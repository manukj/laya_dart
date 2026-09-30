## 0.0.4

* Fix Windows model loading by creating ONNX Runtime sessions with UTF-16
  model paths.

## 0.0.3

* Download the default Laya bundle from `uppppiiiii/laya_onnx` at a pinned
  Hugging Face revision, with SHA-256 verification for every bundle file.
* Run asynchronous native inference on a worker isolate and safely drain
  queued requests when closing a Laya session.
* Document the default model, local/offline loading, and all question types.
* Add package repository metadata and compatible dependency constraints for
  pub.dev publishing.

## 0.0.1

* Added local Laya bundle loading through ONNX Runtime.
* Added choice, score, and noul question construction and decoding.
* Added NFC + ByteLevel BPE tokenization and tensor batching.
* Added synchronous and asynchronous prediction APIs.
