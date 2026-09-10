# Public baseline: NAVER AASIST-L

Version 0.3.0 includes AASIST-L as the default voice detector. It runs on the Mac
through Core ML, without Python, a network request or a separate download.
Settings and voice-supported warnings explicitly identify it as a baseline.
The recorded hackathon video continues to use actual Emilia v8.

## Provenance and license

The checkpoint is distributed inside NAVER's official
[clovaai/aasist repository](https://github.com/clovaai/aasist/tree/a04c9863f63d44471dde8a6abcb3b082b07cd1d1)
under its root [MIT license](https://github.com/clovaai/aasist/blob/a04c9863f63d44471dde8a6abcb3b082b07cd1d1/LICENSE).
We retain the NAVER copyright and complete license in the app. The source
checkpoint is `models/weights/AASIST-L.pth`; its SHA-256 and the converted model's
SHA-256 are in [baseline-manifest.json](baseline-manifest.json). No training
data is redistributed. This is a public baseline, not an Emilia research model.

The official model was trained for ASVspoof 2019 logical-access anti-spoofing.
Our conversion preserves its weights and fixed-length forward pass. Three fixed
random inputs and two audio files matched PyTorch exactly in the recorded
Core ML conversion check. Native Swift inference on the same JFK prefix matched
within 0.00001. These are numerical parity checks, not accuracy measurements.

## Contract and limitations

Five complete seconds of observed PCM are buffered independently for each
capture session, downmixed and resampled locally. The converted graph consumes
the first 64,600 samples at 16 kHz. Leading silence is preserved; incomplete
prefixes are rejected. This does not change Emilia's separate three-second
worker contract.

The baseline's class-0 softmax score is compared with an **unvalidated 0.5 demo
threshold**. It is not a probability of synthesis, fraud or identity. It
false-flagged the human JFK test recording (score 0.9923725); the controlled
synthetic caller scored 0.9999447. Do not infer accuracy from either observation.

Up to six observations within 30 seconds, with 10-second freshness, inform
amber and optional Astra voice evidence. Baseline metadata has its own model
identity and mean score, no Emilia human margin or bandwidth decisions.
Synthetic speech alone does not justify red. Voice-supported warnings require
repeated fresh flags plus grounded conversation evidence, and are labeled
“AASIST-L baseline”. False positives and false negatives remain possible.

## Build or reproduce

Normal source builds run `bash scripts/setup-baseline.sh`, which downloads the
version-pinned converted release asset and verifies its SHA-256. Weights are
ignored by Git. `scripts/build-app.sh` compiles and signs it inside the app.

To reproduce conversion, use a separate environment with Python 3.11,
PyTorch 2.7.1, coremltools 9.0 and NumPy 1.26.4; clone the pinned official repo,
then run:

```sh
python scripts/convert-aasist.py --source PATH_TO_PINNED_AASIST \
  --output Models/AASISTBaseline \
  --validation-wav .deps/whisper.cpp/samples/jfk.wav
```

The manifest records the resulting parity checks. Run `swift test` after setup
for native parity, incomplete-window rejection, lifecycle, independent window
contracts and evidence labeling. `EMILIA_TEST_ASTRA_BASELINE=1 swift test --filter
BaselineTests.testLiveAstraBaselinePolicy` additionally checks the paid API's
benign-reminder and family-claim behavior using explicit test metadata.
