import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
// Direct binding import: works around onnxruntime_v2 passing the model path
// as UTF-8 on Windows, where ORT expects wchar_t (ORTCHAR_T). See
// OrtSession.fromFile in onnxruntime_v2.
// ignore: implementation_imports
import 'package:onnxruntime_v2/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

import 'batch.dart';

/// Owns one ORT session. The shared ORT environment stays process-resident.
final class LayaRuntime {
  static bool _environmentInitialized = false;

  factory LayaRuntime.open(File modelFile) {
    if (!modelFile.existsSync()) {
      throw ArgumentError('Model file not found: ${modelFile.path}');
    }
    if (!_environmentInitialized) {
      OrtEnv.instance.init();
      _environmentInitialized = true;
    }
    OrtSessionOptions? options;
    final OrtSession session;
    int? windowsOptionsAddress;
    try {
      if (Platform.isWindows) {
        // onnxruntime_v2 encodes the path as UTF-8, but the Windows ORT
        // build expects UTF-16 (wchar_t), which surfaces as garbled CJK in
        // the error plus code=3 (file doesn't exist). Create the session
        // with a wide-char path instead.
        final created = _createWindowsSession(modelFile.path);
        session = created.session;
        windowsOptionsAddress = created.optionsAddress;
      } else {
        options = OrtSessionOptions();
        session = OrtSession.fromFile(modelFile, options);
      }
    } catch (_) {
      options?.release();
      rethrow;
    }
    const inputs = {'input_ids', 'attention_mask', 'marker_pos', 'marker_mask', 'qtype'};
    const outputs = {'logits', 'act_probs'};
    if (session.inputNames.toSet().difference(inputs).isNotEmpty ||
        inputs.difference(session.inputNames.toSet()).isNotEmpty ||
        outputs.difference(session.outputNames.toSet()).isNotEmpty) {
      final nativeAddress = windowsOptionsAddress;
      if (nativeAddress != null) {
        session.release().whenComplete(
          () => _releaseNativeOptions(nativeAddress),
        );
      } else {
        session.release().whenComplete(options!.release);
      }
      throw ArgumentError('Model does not expose the required Laya inputs/outputs');
    }
    return LayaRuntime._(
      session,
      windowsOptionsAddress == null ? options : null,
      windowsOptionsAddress,
    );
  }

  /// Creates an ORT session on Windows with the model path encoded as
  /// UTF-16 (wchar_t). The returned options address is natively owned and
  /// must be released with [_releaseNativeOptions].
  static ({OrtSession session, int optionsAddress}) _createWindowsSession(
    String modelPath,
  ) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final optionsOut = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    try {
      OrtStatus.checkOrtStatus(
        api.CreateSessionOptions.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>,
          )
        >()(optionsOut),
      );
    } catch (_) {
      calloc.free(optionsOut);
      rethrow;
    }
    final nativeOptions = optionsOut.value;
    calloc.free(optionsOut);

    final sessionOut = calloc<ffi.Pointer<bg.OrtSession>>();
    final pathPtr = modelPath.toNativeUtf16();
    final int sessionAddress;
    try {
      // The generated binding types model_path as Pointer<Char>, but on
      // Windows the ABI expects wchar_t*. Reinterpret the function pointer
      // (pointer cast is unchecked) so asFunction sees the wide signature.
      final createSessionWchar = api.CreateSession.cast<
        ffi.NativeFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtEnv>,
            ffi.Pointer<ffi.WChar>,
            ffi.Pointer<bg.OrtSessionOptions>,
            ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
          )
        >
      >();
      final statusPtr = createSessionWchar.asFunction<
        bg.OrtStatusPtr Function(
          ffi.Pointer<bg.OrtEnv>,
          ffi.Pointer<ffi.WChar>,
          ffi.Pointer<bg.OrtSessionOptions>,
          ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
        )
      >()(OrtEnv.instance.ptr, pathPtr.cast<ffi.WChar>(), nativeOptions,
          sessionOut);
      OrtStatus.checkOrtStatus(statusPtr);
      sessionAddress = sessionOut.value.address;
    } catch (_) {
      _releaseNativeOptions(nativeOptions.address);
      rethrow;
    } finally {
      calloc.free(pathPtr);
      calloc.free(sessionOut);
    }
    try {
      return (
        session: OrtSession.fromAddress(sessionAddress),
        optionsAddress: nativeOptions.address,
      );
    } catch (_) {
      OrtEnv.instance.ortApiPtr.ref.ReleaseSession.asFunction<
        void Function(ffi.Pointer<bg.OrtSession>)
      >()(ffi.Pointer<bg.OrtSession>.fromAddress(sessionAddress));
      _releaseNativeOptions(nativeOptions.address);
      rethrow;
    }
  }

  static void _releaseNativeOptions(int address) {
    OrtEnv.instance.ortApiPtr.ref.ReleaseSessionOptions.asFunction<
      void Function(ffi.Pointer<bg.OrtSessionOptions>)
    >()(ffi.Pointer<bg.OrtSessionOptions>.fromAddress(address));
  }

  LayaRuntime._(this._session, this._options, [this._nativeOptionsAddress]);

  final OrtSession _session;
  final OrtSessionOptions? _options;
  final int? _nativeOptionsAddress;
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
      final nativeOptionsAddress = _nativeOptionsAddress;
      if (nativeOptionsAddress != null) {
        _releaseNativeOptions(nativeOptionsAddress);
      } else {
        _options?.release();
      }
    }
  }
}
