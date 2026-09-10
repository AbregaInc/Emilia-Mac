Emilia 0.3.0 adds an included, clearly labeled NAVER AASIST-L baseline detector.

The public download now supports local voice detection out of the box, without
Python or another model download. Settings offers the baseline separately from
the external Emilia v8 research model used in the recorded demo. Baseline
voice-supported warnings identify the model explicitly.

- Microphone and all-system-audio listening.
- Local Whisper or OpenAI Realtime transcription, selectable in Settings.
- GPT-6 Astra analysis with exact transcript evidence and repeat-alert suppression.
- Red warning border and movable card, plus normal window, Dock and menu-bar controls.
- User-entered API keys stored in macOS Keychain.
- Standard macOS editing shortcuts, including ⌘V and ⌘A in the API key field.
- Fixed-size ear icon that adapts to the menu bar's appearance.
- Actual Emilia v8 persistent CPU worker with explicit bandwidth assumptions.
- Click-through amber; recent voice evidence supports Astra's assessment of
  family identity claims. Synthetic voice alone never means scam.

Requires macOS 26+ and your own OpenAI API key. Local Whisper is bundled;
OpenAI Realtime uploads audio, and Astra analyzes transcript excerpts in either mode.
The AASIST-L baseline and its MIT license are bundled. Emilia's research
checkpoint remains an optional external artifact. No synthetic score alone
can trigger a scam warning.

The app is Developer ID signed, Apple-notarized and stapled. Both capture paths
were confirmed on the target Mac in prior versions. Thirty-one enabled automated
checks passed (one additional paid check skipped and previously passed), along
with live Astra and Realtime integration checks. This is a hackathon prototype,
not a validated fraud detector or a guarantee that an unflagged call is safe.

The baseline uses five-second windows and an unvalidated 0.5 demonstration
threshold. It false-flagged the human JFK verification sample. Numerical
Core ML/PyTorch parity is verified; real-world detection accuracy is not.
See docs/baseline.md. The recorded demo uses Emilia v8 with assumed wideband,
not this baseline. An interrupted capture check could not be repeated because
native UI automation failed; the default Settings labeling was verified.

Emilia was developed using data we cannot redistribute. Its checkpoint,
training data and reference audio remain excluded. No Emilia thresholds changed.

Notarization submission: `a7496bf2-fce7-4775-bebe-ab7dd413b798` (accepted and stapled).

ZIP SHA-256: `a1bf28378b997ae29bf5d036eb2100c5c4c018aa92f38f59618d42185fadd7d5`
