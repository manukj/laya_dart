import 'dart:io';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import 'batch.dart';

/// Owns one ORT session + env lifetime, and runs one [LayaBatch] through it.
final class LayaRuntime {
  LayaRuntime._(this._session, this._options);

  factory LayaRuntime.open(File modelFile) {
    if (!modelFile.existsSync()) {
      throw ArgumentError('Model file not found: ${modelFile.path}');
    }
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    final OrtSession session;
    try {
      session = OrtSession.fromFile(modelFile, options);
    } catch (_) {
      options.release();
      rethrow;
    }
    return LayaRuntime._(session, options);
  }

  final OrtSession _session;
  final OrtSessionOptions _options;
  bool _closed = false;

  /// Runs [batch] and returns raw (flattened) `logits` and `act_probs`.
  ({List<double> logits, List<double> actionProbabilities}) run(
    LayaBatch batch,
  ) {
    if (_closed) throw StateError('LayaRuntime is closed');
    final runOptions = OrtRunOptions();
    final inputs = _buildInputs(batch);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(runOptions, inputs, ['logits', 'act_probs']);
      return _readOutputs(outputs);
    } finally {
      runOptions.release();
      for (final input in inputs.values) {
        input.release();
      }
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  /// Like [run], but executes on the package's persistent worker isolate
  /// (via `OrtSession.runAsync`) so the calling isolate (e.g. the UI isolate)
  /// stays responsive during the native forward pass.
  Future<({List<double> logits, List<double> actionProbabilities})> runAsync(
    LayaBatch batch,
  ) async {
    if (_closed) throw StateError('LayaRuntime is closed');
    final runOptions = OrtRunOptions();
    final inputs = _buildInputs(batch);
    List<OrtValue?> outputs = const [];
    try {
      outputs =
          await _session.runAsync(runOptions, inputs, [
            'logits',
            'act_probs',
          ]) ??
          const [];
      return _readOutputs(outputs);
    } finally {
      runOptions.release();
      for (final input in inputs.values) {
        input.release();
      }
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  Map<String, OrtValue> _buildInputs(LayaBatch batch) => {
    'input_ids': OrtValueTensor.createTensorWithDataList(batch.inputIds, [
      batch.size,
      batch.sequenceLength,
    ]),
    'attention_mask': OrtValueTensor.createTensorWithDataList(
      batch.attentionMask,
      [batch.size, batch.sequenceLength],
    ),
    'marker_pos': OrtValueTensor.createTensorWithDataList(
      batch.markerPositions,
      [batch.size, batch.optionCount],
    ),
    'marker_mask': OrtValueTensor.createTensorWithDataList(batch.markerMask, [
      batch.size,
      batch.optionCount,
    ]),
    'qtype': OrtValueTensor.createTensorWithDataList(batch.questionTypes, [
      batch.size,
    ]),
  };

  static ({List<double> logits, List<double> actionProbabilities}) _readOutputs(
    List<OrtValue?> outputs,
  ) {
    if (outputs.length != 2) {
      throw StateError(
        'Expected 2 outputs (logits, act_probs), got ${outputs.length}',
      );
    }
    return (
      logits: _flatten(outputs[0]),
      actionProbabilities: _flatten(outputs[1]),
    );
  }

  static List<double> _flatten(OrtValue? value) {
    final tensor = value as OrtValueTensor;
    return (tensor.value as List)
        .expand((row) => row as List)
        .map((v) => (v as num).toDouble())
        .toList();
  }

  /// Releases native resources. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _session.release();
    _options.release();
    OrtEnv.instance.release();
  }
}
