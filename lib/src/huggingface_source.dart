import 'dart:io';

import 'package:http/http.dart' as http;

/// Downloads a Laya ONNX bundle (laya.onnx [+ laya.onnx.data], tokenizer/,
/// and a config file) from a Hugging Face repo into a local cache directory,
/// then returns that directory so it can be opened the same way as a fully
/// local bundle.
///
/// ponytail: files are skipped if already present in [cacheDir], with no
/// checksum/revision verification. Upgrade path: store a manifest (revision +
/// sha256 per file, as README.md section C1 describes) and re-download when
/// it's stale or missing.
class HuggingFaceModelSource {
  const HuggingFaceModelSource({
    required this.repoId,
    this.subfolder = '',
    this.revision = 'main',
  });

  /// e.g. "convaiinnovations/laya".
  final String repoId;

  /// e.g. "multilingual" or "typed-decisions"; empty for the repo root.
  final String subfolder;

  final String revision;

  static const _requiredFiles = [
    'laya.onnx',
    'tokenizer/tokenizer.json',
    'tokenizer/tokenizer_config.json',
  ];

  // laya.onnx.data and the two possible config filenames are optional /
  // alternatives, tried best-effort after the required files succeed.
  static const _optionalFiles = ['laya.onnx.data'];
  static const _configFileCandidates = [
    'laya_config.json',
    'rl_agent_config.json',
  ];

  Uri _resolveUri(String relativePath) {
    final repoPath = subfolder.isEmpty
        ? relativePath
        : '$subfolder/$relativePath';
    return Uri.parse(
      'https://huggingface.co/$repoId/resolve/$revision/$repoPath',
    );
  }

  Future<void> _download(
    Uri uri,
    File destination, {
    bool required = true,
  }) async {
    if (destination.existsSync()) return;
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      if (!required) return;
      throw ArgumentError(
        'Failed to download ${uri.toString()}: HTTP ${response.statusCode}',
      );
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(response.bodyBytes);
  }

  /// Downloads any missing files into [cacheDir] and returns that directory.
  Future<Directory> ensureDownloaded(String cacheDir) async {
    final dir = Directory(cacheDir);
    for (final relativePath in _requiredFiles) {
      await _download(
        _resolveUri(relativePath),
        File('$cacheDir/$relativePath'),
      );
    }
    for (final relativePath in _optionalFiles) {
      await _download(
        _resolveUri(relativePath),
        File('$cacheDir/$relativePath'),
        required: false,
      );
    }
    final hasConfig = _configFileCandidates.any(
      (name) => File('$cacheDir/$name').existsSync(),
    );
    if (!hasConfig) {
      for (final name in _configFileCandidates) {
        final response = await http.get(_resolveUri(name));
        if (response.statusCode == 200) {
          final file = File('$cacheDir/$name');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes);
          break;
        }
      }
    }
    return dir;
  }
}
