"""Export the existing English safetensors checkpoint for local Dart use.

Usage: tool/.venv/bin/python tool/export_local_model.py ../laya models/laya
Derived from pinned tool/reference/export_onnx.py (MIT). Does not download.
The input checkpoint is read only; every output is written to the destination.
"""
import os
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
import sys
sys.dont_write_bytecode = True
import hashlib
import json
from pathlib import Path
import shutil
import numpy as np
import torch
from safetensors.torch import load_file


def digest(path):
    with open(path, 'rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    source, dest = (Path(p).resolve() for p in sys.argv[1:3])
    if source == dest or source in dest.parents:
        raise ValueError('Export destination must be outside the source checkpoint')
    dest.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(source))
    from rl_common import build_model
    cfg = json.loads((source/'rl_agent_config.json').read_text())
    torch.manual_seed(1234)
    torch.set_num_threads(4)
    model = build_model(cfg, encoder_dir=str(source/'encoder'))
    model.load_state_dict(load_file(str(source/'model.safetensors')), strict=True)
    model.eval()
    model.encoder.config.reference_compile = False

    class Wrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
        def forward(self, input_ids, attention_mask, marker_pos, marker_mask, qtype):
            logits, act = self.model(input_ids, attention_mask, marker_pos, marker_mask, qtype)
            return logits, torch.softmax(act.float(), -1)

    wrapper = Wrapper(model)
    inputs = (torch.randint(5,1000,(2,40)), torch.ones(2,40,dtype=torch.long),
              torch.tensor([[3,9,15,21],[3,9,0,0]]),
              torch.tensor([[True,True,True,True],[True,True,False,False]]),
              torch.tensor([0,2]))
    inputs[1][1,30:] = 0
    names = ['input_ids','attention_mask','marker_pos','marker_mask','qtype']
    batch, seq, options = torch.export.Dim('batch'), torch.export.Dim('seq',min=8), torch.export.Dim('options',min=2)
    dynamic = {'input_ids':{0:batch,1:seq},'attention_mask':{0:batch,1:seq},'marker_pos':{0:batch,1:options},'marker_mask':{0:batch,1:options},'qtype':{0:batch}}
    print('Exporting FP32 graph with external weights...', flush=True)
    program = torch.onnx.export(wrapper,inputs,opset_version=18,dynamo=True,optimize=True,
                                input_names=names,output_names=['logits','act_probs'],dynamic_shapes=dynamic)
    program.save(str(dest/'laya.onnx'),external_data=True)
    shutil.copytree(source/'tokenizer',dest/'tokenizer',dirs_exist_ok=True)
    (dest/'laya_config.json').write_text(json.dumps({k:cfg[k] for k in ['max_len','head_max_len','temperature','temperature_by_options']},indent=2)+'\n')
    with torch.no_grad():
        expected = [t.numpy() for t in wrapper(*inputs)]
    del program, wrapper, model
    import gc
    gc.collect()
    import onnxruntime as ort
    session = ort.InferenceSession(str(dest/'laya.onnx'),providers=['CPUExecutionProvider'])
    actual = session.run(['logits','act_probs'],dict(zip(names,[t.numpy() for t in inputs])))
    differences = {}
    for name, left, right in zip(['logits','act_probs'],actual,expected):
        np.testing.assert_allclose(left,right,atol=1e-4,rtol=1e-4)
        differences[name] = float(np.max(np.abs(left-right)))
    manifest = {'origin':'local safetensors export; distinct from the published ONNX artifact',
                'source_sha256':{name:digest(source/name) for name in ['model.safetensors','rl_agent_config.json','encoder/config.json','rl_common.py']},
                'versions':{'torch':torch.__version__,'onnxruntime':ort.__version__},
                'pytorch_parity_max_abs_error':differences,
                'files':{str(p.relative_to(dest)):{'bytes':p.stat().st_size,'sha256':digest(p)} for p in dest.rglob('*') if p.is_file() and p.name!='manifest.json'}}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'destination':str(dest),'parity':differences}),flush=True)


if __name__ == '__main__':
    main()
