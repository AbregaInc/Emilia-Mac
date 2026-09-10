"""Convert an explicitly supplied AASIST-L checkpoint; verify Core ML/PyTorch parity.

No model or upstream source is stored in the public source tree. The pinned
official MIT-licensed checkpoint is converted for the public release; training
data permissions are separate and no training data is distributed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import copy
import types

import coremltools as ct
import numpy as np
import torch

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--validation-wav", type=Path, action="append", default=[])
args = parser.parse_args()
sys.path.insert(0, str(args.source.resolve()))
from models.AASIST import Model

torch.set_num_threads(4)
config = json.loads((args.source / "config/AASIST-L.conf").read_text())["model_config"]
checkpoint = args.source / "models/weights/AASIST-L.pth"
base = Model(config)
base.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True))
base.eval()
reference_base = copy.deepcopy(base)

# Fixed-shape equivalent of NAVER's HtrgGraphAttentionLayer.forward (MIT).
# Core ML's torch frontend cannot lower narrow() with traced tensor lengths.
# Freeze only dimensions, never audio values, and check against the untouched model.
def fixed_graph_forward(self, x1, x2, master=None):
    n1, n2 = int(x1.size(1)), int(x2.size(1))
    x = torch.cat([self.proj_type1(x1), self.proj_type2(x2)], dim=1)
    if master is None: master = torch.mean(x, dim=1, keepdim=True)
    x = self.input_drop(x)
    attention = self._derive_att_map(x, n1, n2)
    master = self._update_master(x, master)
    x = self.act(self._apply_BN(self._project(x, attention)))
    return x[:, :n1, :], x[:, n1:n1+n2, :], master

for module in base.modules():
    if type(module).__name__ == "HtrgGraphAttentionLayer":
        module.forward = types.MethodType(fixed_graph_forward, module)

class Adapter(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, audio):
        # Official 64,600-sample input, taken from an already observed five-second window.
        _, logits = self.model(audio[:, :64600])
        return torch.softmax(logits, dim=-1)[:, 0]

wrapper = Adapter(base).eval()
reference_wrapper = Adapter(reference_base).eval()
torch.manual_seed(13)
example = torch.randn(1, 80000) * 0.03
with torch.no_grad():
    traced = torch.jit.trace(wrapper, example)
converted = ct.convert(traced, inputs=[ct.TensorType(name="audio", shape=(1, 80000))],
                       outputs=[ct.TensorType(name="synthetic_score")], convert_to="neuralnetwork",
                       minimum_deployment_target=ct.target.macOS11, compute_units=ct.ComputeUnit.CPU_ONLY)
args.output.mkdir(parents=True, exist_ok=True)
model_path = args.output / "aasist-l.mlmodel"
converted.save(str(model_path))
checks = []
for seed in (17, 29, 43):
    audio = np.random.default_rng(seed).normal(0, 0.03, (1, 80000)).astype(np.float32)
    with torch.no_grad(): reference = float(reference_wrapper(torch.from_numpy(audio))[0])
    actual = float(np.asarray(converted.predict({"audio": audio})["synthetic_score"]).reshape(-1)[0])
    checks.append({"seed": seed, "pytorch": reference, "coreml": actual, "absolute_error": abs(reference - actual)})
assert max(c["absolute_error"] for c in checks) < 0.001, checks
import wave
for path in args.validation_wav:
    with wave.open(str(path), "rb") as wav:
        assert wav.getframerate() == 16000 and wav.getnchannels() == 1 and wav.getsampwidth() == 2
        audio = np.frombuffer(wav.readframes(80000), dtype="<i2").astype(np.float32) / 32768
    assert len(audio) == 80000
    audio = audio.reshape(1,80000)
    with torch.no_grad(): reference = float(reference_wrapper(torch.from_numpy(audio))[0])
    actual = float(np.asarray(converted.predict({"audio": audio})["synthetic_score"]).reshape(-1)[0])
    assert abs(reference-actual) < 0.001
    checks.append({"wav": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "pytorch": reference, "coreml": actual, "absolute_error": abs(reference-actual)})
manifest = {
    "modelVersion": "aasist-l-a04c986-coreml-v1", "modelFile": model_path.name,
    "sha256": hashlib.sha256(model_path.read_bytes()).hexdigest(),
    "checkpointSHA256": hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
    "inputName": "audio", "outputName": "synthetic_score", "sampleRate": 16000, "sampleCount": 80000,
    "threshold": 0.5, "thresholdStatus": "unvalidated demonstration threshold; not a fraud probability",
    "license": "MIT, NAVER Corp.; checkpoint distributed inside the official clovaai/aasist repository under its root LICENSE",
    "sourceURL": "https://github.com/clovaai/aasist/tree/a04c9863f63d44471dde8a6abcb3b082b07cd1d1",
    "deploymentPermission": "Public baseline derived from the official MIT-licensed repository; retain NAVER copyright and LICENSE. No training data redistributed.",
    "redistribution": True, "parity": checks,
}
(args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({"model": str(model_path), "parity": checks}, indent=2))
