"""Export the Laya decision model (ModernBERT encoder + decision head) to a single ONNX file.

Usage:  .venv/bin/python export_onnx.py [model_dir] [out_dir]
Inputs : input_ids [B,L] int64, attention_mask [B,L] int64, marker_pos [B,K] int64, marker_mask [B,K] bool, qtype [B] int64
Outputs: logits [B,K] float32 (uncalibrated; masked slots = -1e4), act_probs [B,2] float32
"""
import json
import os
import shutil
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "model"))
from rl_common import build_model  # noqa: E402

model_dir = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "model")
out_dir = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else "../onnx")
os.makedirs(out_dir, exist_ok=True)

from safetensors.torch import load_file  # noqa: E402

cfg = json.load(open(os.path.join(model_dir, "rl_agent_config.json")))
model = build_model(cfg, encoder_dir=os.path.join(model_dir, "encoder"))
model.load_state_dict(load_file(os.path.join(model_dir, "model.safetensors")), strict=True)
model.eval()
model.encoder.config.reference_compile = False


class Wrapper(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, input_ids, attention_mask, marker_pos, marker_mask, qtype):
        logits, act = self.m(input_ids, attention_mask, marker_pos, marker_mask, qtype)
        return logits, torch.softmax(act.float(), -1)


w = Wrapper(model)
B, L, K = 2, 40, 4
ex = (
    torch.randint(5, 1000, (B, L)),
    torch.ones(B, L, dtype=torch.long),
    torch.tensor([[3, 9, 15, 21], [3, 9, 0, 0]]),
    torch.tensor([[True, True, True, True], [True, True, False, False]]),
    torch.tensor([0, 2]),
)
ex[1][1, 30:] = 0  # second row padded

out = os.path.join(out_dir, "laya.onnx")
# grad must stay enabled: nn.TransformerEncoderLayer's fused "fast path" (not exportable) is only taken under no_grad.
batch, seq, opts = torch.export.Dim("batch"), torch.export.Dim("seq", min=8), torch.export.Dim("options", min=2)
prog = torch.onnx.export(
    w, ex, opset_version=18, dynamo=True, optimize=True,
    input_names=["input_ids", "attention_mask", "marker_pos", "marker_mask", "qtype"],
    output_names=["logits", "act_probs"],
    dynamic_shapes={"input_ids": {0: batch, 1: seq}, "attention_mask": {0: batch, 1: seq},
                    "marker_pos": {0: batch, 1: opts}, "marker_mask": {0: batch, 1: opts}, "qtype": {0: batch}},
)
prog.save(out, external_data=False)

# ship the tokenizer + calibration config next to the graph
shutil.copytree(os.path.join(model_dir, "tokenizer"), os.path.join(out_dir, "tokenizer"), dirs_exist_ok=True)
json.dump({k: cfg[k] for k in ("max_len", "head_max_len", "temperature", "temperature_by_options")},
          open(os.path.join(out_dir, "laya_config.json"), "w"), indent=1)

# parity check
import onnxruntime as ort  # noqa: E402

with torch.no_grad():
    ref_logits, ref_act = w(*ex)
sess = ort.InferenceSession(out, providers=["CPUExecutionProvider"])
o = sess.run(None, {"input_ids": ex[0].numpy(), "attention_mask": ex[1].numpy(), "marker_pos": ex[2].numpy(),
                    "marker_mask": ex[3].numpy(), "qtype": ex[4].numpy()})
print("max |dlogits| =", np.abs(o[0] - ref_logits.numpy()).max(), " max |dact| =", np.abs(o[1] - ref_act.numpy()).max())
print("wrote", out, "%.0f MB" % (sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir) if f.startswith("laya")) / 1e6))
