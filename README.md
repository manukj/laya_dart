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

final laya = await Laya.load(); // Downloads once, then reuses the cache.
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

### Pinned downloads

`Laya.load()` downloads the English `receptron/laya-onnx` bundle at commit `68f27dfe5a27a54fb2b1fefc432f43f972e90868` into application support storage, then reuses its verified cache on subsequent calls. Model and external-weight hashes are pinned; config/tokenizer hashes are captured over HTTPS on first download and saved for subsequent validation. The bundle requires roughly 1.7 GB of download/storage. `Laya.load(path)` is always local and offline. Fresh downloads require repository access; HTTP errors are reported (this development environment currently returns 403).

Downloads stream to staging and publish into a versioned directory only after checksum validation. Cached files are checked again before reuse. Old versions are retained; corruption produces an actionable error. `ensureDownloaded` returns the actual version directory; use that path, not the cache root. Process crashes can leave unused staging directories, which may be removed once no downloads are running.

### Verification pending

The latest runtime and downloader changes are implemented but not yet tested. Before release: run unit/analyzer checks; test malformed bundles, inference failure recovery, overlap and close-during-inference, two simultaneous sessions, download interruption/checksum failures/cache updates; then measure cold load, tokenization, warm inference and memory on physical Android/iOS, including offline restart, release/profile builds and Android 16 KB pages. Accelerator selection and smaller model variants remain deferred pending parity and performance/quality evaluation.

For local model download, ONNX conversion, and bundle setup, see the [local model guide](tool/README.md).

## License

The `laya_dart` package is released under the MIT License. Laya model weights retain the model publisher's license.
