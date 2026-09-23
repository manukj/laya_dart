"""Generate tiny ONNX Identity graphs without third-party dependencies.

ModelProto IR 8, opset 13, one input/output of shape [2]. Integration tests
validate these protobufs by executing them with native ONNX Runtime.
"""
from pathlib import Path
import hashlib
import json


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def integer(field, value):
    return varint(field << 3) + varint(value)


def message(field, value):
    if isinstance(value, str):
        value = value.encode()
    return varint((field << 3) | 2) + varint(len(value)) + value


def identity(dtype):
    shape = message(1, integer(1, 2))
    tensor_type = integer(1, dtype) + message(2, shape)
    def info(name):
        return message(1, name) + message(2, message(1, tensor_type))
    node = message(1, 'input') + message(2, 'output') + message(4, 'Identity')
    graph = (message(1, node) + message(2, 'identity') +
             message(11, info('input')) + message(12, info('output')))
    return integer(1, 8) + message(2, 'laya_dart') + message(7, graph) + message(8, integer(2, 13))


if __name__ == '__main__':
    dest = Path(__file__).resolve().parents[1] / 'example/assets/runtime'
    dest.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, dtype in [('float32', 1), ('int64', 7), ('bool', 9)]:
        data = identity(dtype)
        filename = f'identity_{name}.onnx'
        (dest / filename).write_bytes(data)
        manifest[filename] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
