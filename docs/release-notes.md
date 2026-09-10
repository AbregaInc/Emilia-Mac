Emilia 0.1.1 is a native Apple Silicon Mac app for live scam warning signs.

- Microphone and all-system-audio listening.
- Local Whisper or OpenAI Realtime transcription, selectable in Settings.
- GPT-6 Astra analysis with exact transcript evidence and repeat-alert suppression.
- Red warning border and movable card, plus normal window, Dock and menu-bar controls.
- User-entered API keys stored in macOS Keychain.
- Standard macOS editing shortcuts, including ⌘V and ⌘A in the API key field.
- Fixed-size ear icon that adapts to the menu bar's appearance.

Requires macOS 26+ and your own OpenAI API key. Local Whisper is bundled;
OpenAI Realtime uploads audio, and Astra analyzes transcript excerpts in either mode.
The voice-origin checkpoint is an optional separate local artifact and is not
bundled in this download. No synthetic score alone can trigger a scam warning.

The app is Developer ID signed, Apple-notarized and stapled. Both capture paths
were confirmed on the target Mac. Nineteen automated checks passed, along
with live Astra and Realtime integration checks. This is a hackathon prototype,
not a validated fraud detector or a guarantee that an unflagged call is safe.

ZIP SHA-256: `32d8e39eacc10e1a4446468460b996ee4f61d28ac53f48f1530b9247681107c9`
