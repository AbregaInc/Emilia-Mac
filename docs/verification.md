# Hackathon verification — 2026-09-10

Device: Apple M1 Max, 64 GiB RAM; macOS 26.6.2; Xcode 26.6. Native arm64 build.

## Verified

- Developer ID signing and strict code-signature verification pass.
- Dock icon and normal launch window are visible; native accessibility controls
  were inspected. This replaced an unreliable menu-bar-only launch.
- User confirmed both microphone and all-system-audio capture work on this Mac.
- Local Whisper base.en correctly transcribed the public-domain JFK test
  recording, with 0.60 seconds inference time after model loading in the first
  smoke check. This is one file measurement, not an end-to-end latency guarantee.
- Live Astra checks passed for a credential scam, benign automated reminder,
  educational negation and spoken prompt injection. Observed request times in
  that run: 8.15, 3.14, 2.95 and 3.39 seconds respectively.
- A locally generated controlled script passed audio → local Whisper → Astra
  → exact-quote grounding. No filenames or scenario labels enter inference.
- OpenAI Realtime authenticated with the supplied development key and produced
  incremental transcript deltas during paced audio playback. The actual service
  rejects server turn detection for `gpt-live-transcribe`; the implementation
  uses app-managed commits, as in the official transcription guide's example.
- AASIST-L conversion matches the original PyTorch model on three fixed random
  inputs (observed absolute error 0 in this check). Converted model: 397,097
  bytes. A controlled local synthetic sample produced a synthetic flag. Neither
  result establishes detector quality or a calibrated probability.
- Development `.env` and copied Apple key are excluded from Git and the app
  bundle. Settings saves user-entered keys to Keychain. Keychain tests mock the
  OS calls and create no actual credentials.

## Limits / remaining checks

- This is an integration prototype, not a validated scam detector. No accuracy
  claim, warning-recall benchmark or legitimate-call false-warning rate is established.
- Thirty-minute listening, route-change, sleep/wake, noisy speakerphone,
  long-session realtime reconnect and energy measurements remain manual checks.
- The synthetic model is an external, user-authorized local demo artifact.
  Its trained-weight public redistribution rights remain separate.
- Public release still needs a one-minute event-only video and contribution
  attribution. Do not imply pre-existing model training occurred at the event.

Rerun automated tests with:

```sh
swift test
EMILIA_TEST_WHISPER=1 swift test --filter AudioTests.testLocalWhisperPipelineTranscribesObservedAudio
swift run EmiliaCheck --astra
swift run EmiliaCheck --realtime
```

The optional voice test also requires the external converted model and local
controlled WAV fixture; ordinary tests skip model-dependent checks unless enabled.
