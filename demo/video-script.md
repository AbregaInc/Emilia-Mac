# Emilia — a second opinion before a costly mistake

60-second edited recording of the real Mac app. Simulated callers use macOS
Samantha; narration uses OpenAI speech generation. The warning comes from the
live Realtime → Astra path, never a forced warning or prerecorded API response.

| Time | Picture | Audio |
|---|---|---|
| 0–4 | Paused app | Emilia: a second opinion on a call. |
| 4–10 | Actual amber over harmless reminder | Amber indicates synthetic voice evidence; no scam warning. |
| 10–18 | Amber plus research explanation | Emilia v8 comes from existing autoresearch run in Codex with OpenAI models directing experiments and evaluating results. |
| 18–26 | Amber plus detector architecture | Three-second windows, four-block W2v-BERT encoder, router and fitted classifier heads; local synthetic-speech detection. |
| 26–32 | Separate family call, actual caller audio | “Mom, it's your daughter. This is my new phone number. I wanted to talk with you about our family.” |
| 32–41 | Actual red warning and quoted claim | Realtime captures the claim; Astra combines it with Emilia's voice evidence and warns to verify. |
| 41–46 | Settings | Local OpenAI Whisper option; voice detection stays on Mac. |
| 46–53 | Paused app plus contribution credit | Research predates today; native app and live integration built at the hackathon using Astra in Codex. |
| 53–60 | Closing app view | OpenAI speech-generation narration; Emilia: a second opinion before a costly mistake. |

`storyboard.py` is the shared source of narration and timing. Every narration
clip starts with its matching shot and whole-clip caption; there are no estimated
word-count subtitle boundaries. Research cards are editorial explanations over
actual app footage, not a claimed recording of an experiment or new model training.
Technical facts follow core's `docs/emilia-v8-app-handoff.md`; research workflow
follows `docs/operating-model.md` and the user's description of their Codex run.

On-screen credits distinguish new hackathon app/integration work from pretrained
models and the existing Emilia research project. This recording uses the current
recovered original Emilia v8, seed 1, CPU, with an explicit wideband assumption.
The default remains unknown. The controlled caller was selected because the
frozen detector flags it; other generated voices did not reliably flag.
The final edit may shift internal cuts to fit measured speech and API timing;
the exported video must be exactly 60 seconds. Do not claim the edited timeline
is a latency benchmark.
