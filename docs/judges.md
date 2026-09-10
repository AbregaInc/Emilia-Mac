# Emilia — judges' review guide

[60-second demo](https://github.com/AbregaInc/Emilia-Mac/releases/download/v0.2.0/Emilia-60s-demo.mp4)
· [Signed, notarized Mac download](https://github.com/AbregaInc/Emilia-Mac/releases/download/v0.3.0/Emilia-macOS-arm64.zip)
· [Release](https://github.com/AbregaInc/Emilia-Mac/releases/tag/v0.3.0)

Emilia adds a second opinion to a live call: amber indicates synthetic-voice
evidence, while a red, click-through border and quoted warning ask the listener
to pause when the conversation suggests a scam. Synthetic speech alone is not
fraud, and a human voice can still make a fraudulent request.

## What we built at the hackathon

- Native Swift/AppKit/SwiftUI app with microphone and all-system-audio capture,
  Dock/menu-bar controls, permissions, pause/reset and secure API-key storage.
- Local OpenAI Whisper and streaming OpenAI Realtime transcription paths.
- GPT-6 Astra integration with structured results, exact-quote grounding,
  transcript revision handling, bounded context and request cadence.
- Actual Emilia v8 worker integration, bounded recent voice evidence, amber
  indication and combined voice/conversation warnings.
- Signed/notarized packaging and the automated, narrated 60-second demo.

The commit history is preserved for review. Pretrained Whisper, whisper.cpp,
the underlying speech encoder, and the Emilia research detector predate the
event. The research training is not claimed as hackathon work.

## OpenAI use

| Role | Use |
|---|---|
| Development | GPT-6 Astra in Codex built and tested the native app and integrations. |
| Live transcription | OpenAI Realtime streams transcript deltas from captured audio. |
| Local transcription | OpenAI Whisper base.en runs through whisper.cpp on the Mac. |
| Scam assessment | GPT-6 Astra combines transcript evidence with optional recent voice metadata; it must quote observed words. |
| Existing research | OpenAI models direct experiments and evaluate results in Emilia's Codex autoresearch workflow. |
| Video | OpenAI speech generation narrates the demo; the simulated caller uses macOS speech. |

## The Emilia detector

Recovered original v8, seed 1, runs locally in one persistent CPU worker. Three
complete seconds of audio pass through four frozen W2v-BERT blocks; pooled
features feed saved classifier heads, with an artifact detector routing between
heads. The signed human margin is not a probability. The artifact-routing score
is not itself synthetic-voice or scam evidence.

The autoresearch workflow separates experiment selection, execution and
operation. Models propose bounded experiments, use shared evaluation machinery,
inspect recorded results and decide what to pursue next. The demo explains this
existing project rather than claiming to show a new training run.

Emilia was developed using data we cannot redistribute. Its training data,
checkpoint and research-only reference recording are excluded from this public
release. The adapter, evidence policy and UI are open for review. The full
voice-detection demo runs on our configured Mac; the public download does not
claim to reproduce it without the external bundle.

The model defaults to unknown bandwidth and returns both historical decisions
without one synthetic flag. The video explicitly assumes wideband. No thresholds
were adjusted for the demo. Its synthetic caller was selected because this
frozen detector flags it; the video is not an accuracy or latency benchmark.

## Try the public download

Requires Apple Silicon, macOS 26+, and your own OpenAI API key with access to
the selected models. Unzip the release, open Emilia.app, add your key in
Settings, choose a transcription mode, select Microphone or System audio, and
start listening. Approve macOS capture permission if requested.

Local Whisper is bundled. API keys entered in Settings use macOS Keychain.
Realtime sends audio to OpenAI; Astra receives transcript excerpts and optional
voice summaries. No call recordings are saved by default.

The download defaults to a bundled, clearly labeled NAVER AASIST-L baseline.
No Python or additional detector download is needed. Emilia v8 remains a
separate Settings choice requiring its external bundle. Try the
credential-request enactment in [demo/scenarios.md](../demo/scenarios.md).
Amber and voice-supported warnings work with the baseline, but its behavior
differs from the recorded Emilia demo. Its unvalidated 0.5 threshold false-flagged
the human JFK verification sample. See [baseline provenance and limitations](baseline.md).

## Where to review the engineering

| Component | Source |
|---|---|
| Native capture, independent source sessions | [AudioCapture.swift](../Sources/Emilia/AudioCapture.swift) |
| Live orchestration and stale-result rejection | [AppModel.swift](../Sources/Emilia/AppModel.swift) |
| JSONL worker lifecycle and response IDs | [VoiceDetector.swift](../Sources/Emilia/VoiceDetector.swift) |
| Bundled public baseline | [BaselineDetector.swift](../Sources/Emilia/BaselineDetector.swift) |
| Three-second PCM contract | [VoicePCMWindow.swift](../Sources/EmiliaCore/VoicePCMWindow.swift) |
| Bounded evidence and expiry | [VoiceEvidence.swift](../Sources/EmiliaCore/VoiceEvidence.swift) |
| Astra prompt and strict schema | [AstraClient.swift](../Sources/EmiliaCore/AstraClient.swift) |
| Exact-quote grounding | [Evidence.swift](../Sources/EmiliaCore/Evidence.swift) |
| Streaming transcript reconciliation | [RealtimeTranscriber.swift](../Sources/EmiliaCore/RealtimeTranscriber.swift) |
| Click-through amber | [VoiceGlow.swift](../Sources/Emilia/VoiceGlow.swift) |
| Tests | [Tests](../Tests) |
| Demo script and timed edit | [storyboard.py](../demo/storyboard.py), [video-script.md](../demo/video-script.md) |

Build instructions are in the [README](../README.md). After setup, `swift test`
runs ordinary tests without API credentials; optional model/API checks are
documented in [verification.md](verification.md). The latest enabled app suite
passed 31 checks with one additional paid check skipped (previously passed separately). Seven video
checks passed, including exact 60-second duration and amber/red visibility.

Known limits include unvalidated real-world false-warning rates, no speaker
attribution, external detector installation, and incomplete long-session,
sleep/wake and energy testing. This prototype does not prove fraud or identity.
