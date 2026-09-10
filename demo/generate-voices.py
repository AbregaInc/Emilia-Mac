"""Generate original demo narration; credentials remain in the ignored .env."""
import concurrent.futures
import json
from pathlib import Path
import urllib.request
import sys
import subprocess
from storyboard import STORY

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/demo"
LINES = {row[0]: row[4] for row in STORY}
LINES["reminder"] = "This is an automated reminder. Your appointment is tomorrow at ten. No action is needed. Have a wonderful day."

def generate(name, text, key):
    if name in ("caller", "reminder"):
        # Controlled local caller that the frozen v8 detector flags. No model changes.
        basename = "amber" if name == "reminder" else name
        aiff = OUT / f"{basename}-system.aiff"
        subprocess.run(["say", "-v", "Samantha", "-r", "165", "-o", str(aiff), text], check=True)
        subprocess.run(["ffmpeg", "-y", "-i", str(aiff), "-ar", "16000", "-ac", "1", str(OUT / f"{basename}-system.wav")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        print(name + " generated with macOS speech", flush=True)
        return
    payload = {"model": "gpt-4o-mini-tts-2025-12-15", "voice": "marin", "input": text, "response_format": "wav", "instructions": "Speak clearly, naturally and briskly. Warm, confident product-demo narrator. Say Emilia as eh-MEE-lee-ah. No theatrical emphasis. Keep pauses short."}
    request = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=90) as response:
        (OUT / f"{name}.wav").write_bytes(response.read())
    print(name + " generated", flush=True)

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    key = next(line.split("=", 1)[1].strip().strip("\"'") for line in (ROOT / ".env").read_text().splitlines() if line.startswith("OPENAI_API_KEY="))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda item: generate(*item, key), [(k,v) for k,v in LINES.items() if len(sys.argv) == 1 or k in sys.argv[1:]]))
