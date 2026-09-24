import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Downloads an immutable, checksum-pinned bundle into a versioned cache.
/// [sha256ByFile] must include every external weight file referenced by ONNX.
class HuggingFaceModelSource {
  static const _defaultRepo = 'receptron/laya-onnx';
  static const _defaultRevision = '68f27dfe5a27a54fb2b1fefc432f43f972e90868';

  /// Installs the package's default pinned English bundle. Small-file hashes
  /// are captured over HTTPS on first use; model/weight hashes are pinned here.
  static Future<Directory> ensureDefaultDownloaded(String cacheDir) async {
    final manifestFile = File('$cacheDir/default-$_defaultRevision.json');
    final hashes = <String, String>{};
    if (await manifestFile.exists()) {
      final saved = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      hashes.addAll(saved.cast<String, String>());
    }
    const smallFiles = [
      'laya_config.json',
      'tokenizer/tokenizer.json',
      'tokenizer/tokenizer_config.json',
    ];
    for (final name in smallFiles) {
      if (hashes.containsKey(name)) continue;
      final uri = Uri.https('huggingface.co', '/$_defaultRepo/resolve/$_defaultRevision/$name');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} downloading default Laya bundle. '
            'Retry when the repository is accessible or pass a local directory to Laya.load.', uri: uri);
      }
      hashes[name] = sha256.convert(response.bodyBytes).toString();
    }
    hashes['laya.onnx'] = 'a874eb254b58b0fcb1e7ad56fbb188c29d64e08c9a46b689433e1f52c66dba1e';
    hashes['laya.onnx.data'] = '487746363a8da57bcadb4345352997d22a0fb90d70aa22c6856668d023242aba';
    final directory = await HuggingFaceModelSource(
      repoId: _defaultRepo, revision: _defaultRevision, sha256ByFile: hashes,
    ).ensureDownloaded(cacheDir);
    if (!await manifestFile.exists()) {
      final staging = await Directory('$cacheDir/.default-manifest-').createTemp();
      try {
        final file = await File('${staging.path}/manifest.json').writeAsString(jsonEncode(hashes), flush: true);
        await file.rename(manifestFile.path);
      } finally {
        await staging.delete(recursive: true);
      }
    }
    return directory;
  }

  HuggingFaceModelSource({
    required this.repoId,
    required this.revision,
    required Map<String, String> sha256ByFile,
    this.subfolder = '',
  }) : sha256ByFile = Map.unmodifiable(sha256ByFile) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$').hasMatch(repoId) ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(revision)) {
      throw ArgumentError('Supply a Hugging Face owner/repo and full commit SHA');
    }
    if (subfolder.isNotEmpty) _validatePath(subfolder);
    for (final entry in sha256ByFile.entries) {
      _validatePath(entry.key);
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry.value)) {
        throw ArgumentError('Invalid SHA-256 for ${entry.key}');
      }
    }
    for (final name in [
      'laya.onnx', 'tokenizer/tokenizer.json',
      'tokenizer/tokenizer_config.json',
    ]) {
      if (!sha256ByFile.containsKey(name)) {
        throw ArgumentError('Bundle manifest must include $name');
      }
    }
    if (!sha256ByFile.containsKey('laya_config.json') &&
        !sha256ByFile.containsKey('rl_agent_config.json')) {
      throw ArgumentError('Bundle manifest must include a Laya config');
    }
  }

  final String repoId;
  final String revision;
  final String subfolder;
  final Map<String, String> sha256ByFile;

  static void _validatePath(String path) {
    if (path.contains('\\') || path.split('/').any(
      (part) => part.isEmpty || part == '.' || part == '..' ||
          !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(part),
    )) {
      throw ArgumentError('Unsafe bundle path: $path');
    }
  }

  String get _manifest {
    final names = sha256ByFile.keys.toList()..sort();
    return jsonEncode({
      'repo': repoId, 'revision': revision, 'subfolder': subfolder,
      'files': {for (final name in names) name: sha256ByFile[name]!.toLowerCase()},
    });
  }

  Future<bool> _valid(Directory dir) async {
    for (final entry in sha256ByFile.entries) {
      final file = File('${dir.path}/${entry.key}');
      if (!await file.exists() ||
          (await sha256.bind(file.openRead()).first).toString() !=
              entry.value.toLowerCase()) return false;
    }
    return true;
  }

  /// Returns a complete versioned directory. Use the returned path to load it.
  /// Old versions remain available for sessions already using them.
  Future<Directory> ensureDownloaded(String cacheDir) async {
    final root = await Directory(cacheDir).create(recursive: true);
    final key = sha256.convert(utf8.encode(_manifest)).toString();
    final target = Directory('${root.path}/$key');
    final lock = await File('${root.path}/$key.lock').open(mode: FileMode.append);
    await lock.lock(FileLock.blockingExclusive);
    Directory? staging;
    final client = http.Client();
    try {
      if (await target.exists()) {
        if (await _valid(target)) return target;
        throw StateError('Corrupt cached bundle at ${target.path}. '
            'Use a fresh cache directory or remove that version after closing its sessions.');
      }
      staging = await Directory('${root.path}/.laya-download-').createTemp();
      for (final entry in sha256ByFile.entries) {
        final uri = Uri.https('huggingface.co',
          '/$repoId/resolve/$revision/'
          '${subfolder.isEmpty ? '' : '$subfolder/'}${entry.key}');
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode} downloading ${entry.key}', uri: uri);
        }
        final file = File('${staging.path}/${entry.key}');
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        try {
          await sink.addStream(response.stream);
          await sink.flush();
        } finally {
          await sink.close();
        }
        if ((await sha256.bind(file.openRead()).first).toString() !=
            entry.value.toLowerCase()) {
          throw FormatException('SHA-256 mismatch for ${entry.key}');
        }
      }
      await File('${staging.path}/bundle-manifest.json').writeAsString(_manifest, flush: true);
      if (await target.exists()) {
        if (await _valid(target)) return target;
        throw StateError('Conflicting cache directory: ${target.path}');
      }
      return await staging.rename(target.path);
    } finally {
      client.close();
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await lock.close();
    }
  }
}
