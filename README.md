# Emilia

**A second opinion for what you're hearing.**

A native Mac app with Dock and menu-bar controls that listens to a microphone or system audio,
transcribes with local Whisper or OpenAI Realtime, and asks GPT-6 Astra to identify
actionable scam warning signs. Evidence-backed warnings appear as a red screen
border and a movable, nonactivating card. The border does not intercept clicks.

## Run on this Mac

Requires Apple Silicon, macOS 26+, Xcode command-line tools, CMake, Git and curl.

```sh
bash scripts/setup-whisper.sh
bash scripts/build-app.sh
bash scripts/run.sh
```

Add your API key through Emilia's settings; the app stores it in macOS
Keychain, accessible only while the device is unlocked, on this device.
For development, `OPENAI_API_KEY=your-key` in a local `.env` with `chmod 600 .env`
is also supported. `.env` files are gitignored and never copied to the app
bundle. The development launcher selects the repository `.env` using
`EMILIA_ENV_FILE`. A saved Keychain key takes precedence. Merely launching the
development build never copies its `.env` key into Keychain.

Select **Microphone** for a phone on speakerphone, or **System audio** for audio
playing from Mac apps. Click **Start listening** and accept the relevant macOS
permission prompt. There is no additional onboarding/opt-in screen. The app
shows which source is active and that Astra analyzes transcripts.

Microphone mode captures everything audible near the selected default input,
including both sides of a speakerphone conversation. System mode captures all
system playback, including unrelated apps, but does not add microphone audio.
Neither mode establishes speaker identity or accesses internal iPhone audio.

The app opens a window and has a Dock icon. Click it or the menu-bar ear icon to reopen it. Pause clears
audio/transcript buffers and cancels analysis. Sleep pauses listening; resume
explicitly after wake. If you change the default microphone or audio route and
audio stops, pause and start again. English is the initial transcription language.

## Transcription choice

Settings offers **Local Whisper** (the default) and **OpenAI Realtime**.
Local Whisper keeps audio on the Mac. OpenAI Realtime streams 24 kHz mono PCM
over an authenticated WebSocket to `gpt-live-transcribe`, with `delay: low`,
and displays text deltas while speech is still arriving. It uses the same API
key as Astra and incurs transcription API usage. Pause to change modes.

This is a dedicated transcription session: there is no spoken AI response.
The app commits turns on a speech pause or at six seconds; live deltas can
arrive before the commit. This model does not support server turn detection,
so Emilia handles that locally. Item IDs reconcile partial/final results even
when completion events arrive out of order. Times are captured audio-window
boundaries, not claimed word-level timestamps. Upload backlog or disconnection
stops the session visibly; there is no silent cloud/local fallback.

## What runs where

- **On the Mac:** audio capture; bounded PCM buffers; Whisper base.en through
  pinned whisper.cpp with Metal acceleration; evidence validation; warning
  suppression; UI; optional local Core ML voice-origin model.
- **OpenAI API:** optional realtime audio transcription; `gpt-6-astra` Responses API, low reasoning effort, strict JSON
  schema, `store: false`. At most 6,000 transcript characters / 120 seconds of
  context, one request at a time, minimum three-second cadence. API requests
  stop after 120 attempts per listening session; restart explicitly to continue.

Raw audio stays in memory and is uploaded only in OpenAI Realtime mode.
Transcript/audio are not persisted by default.
`store: false` disables Responses application storage; it is not a promise of
zero provider retention. API account terms and retention policies still apply.
Local Whisper runs offline; conversational scam warnings require internet and an API
key. Missing API access is shown explicitly, while local transcription can run.

Whisper receives only audio observed so far. It re-transcribes up to 12 seconds
of recent speech, on a serial worker, approximately every three seconds or at
a pause. Silence gating avoids unnecessary work but can miss quiet speech.
Transcription errors and hallucinations remain possible. Revisions replace
overlapping transcript intervals. Old answers, missing exact quotes, and
quotes retracted from the current transcript cannot trigger new warnings.

## Voice-origin evidence

Synthetic speech alone never triggers a scam warning. The warning policy does
not accept a voice score. A human scam can warn; a benign synthetic reminder
should not warn just because it is synthetic.

An optional Core ML model is loaded from
`~/Library/Application Support/Emilia/VoiceModel/manifest.json` (or the explicit
`EMILIA_VOICE_MODEL_DIR` override). It must expose one `audio` float waveform
input shaped `[1, 80000]`, at 16 kHz, and one scalar synthetic score. The
manifest pins the model checksum, input/output names, threshold and permission
record. No model installed means **Model not installed**, never a fake score.

`scripts/convert-aasist.py` converts an explicitly supplied AASIST-L source and
checkpoint and checks Core ML/PyTorch agreement on three fixed random inputs.
This is conversion parity, not detection accuracy. Its 0.5 demo threshold is
uncalibrated. The local demo may use this user-authorized external artifact;
public checkpoint redistribution remains separate from the source license.

## Verify

```sh
swift test
swift run EmiliaCheck Models/ggml-base.en.bin .deps/whisper.cpp/samples/jfk.wav
swift run EmiliaCheck --astra  # four small paid API checks; requires local .env
swift run EmiliaCheck --realtime  # streams the public-domain JFK test recording to OpenAI
```

The automated tests exercise grounding, refusal, stale/revised evidence,
cooldowns, retention, ring-buffer wraparound and request construction. The live
Astra checks cover a code request, benign reminder, negation and prompt injection.
See [demo/scenarios.md](demo/scenarios.md) for original enactment scripts.
These are integration checks, not a scam-detection accuracy benchmark.

## Distribution

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR ORGANIZATION (TEAMID)' bash scripts/build-app.sh
APPLE_ID=you@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_PASSWORD=... bash scripts/notarize.sh
```

The build creates `dist/Emilia.app` and `dist/Emilia-macOS-arm64.zip`. Signing
defaults to ad hoc unless a Developer ID identity is supplied. Notarization is
a separate step requiring Apple credentials; a signature alone is not notarization.
The notarization script does not save credentials in Keychain. Whisper weights
are bundled from the checksum-verified local download, never committed to Git.
The API key and voice-origin checkpoint are not bundled.

## Hackathon contribution

This standalone repository contains the Mac capture/UI, local Whisper bridge,
Astra integration, grounding policy, lifecycle controls, checks and packaging
built for the hackathon. OpenAI Whisper, whisper.cpp and any supplied AASIST
checkpoint are pre-existing components, clearly attributed. Emilia's research
workspace is not included and is not needed to build this app.

The warning is a second opinion, not a finding of fraud or proof that an
unflagged call is safe. No blocking, automatic hangup or identity verification
is performed. The one-minute video must show actual audio-driven inference
and distinguish controlled enactments from real calls.

Apache-2.0 for original source. See THIRD_PARTY_NOTICES for dependencies.
