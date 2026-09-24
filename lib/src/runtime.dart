import 'dart:io';
import 'dart:isolate';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import 'batch.dart';

/// Owns one ORT session. The shared ORT environment stays process-resident.
final class LayaRuntime {
  LayaRuntime._(this._session, this._options);
  static bool _environmentInitialized = false;

  factory LayaRuntime.open(File modelFile) {
    if (!modelFile.existsSync()) {
      throw ArgumentError('Model file not found: ${modelFile.path}');
    }
    if (!_environmentInitialized) {
      OrtEnv.instance.init();
      _environmentInitialized = true;
    }
    final options = OrtSessionOptions();
    final OrtSession session;
    try {
      session = OrtSession.fromFile(modelFile, options);
    } catch (_) {
      options.release();
      rethrow;
    }
    const inputs = {'input_ids', 'attention_mask', 'marker_pos', 'marker_mask', 'qtype'};
    const outputs = {'logits', 'act_probs'};
    if (session.inputNames.toSet().difference(inputs).isNotEmpty ||
        inputs.difference(session.inputNames.toSet()).isNotEmpty ||
        outputs.difference(session.outputNames.toSet()).isNotEmpty) {
      session.release().whenComplete(options.release);
      throw ArgumentError('Model does not expose the required Laya inputs/outputs');
    }
    return LayaRuntime._(session, options);
  }

  final OrtSession _session;
  final OrtSessionOptions _options;
  bool _closed = false;
  int _pending = 0;
  Future<void>? _closeFuture;
  Future<void> _lastAsyncOperation = Future<void>.value();

  /// Runs [batch] and returns raw (flattened) `logits` and `act_probs`.
  ({List<double> logits, List<double> actionProbabilities}) run(
    LayaBatch batch,
  ) {
    if (_closed) throw StateError('LayaRuntime is closed');
    if (_pending != 0) {
      throw StateError('Await pending async requests before synchronous inference');
    }
    return _execute(_session, batch);
  }

  static ({List<double> logits, List<double> actionProbabilities}) _execute(
    OrtSession session, LayaBatch batch,
  ) {
    final runOptions = OrtRunOptions();
    final inputs = <String, OrtValue>{};
    List<OrtValue?> outputs = const [];
    try {
      _buildInputs(batch, inputs);
      outputs = session.run(runOptions, inputs, ['logits', 'act_probs']);
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

  /// Queues inference on a worker isolate without a native-work timeout.
  /// Resources stay alive until the synchronous native call has returned.
  Future<({List<double> logits, List<double> actionProbabilities})> runAsync(
    LayaBatch batch,
  ) async {
    if (_closed) throw StateError('LayaRuntime is closed');
    _pending++;
    final operation = _lastAsyncOperation.then((_) async {
      try {
        return await _runInWorker(_session.address, batch);
      } finally {
        _pending--;
      }
    });
    // Keep the queue alive after a failed request, while preserving the
    // original error for the caller awaiting this operation.
    _lastAsyncOperation = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  static Future<({List<double> logits, List<double> actionProbabilities})>
  _runInWorker(int address, LayaBatch batch) => Isolate.run(
    () => _execute(OrtSession.fromAddress(address), batch),
  );

  static void _buildInputs(LayaBatch batch, Map<String, OrtValue> inputs) {
    inputs['input_ids'] = OrtValueTensor.createTensorWithDataList(batch.inputIds, [
      batch.size,
      batch.sequenceLength,
    ]);
    inputs['attention_mask'] = OrtValueTensor.createTensorWithDataList(
      batch.attentionMask,
      [batch.size, batch.sequenceLength],
    );
    inputs['marker_pos'] = OrtValueTensor.createTensorWithDataList(
      batch.markerPositions,
      [batch.size, batch.optionCount],
    );
    inputs['marker_mask'] = OrtValueTensor.createTensorWithDataList(batch.markerMask, [
      batch.size,
      batch.optionCount,
    ]);
    inputs['qtype'] = OrtValueTensor.createTensorWithDataList(batch.questionTypes, [
      batch.size,
    ]);
  }

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
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closed = true;
    return _closeFuture = _release();
  }

  Future<void> _release() async {
    await _lastAsyncOperation;
    try {
      await _session.release();
    } finally {
      _options.release();
    }
  }
}
