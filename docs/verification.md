# Hackathon verification — 2026-09-10

Device: Apple M1 Max, 64 GiB RAM; macOS 26.6.2; Xcode 26.6. Native arm64 build.

## Verified

### Current v0.3.0 public baseline

- NAVER AASIST-L is bundled and selected by default; Emilia v8 is an explicit
  external-model choice. No runtime Python or download is needed for baseline.
- Core ML conversion matches original PyTorch on three fixed inputs and two
  audio files. Native Swift inference matches the JFK reference score within
  0.00001. The human JFK sample false-flags at the unvalidated 0.5 threshold;
  these checks establish parity, not detection quality.
- Enabled suite: 32 tests, one optional paid test skipped, zero failures.
  This run enabled local Whisper, actual Emilia v8 and paid baseline Astra
  checks. Benign reminder does not warn; supported family claim warns with
  grounded quotes. The skipped Emilia-only paid check passed previously.
- Baseline evidence records its own detector identity and score rather than
  an Emilia human margin. Five-second baseline and three-second v8 windows
  remain distinct. Incomplete input, stop/reload and evidence expiry are tested.
- Developer ID signature and notarization/stapling passed; Apple submission
  `a7496bf2-fce7-4775-bebe-ab7dd413b798`. ZIP SHA-256:
  `a1bf28378b997ae29bf5d036eb2100c5c4c018aa92f38f59618d42185fadd7d5`.
- Native UI verified the default baseline Settings description and started
  System audio capture. An unrelated user call interrupted the session; it was
  cleared without retaining a recording. Subsequent native automation failed
  with “Sky Computer Use native pipe startup failed”, so the fresh end-to-end
  visual warning check remains unverified. No claim is made about that session.

Earlier release checks below are historical and retain their own version scope.

### Current v0.2.0 integration

- Replaced the AASIST-L runtime with recovered original Emilia v8, seed 1,
  through one persistent CPU Python worker. Canonical bundle unchanged.
- Reference WAV and Swift PCM match route v6, human margin 0.06209803647790091
  and artifact score 6.047003626183e-08; no synthetic flag. Unknown bandwidth
  preserves both decisions and omits a single flag.
- Latest enabled suite: 28 tests, one paid-API test skipped, zero failures.
  Local Whisper and real v8 checks enabled. Separate paid Astra fusion test
  passed family claim without voice, family claim with synthetic evidence,
  assistive speech, benign reminder and human credential-scam cases.
- Actual native UI: Mic and System audio reached v8 independently. Pause/restart
  clears streams and shuts down the worker. Missing bundle, wrong response ID,
  worker restart, incomplete windows, source reset and evidence expiry have tests.
- Benign reminder showed amber without red. Clicking through amber opened
  Settings. Separate family call produced a real Astra warning marked
  “Voice + conversation · assumed wideband”. Red takes precedence.
- Complete silent windows still go unchanged to the model but do not renew
  evidence. Six observations/30 seconds, 10-second freshness, signed margins
  and explicit band assumptions are sent separately from the transcript.
- v0.2.0 Developer ID signature, notarization and stapling passed. Submission:
  `5ae8908b-b837-42d2-aac2-06873fc12245`. ZIP SHA-256:
  `8e97ec68a2ca7cd96d9b1948b7764f981d28e249379dc8665a7f52629e305e3c`.
- Final demo is exactly 60 seconds. Six video checks cover source assets,
  timeline, caption fit, full audio/video decode, amber visibility and the
  red border/card on the same display. Edited footage visually inspected.

### Earlier v0.1.1 checks (historical AASIST runtime)

- Developer ID signing and strict code-signature verification pass.
- Apple notarization accepted v0.1.1 submission `579bba2b-90b9-48fe-b44f-e042f5e3e2e4`.
  Stapling and ticket validation passed. Release ZIP SHA-256:
  `32d8e39eacc10e1a4446468460b996ee4f61d28ac53f48f1530b9247681107c9`.
- Full enabled test run: 19 tests, zero failures, including local Whisper and
  external Core ML integration. Credential tests made no Keychain writes.
- Native UI paste and Select All replacement verified with harmless text in
  the secure key field; no test key was saved. Menu and status-icon configuration
  have regression coverage. Physical menu-bar visibility remains user-dependent
  when macOS has insufficient space for status items.
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
- Public v8 redistribution remains unapproved. The signed app excludes weights,
  reference audio and Python. This Mac uses the external canonical bundle and
  existing Python; it is not a portable detector installation.

Rerun automated tests with:

```sh
swift test
EMILIA_TEST_WHISPER=1 swift test --filter AudioTests.testLocalWhisperPipelineTranscribesObservedAudio
EMILIA_TEST_VOICE=1 EMILIA_TEST_WHISPER=1 swift test
EMILIA_TEST_ASTRA_FUSION=1 swift test --filter VoiceEvidenceTests.testLiveAstraCombinedEvidence
swift run EmiliaCheck --astra
swift run EmiliaCheck --realtime
```

The optional voice test requires the recovered v8 bundle and reference WAV
locally; ordinary tests skip model-dependent checks unless enabled.
