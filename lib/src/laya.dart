import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'batch.dart';
import 'byte_level_bpe.dart';
import 'config.dart';
import 'decoding.dart';
import 'huggingface_source.dart';
import 'questions.dart';
import 'runtime.dart';
import 'tokenizer_adapter.dart';

/// Loads a Laya bundle (laya.onnx + tokenizer/ + config) from a local
/// directory or a Hugging Face repo, and answers typed questions about a
/// state. See README.md section 3 for the expected bundle layout.
final class Laya {
  Laya._(this._tokenizer, this._config, this._runtime);

  /// Opens [modelLocalDir] without network access. When omitted, downloads
  /// the default pinned English bundle into application support storage,
  /// or reuses its checksum-verified cache.
  static Future<Laya> load([String? modelLocalDir]) async {
    if (modelLocalDir != null) return Laya._fromDirectory(modelLocalDir);
    final cacheDir = '${(await getApplicationSupportDirectory()).path}/laya';
    final directory = await HuggingFaceModelSource.ensureDefaultDownloaded(cacheDir);
    return Laya._fromDirectory(directory.path);
  }

  factory Laya._fromDirectory(String modelDir) {
    final modelFile = File('$modelDir/laya.onnx');
    if (!modelFile.existsSync() || modelFile.lengthSync() == 0) {
      throw ArgumentError('Missing or empty model file: ${modelFile.path}');
    }
    final tokenizerDir = Directory('$modelDir/tokenizer');
    final tokenizerJsonFile = File('${tokenizerDir.path}/tokenizer.json');
    final tokenizerConfigFile = File(
      '${tokenizerDir.path}/tokenizer_config.json',
    );
    if (!tokenizerJsonFile.existsSync() || !tokenizerConfigFile.existsSync()) {
      throw ArgumentError('Missing tokenizer files under ${tokenizerDir.path}');
    }
    final configFile =
        [
          File('$modelDir/laya_config.json'),
          File('$modelDir/rl_agent_config.json'),
        ].firstWhere(
          (f) => f.existsSync(),
          orElse: () => throw ArgumentError(
            'Missing laya_config.json or rl_agent_config.json in $modelDir',
          ),
        );

    final LayaTokenizer tokenizer;
    final LayaConfig config;
    try {
      tokenizer = ByteLevelBpeTokenizer.fromJson(
        jsonDecode(tokenizerJsonFile.readAsStringSync())
            as Map<String, dynamic>,
        jsonDecode(tokenizerConfigFile.readAsStringSync())
            as Map<String, dynamic>,
      );
      config = LayaConfig.fromJson(
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>,
      );
    } on FormatException catch (e) {
      throw ArgumentError('Invalid Laya bundle in $modelDir: ${e.message}');
    } on TypeError catch (e) {
      throw ArgumentError('Invalid JSON structure in Laya bundle $modelDir: $e');
    } on FileSystemException catch (e) {
      throw ArgumentError('Cannot read Laya bundle $modelDir: $e');
    }

    final LayaRuntime runtime;
    try {
      runtime = LayaRuntime.open(modelFile);
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw ArgumentError('Failed to open ${modelFile.path}: $e');
    }
    return Laya._(tokenizer, config, runtime);
  }

  final LayaTokenizer _tokenizer;
  final LayaConfig _config;
  final LayaRuntime _runtime;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Answers every question in [questions] against [state] in one forward pass.
  /// [questions] must be non-empty. Each value is either an already-built
  /// [LayaQuestion] (see `LayaQuestion.choice`/`.score`/`.noul`) or the
  /// Jev-style request shape
  /// `{"type": "choice"|"score"|"noul", "instructions": ..., "criteria": ...}`.
  Map<String, Object> predict(Object? state, Map<String, Object> questions) {
    if (_closed) throw StateError('Laya instance is closed');
    final batch = _buildBatch(state, questions);
    final result = _runtime.run(batch);
    return decodeOutputs(
      batch: batch,
      config: _config,
      logits: result.logits,
      actionProbabilities: result.actionProbabilities,
    );
  }

  /// Like [predict], but runs the native forward pass on a
  /// worker isolate so the caller's isolate (e.g. the UI isolate) stays
  /// responsive while it awaits.
  Future<Map<String, Object>> predictAsync(
    Object? state,
    Map<String, Object> questions,
  ) async {
    if (_closed) throw StateError('Laya instance is closed');
    final batch = _buildBatch(state, questions);
    final result = await _runtime.runAsync(batch);
    return decodeOutputs(
      batch: batch,
      config: _config,
      logits: result.logits,
      actionProbabilities: result.actionProbabilities,
    );
  }

  LayaBatch _buildBatch(Object? state, Map<String, Object> questions) {
    if (questions.isEmpty) {
      throw ArgumentError('At least one question is required');
    }
    final parsed = {
      for (final entry in questions.entries)
        entry.key: switch (entry.value) {
          final LayaQuestion q => q,
          final Map<String, Object?> json => LayaQuestion.fromJson(json),
          _ => throw ArgumentError(
            'Question "${entry.key}" must be a LayaQuestion or a '
            '{"type", "instructions", "criteria"} map',
          ),
        },
    };
    return LayaBatch.build(
      state: state,
      questions: parsed,
      tokenizer: _tokenizer,
      config: _config,
    );
  }

  /// Releases native ORT resources. Safe to call more than once; further
  /// calls to [predict] after closing throw a [StateError].
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closed = true;
    return _closeFuture = _runtime.close();
  }
}
