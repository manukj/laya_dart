![Laya demo](https://raw.githubusercontent.com/manukj/laya_dart/main/example/lib/demo/demo.GIF)

# laya_dart

[Laya](https://huggingface.co/convaiinnovations/laya) is an open-source System 1 decision model. It evaluates a state against typed questions and returns choices, scores, and yes/no probabilities.

`laya_dart` runs Laya locally in Flutter or Dart. It uses the [`onnxruntime_v2`](https://pub.dev/packages/onnxruntime_v2) Flutter FFI wrapper, backed by [ONNX Runtime](https://onnxruntime.ai/), to execute the model on the device.

## Install

```yaml
dependencies:
  laya_dart: ^0.0.1
```

## Use

```dart
import 'package:laya_dart/laya_dart.dart';

// Downloads uppppiiiii/laya_onnx once, then reuses the verified cache.
final laya = await Laya.load();
// Or: await Laya.load('/path/to/local/laya-bundle'); // No network access.
final result = await laya.predictAsync(
  'The customer was charged twice and wants a refund.',
  {
    'department': LayaQuestion.choice(
      instructions: 'Which team should handle this message?',
      criteria: {
        'billing': 'payments and refunds',
        'technical': 'bugs and outages',
        'other': 'anything else',
      },
    ),
    'refund': LayaQuestion.noul(
      instructions: 'Does the customer request a refund?',
    ),
  },
);
await laya.close();
```

`Laya.predict` is synchronous. `Laya.predictAsync` queues native inference on a worker isolate. Questions can be `choice`, `score`, or `noul`. Loading and tokenization currently run on the calling isolate; profile their UI impact before shipping.

Await `laya.close()` to drain accepted requests and release the session. Repeated closes share the same completion. New requests after close and synchronous inference while async requests are pending are rejected. The shared ORT environment remains process-resident so closing one session cannot invalidate another. Native inference has no timeout/cancellation: a caller-side timeout does not stop it.

### Hugging Face model and pinned downloads

`Laya.load()` downloads the default [`uppppiiiii/laya_onnx`](https://huggingface.co/uppppiiiii/laya_onnx) bundle from Hugging Face at the immutable commit [`b3930f0f1aed41bb6a4493eafdca9d19ee0d86f5`](https://huggingface.co/uppppiiiii/laya_onnx/tree/b3930f0f1aed41bb6a4493eafdca9d19ee0d86f5). It includes `laya.onnx`, its required `laya.onnx.data` external weights, `rl_agent_config.json`, and the tokenizer files. The bundle requires roughly 1.7 GB of download/storage.

Every downloaded file is pinned to its SHA-256 checksum. The package downloads into application-support storage once, verifies it, and reuses that versioned cache on later runs. To stay fully offline or load a different compatible bundle, pass its directory explicitly: `Laya.load('/path/to/local/laya-bundle')`.

Downloads stream to staging and publish into a versioned directory only after checksum validation. Cached files are checked again before reuse. Old versions are retained; corruption produces an actionable error. `ensureDownloaded` returns the actual version directory; use that path, not the cache root. Process crashes can leave unused staging directories, which may be removed once no downloads are running.

### Verification pending

The latest runtime and downloader changes are implemented but not yet tested. Before release: run unit/analyzer checks; test malformed bundles, inference failure recovery, overlap and close-during-inference, two simultaneous sessions, download interruption/checksum failures/cache updates; then measure cold load, tokenization, warm inference and memory on physical Android/iOS, including offline restart, release/profile builds and Android 16 KB pages. Accelerator selection and smaller model variants remain deferred pending parity and performance/quality evaluation.

For local model download, ONNX conversion, and bundle setup, see the [local model guide](tool/README.md).

## License

The `laya_dart` package is released under the MIT License. Laya model weights retain the model publisher's license.
