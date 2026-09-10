# Recovered Emilia v8 — local app integration

Launch the signed, notarized app:

```sh
open /Users/boris/repo/abrega/emilia-mac-app/dist/Emilia.app
```

This Mac resolves `~/Library/Application Support/Emilia/VoiceModel-v8` to the
canonical `emilia-v8-recovery-20260910` bundle and `VoiceModel-v8-python` to
`/Users/boris/.pyenv/versions/3.11.5/bin/python`. Environment overrides are
`EMILIA_V8_BUNDLE` and `EMILIA_V8_PYTHON`. Neither weights nor reference audio
are copied into the public repository or release.

One persistent worker runs original v8 seed 1 on CPU. Requests carry IDs,
three complete seconds of original-rate interleaved float32 PCM and an explicit
bandwidth choice. The app never pads, trims leading silence, infers bandwidth
from sample rate, changes thresholds, or treats margins as probabilities.
Unknown preserves both decisions without a single flag. Mic and System audio
are separate capture sessions; switching requires stopping and clears context.
Only one inference is in flight; complete windows arriving while busy are
dropped instead of accumulating. Failures display unavailable status.

Amber is click-through and indicates fresh synthetic-voice evidence. Red takes
precedence and requires Astra's assessment grounded in transcript quotes.
Astra receives at most six observations from 30 seconds with 10-second freshness,
signed mean margin, flag counts and the bandwidth assumption. Artifact-routing
scores are excluded. Silence cannot renew evidence. Family impersonation may
warrant a verification warning with repeated fresh flags; synthetic speech
alone or disclosed assistive speech does not. No speaker attribution is claimed.

## Verification

Reference WAV worker and PCM app calls matched route v6, margin
0.06209803647790091, synthetic false, artifact score 6.047003626183e-08.
The enabled Swift suite passed 27 checks with one paid check skipped; that
five-case Astra policy check passed separately. Real UI verified microphone,
system audio, amber click-through, family-context red warning and worker shutdown.
See `verification.md` for notarization receipt and remaining long-session limits.

The video at `dist/demo/Emilia-60s-demo.mp4` uses actual model/API responses,
controlled macOS synthetic caller audio, OpenAI narration and explicit event
contribution credits. It is an edited demo, not an accuracy or latency benchmark.
Public redistribution of the external detector remains unapproved.

## Changed files (absolute paths)

- /Users/boris/repo/abrega/emilia-mac-app/Sources/Emilia/VoiceDetector.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/Emilia/VoiceGlow.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/Emilia/AudioCapture.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/Emilia/AppModel.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/Emilia/EmiliaApp.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/EmiliaCore/VoicePCMWindow.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/EmiliaCore/VoiceEvidence.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/EmiliaCore/AstraClient.swift
- /Users/boris/repo/abrega/emilia-mac-app/Sources/EmiliaCore/Evidence.swift
- /Users/boris/repo/abrega/emilia-mac-app/Tests/EmiliaAppTests/AudioTests.swift
- /Users/boris/repo/abrega/emilia-mac-app/Tests/EmiliaAppTests/VoiceGlowTests.swift
- /Users/boris/repo/abrega/emilia-mac-app/Tests/EmiliaAppTests/VoiceWorkerTests.swift
- /Users/boris/repo/abrega/emilia-mac-app/Tests/EmiliaCoreTests/VoiceEvidenceTests.swift
- /Users/boris/repo/abrega/emilia-mac-app/Resources/Info.plist
- /Users/boris/repo/abrega/emilia-mac-app/scripts/run.sh
- /Users/boris/repo/abrega/emilia-mac-app/.gitignore
- /Users/boris/repo/abrega/emilia-mac-app/README.md
- /Users/boris/repo/abrega/emilia-mac-app/docs/verification.md
- /Users/boris/repo/abrega/emilia-mac-app/docs/release-notes.md
- /Users/boris/repo/abrega/emilia-mac-app/docs/v8-integration.md
- /Users/boris/repo/abrega/emilia-mac-app/demo/Backdrop.swift
- /Users/boris/repo/abrega/emilia-mac-app/demo/generate-voices.py
- /Users/boris/repo/abrega/emilia-mac-app/demo/render-video.py
- /Users/boris/repo/abrega/emilia-mac-app/demo/test_render_video.py
- /Users/boris/repo/abrega/emilia-mac-app/demo/video-script.md
- /Users/boris/repo/abrega/emilia-mac-app/demo/README.md
