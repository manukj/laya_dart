# Local Laya model guide

This guide is for running a downloaded Laya checkpoint locally. The Dart
package loads an ONNX bundle; it does not load PyTorch `safetensors` files
directly.

## 1. Download the model

Download the checkpoint from the official [Laya model page](https://huggingface.co/convaiinnovations/laya).
Keep the downloaded checkpoint outside the Dart package if it is not intended
to be committed.

The checkpoint should contain the model weights, encoder configuration,
tokenizer files, and `rl_agent_config.json`.

## 2. Prepare the export environment

From the `laya_dart` directory:

```bash
python3 -m venv tool/.venv
tool/.venv/bin/pip install torch transformers safetensors onnx onnxruntime onnxscript
```

The export script is:

```text
tool/export_local_model.py
```

It reads the local checkpoint only. It does not download model weights.

## 3. Export to ONNX

Run:

```bash
tool/.venv/bin/python tool/export_local_model.py \
  /path/to/laya \
  /path/to/laya-onnx
```

The destination must be different from the source checkpoint. The output
directory should contain:

```text
laya-onnx/
  laya.onnx
  laya.onnx.data       # external weights, when produced by the exporter
  laya_config.json
  tokenizer/
    tokenizer.json
    tokenizer_config.json
```

The exporter also runs a PyTorch-versus-ONNX output check and writes a
`manifest.json` with hashes and maximum output differences.

## 4. Load the local bundle

Pass the bundle directory to `Laya.load`:

```dart
final laya = await Laya.load('/path/to/laya-onnx');
final result = await laya.predictAsync(state, questions);
await laya.close();
```

Keep `laya.onnx` and `laya.onnx.data` beside each other. The tokenizer and
configuration must come from the same checkpoint as the weights.

## Troubleshooting

If export fails, check that the checkpoint, encoder configuration, and
`rl_common.py` come from the same Laya revision. If loading fails, verify that
the ONNX graph and external data file are both present and that the bundle's
input/output names match the Laya ONNX contract.
