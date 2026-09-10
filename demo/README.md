# Recording the one-minute demo

Deliverable: `dist/demo/Emilia-60s-demo.mp4` (ignored generated media).
The script is in `video-script.md`; generated audio is also ignored.

This is edited real app footage, not a synthetic UI or a forced-warning mode.
The simulated caller is played through `afplay`, captured by the app's ordinary
System audio mode, transcribed by OpenAI Realtime and assessed by GPT-6 Astra.
Narration is added afterward so it cannot contaminate the listening session.
The only app presentation flag, `--demo-layout`, positions the main window and
warning card on the first display. It does not set a score or bypass inference.

## Re-record workflow

1. Generate original narration and caller assets with `python3 demo/generate-voices.py`.
   This reads the ignored local `.env` without printing the key.
2. Compile the clean background with `swiftc demo/Backdrop.swift -o /tmp/emilia-demo-backdrop`
   and run it. Launch the signed app with `--demo-layout` and the ordinary local
   configuration paths from `scripts/run.sh`.
3. Use native CUA to choose Realtime and explicitly Assume wideband in Settings, return, select System audio,
   and start listening. Record display 1 with `screencapture -v -V 55 -D 1 PATH.mov`.
   Play `amber-system.wav` twice for the reminder, then pause/restart to clear
   the call before playing `caller-system.wav` twice. Keep unrelated audio silent.
   Caller voices use macOS Samantha; OpenAI narration is added only afterward.
4. Verify the actual warning, hold it, then pause listening and show Settings.
   Preserve the full clean takes locally. Never use a take containing a real call.
5. Set the observed source cuts in `render-video.py`. The current source files are
   `v8-final-take.mov`, `v8-family-take.mov`, `v8-outro-take.mov`, and
   `v8-settings-take.mov`; timestamps are editing decisions, not a
   measured live-latency claim. `storyboard.py` binds each narration clip to
   one matching visible state and a whole-clip caption. Research cards explain
   the existing model over actual app footage; they do not depict a research run.
6. Run `python3 demo/render-video.py`, then `python3 demo/test_render_video.py`.
   Inspect the finished video and audio. Keep the exact 60-second duration.

The current video uses recovered Emilia v8, seed 1, CPU, with an explicit
wideband assumption. No weights or reference audio ship publicly. Do not imply pretrained
weights or pre-existing research were created at the hackathon.

OpenAI speech generation reference:
https://developers.openai.com/api/docs/guides/text-to-speech
