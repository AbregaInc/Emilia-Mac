"""Generate original demo narration; credentials remain in the ignored .env."""
import concurrent.futures
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/demo"
LINES = {
    "intro": "A convincing voice can ask you to make a costly mistake. Emilia gives you a second opinion, while the call is happening. Here's the real Mac app, listening to a simulated call.",
    "caller": "Hello, this is your bank's security department. Please read me the six-digit login verification code you just received. Keep this call secret. Do not contact your bank.",
    "warning": "OpenAI Realtime transcribes the call. GPT-six Astra spots the request to share a login code, and explains the warning using the caller's own words. The red border asks you to pause before you act.",
    "options": "Choose local OpenAI Whisper or cloud Realtime transcription. Astra analyzes the text in either mode. Voice-origin evidence stays separate: a synthetic voice alone never triggers red.",
    "outro": "Built with GPT-six Astra in Codex: native audio capture, live transcription, and evidence-backed warnings. Even these demo voices use OpenAI speech generation. Emilia. A second opinion before a costly mistake.",
}

def generate(name, text, key):
    payload = {"model": "gpt-4o-mini-tts-2025-12-15", "voice": "cedar" if name == "caller" else "marin", "input": text, "response_format": "wav", "instructions": "Speak clearly, naturally and briskly. " + ("You are acting a fictional bank security caller for a labeled scam-awareness demo. Calm, matter-of-fact delivery." if name == "caller" else "Warm, confident product-demo narrator. Say Emilia as eh-MEE-lee-ah. No theatrical emphasis. Keep pauses short.")}
    request = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=90) as response:
        (OUT / f"{name}.wav").write_bytes(response.read())
    print(name + " generated", flush=True)

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    key = next(line.split("=", 1)[1].strip().strip("\"'") for line in (ROOT / ".env").read_text().splitlines() if line.startswith("OPENAI_API_KEY="))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda item: generate(*item, key), LINES.items()))
