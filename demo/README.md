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
3. Use native CUA to choose Realtime in Settings, return, select System audio,
   and start listening. Record display 1 with `screencapture -v -V 55 -D 1 PATH.mov`.
   Play only `dist/demo/caller.wav`; keep unrelated system audio silent.
4. Verify the actual warning, hold it, then pause listening and show Settings.
   Preserve the full clean takes locally. Never use a take containing a real call.
5. Set the observed source cuts in `render-video.py`. The current source files are
   `final-take.mov` and `clean-take.mov`; timestamps are editing decisions, not a
   measured live-latency claim. Caption phrase timings are approximate.
6. Run `python3 demo/render-video.py`, then `python3 demo/test_render_video.py`.
   Inspect the finished video and audio. Keep the exact 60-second duration.

The current video identifies AASIST-L as a temporary detector and the Emilia
research integration as pending. After the model handoff, update that disclosure,
record actual behavior again, and regenerate the movie. Do not imply pretrained
weights or pre-existing research were created at the hackathon.

OpenAI speech generation reference:
https://developers.openai.com/api/docs/guides/text-to-speech
