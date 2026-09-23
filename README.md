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

final laya = await Laya.load();
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

`Laya.predict` is synchronous. `Laya.predictAsync` runs inference through the runtime worker isolate and is suitable for Flutter UI code. Questions can be `choice`, `score`, or `noul`.

For local model download, ONNX conversion, and bundle setup, see the [local model guide](tool/README.md).

## License

The `laya_dart` package is released under the MIT License. Laya model weights retain the model publisher's license.
