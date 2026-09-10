Emilia 0.2.0 is a native Apple Silicon Mac app for live scam warning signs.

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
The voice-origin checkpoint is an optional separate local artifact and is not
bundled in this download. No synthetic score alone can trigger a scam warning.

The app is Developer ID signed, Apple-notarized and stapled. Both capture paths
were confirmed on the target Mac. Twenty-seven automated checks passed (one
paid check skipped in the full suite and passed separately), along
with live Astra and Realtime integration checks. This is a hackathon prototype,
not a validated fraud detector or a guarantee that an unflagged call is safe.

External recovered v8 and compatible Python are required for voice detection;
neither ships in the download. Default unknown bandwidth has no single flag.
The demo explicitly assumes wideband.

ZIP SHA-256: `8e97ec68a2ca7cd96d9b1948b7764f981d28e249379dc8665a7f52629e305e3c`
