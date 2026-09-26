import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A snapshot of a Laya bundle download.
final class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.fileName,
    required this.bytesReceived,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
  });

  final String fileName;
  final int bytesReceived;
  final int? totalBytes;
  final int completedFiles;
  final int totalFiles;
}

typedef ModelDownloadProgressCallback =
    void Function(ModelDownloadProgress progress);

/// Downloads an immutable, checksum-pinned bundle into a versioned cache.
/// [sha256ByFile] must include every external weight file referenced by ONNX.
class HuggingFaceModelSource {
  static const _defaultRepo = 'uppppiiiii/laya_onnx';
  static const _defaultRevision = 'b3930f0f1aed41bb6a4493eafdca9d19ee0d86f5';
  static const _defaultHashes = <String, String>{
    'laya.onnx':
        'a0ed62e1147e33edfdf385cb813c513618cf0723be13faab9034dd196638c4bd',
    'laya.onnx.data':
        '487746363a8da57bcadb4345352997d22a0fb90d70aa22c6856668d023242aba',
    'rl_agent_config.json':
        'ae287b56bbcf5f8c4f4541ae9dfd00c914c4c48b940b8398c3058af37ba92bbd',
    'tokenizer/tokenizer.json':
        '6c8aaa9a542084f2457eab775d4eeb51f92a70c0fd9de28d5edb0ddec3c08d30',
    'tokenizer/tokenizer_config.json':
        '50044de60daaa73df97d262e15a40d4faf0160e7d742df64b377877a1320dd12',
  };

  /// Installs the package's default immutable, checksum-pinned bundle.
  static Future<Directory> ensureDefaultDownloaded(
    String cacheDir, {
    ModelDownloadProgressCallback? onProgress,
  }) async {
    return HuggingFaceModelSource(
      repoId: _defaultRepo,
      revision: _defaultRevision,
      sha256ByFile: _defaultHashes,
    ).ensureDownloaded(cacheDir, onProgress: onProgress);
  }

  HuggingFaceModelSource({
    required this.repoId,
    required this.revision,
    required Map<String, String> sha256ByFile,
    this.subfolder = '',
  }) : sha256ByFile = Map.unmodifiable(sha256ByFile) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$').hasMatch(repoId) ||
        !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(revision)) {
      throw ArgumentError(
        'Supply a Hugging Face owner/repo and full commit SHA',
      );
    }
    if (subfolder.isNotEmpty) _validatePath(subfolder);
    for (final entry in sha256ByFile.entries) {
      _validatePath(entry.key);
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry.value)) {
        throw ArgumentError('Invalid SHA-256 for ${entry.key}');
      }
    }
    for (final name in [
      'laya.onnx',
      'tokenizer/tokenizer.json',
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
    if (path.contains('\\') ||
        path
            .split('/')
            .any(
              (part) =>
                  part.isEmpty ||
                  part == '.' ||
                  part == '..' ||
                  !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(part),
            )) {
      throw ArgumentError('Unsafe bundle path: $path');
    }
  }

  String get _manifest {
    final names = sha256ByFile.keys.toList()..sort();
    return jsonEncode({
      'repo': repoId,
      'revision': revision,
      'subfolder': subfolder,
      'files': {
        for (final name in names) name: sha256ByFile[name]!.toLowerCase(),
      },
    });
  }

  Future<bool> _valid(Directory dir) async {
    for (final entry in sha256ByFile.entries) {
      final file = File('${dir.path}/${entry.key}');
      if (!await file.exists() ||
          (await sha256.bind(file.openRead()).first).toString() !=
              entry.value.toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  /// Returns a complete versioned directory. Use the returned path to load it.
  /// Old versions remain available for sessions already using them.
  Future<Directory> ensureDownloaded(
    String cacheDir, {
    ModelDownloadProgressCallback? onProgress,
  }) async {
    final root = await Directory(cacheDir).create(recursive: true);
    final key = sha256.convert(utf8.encode(_manifest)).toString();
    final target = Directory('${root.path}/$key');
    final lock = await File(
      '${root.path}/$key.lock',
    ).open(mode: FileMode.append);
    await lock.lock(FileLock.blockingExclusive);
    Directory? staging;
    final client = http.Client();
    try {
      if (await target.exists()) {
        if (await _valid(target)) return target;
        throw StateError(
          'Corrupt cached bundle at ${target.path}. '
          'Use a fresh cache directory or remove that version after closing its sessions.',
        );
      }
      staging = await root.createTemp('.laya-download-');
      final entries = sha256ByFile.entries.toList();
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        final uri = Uri.https(
          'huggingface.co',
          '/$repoId/resolve/$revision/'
              '${subfolder.isEmpty ? '' : '$subfolder/'}${entry.key}',
        );
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode != 200) {
          throw HttpException(
            'HTTP ${response.statusCode} downloading ${entry.key}',
            uri: uri,
          );
        }
        final file = File('${staging.path}/${entry.key}');
        await file.parent.create(recursive: true);
        final sink = file.openWrite();
        var bytesReceived = 0;
        final totalBytes = response.contentLength;
        void report() => onProgress?.call(
          ModelDownloadProgress(
            fileName: entry.key,
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            completedFiles: index,
            totalFiles: entries.length,
          ),
        );
        report();
        try {
          await for (final chunk in response.stream) {
            bytesReceived += chunk.length;
            sink.add(chunk);
            report();
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if ((await sha256.bind(file.openRead()).first).toString() !=
            entry.value.toLowerCase()) {
          throw FormatException('SHA-256 mismatch for ${entry.key}');
        }
        onProgress?.call(
          ModelDownloadProgress(
            fileName: entry.key,
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            completedFiles: index + 1,
            totalFiles: entries.length,
          ),
        );
      }
      await File(
        '${staging.path}/bundle-manifest.json',
      ).writeAsString(_manifest, flush: true);
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
