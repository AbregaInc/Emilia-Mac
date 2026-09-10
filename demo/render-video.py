"""Assemble a 60 s demo from real recordings and original OpenAI narration."""
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/demo"
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"

SEGMENTS = [
    ("intro", 8, "v8-final-take.mov", 0),
    ("amber", 8, "v8-final-take.mov", 8),
    ("caller", 10, "v8-family-take.mov", 2),
    ("warning", 14, "v8-family-take.mov", 13),
    ("options", 8, "v8-settings-take.mov", 0),
    ("outro", 12, "v8-outro-take.mov", 0),
]
AUDIO = {"amber": "amber-system.wav", "caller": "caller-system.wav"}
CAPTIONS = {
    "intro": ["Emilia gives you a second opinion on a call.", "First, listen to a harmless automated reminder."],
    "amber": ["SIMULATED CALLER: This is an automated reminder.", "Your appointment is tomorrow at ten. No action is needed.", "Have a wonderful day."],
    "caller": ["SIMULATED CALLER: Mom, it’s your daughter. This is my new phone number.", "I wanted to talk with you about our family."],
    "warning": ["Amber means synthetic voice evidence, without blocking your clicks.", "OpenAI Realtime captures the words.", "GPT-6 Astra combines the claimed family identity with recent voice evidence,", "and asks you to verify. The context changed the warning."],
    "options": ["Local OpenAI Whisper is also available.", "Voice detection stays on this Mac.", "Astra receives text and a bounded evidence summary."],
    "outro": ["Built with GPT-6 Astra in Codex.", "Narrated using OpenAI speech generation.", "Emilia: a second opinion before a costly mistake."],
}

def run(*args):
    subprocess.run([str(a) for a in args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)]))

def caption_image(text, path):
    image = Image.new("RGBA", (1920, 1080))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, 27)
    box = draw.textbbox((0, 0), text, font=font)
    width = box[2] - box[0]
    x = (1920 - width) // 2
    draw.rounded_rectangle((x-22, 797, x+width+22, 846), radius=10, fill=(8, 12, 10, 242))
    draw.text((x, 806), text, font=font, fill=(246, 244, 235))
    image.save(path)

def main():
    assert sum(row[1] for row in SEGMENTS) == 60
    caption_list = []
    srt = []
    clock = 0.0
    subtitle_index = 1
    for name, seconds, source, start in SEGMENTS:
        print("Rendering " + name, flush=True)
        actual = duration(OUT / AUDIO.get(name, name + ".wav"))
        tempo = max(1.0, actual / (seconds - 0.3))
        run("ffmpeg", "-y", "-ss", start, "-i", OUT/source, "-i", OUT/AUDIO.get(name, name+".wav"),
            "-filter_complex", f"[0:v]scale=1670:1080,pad=1920:1080:125:0:color=0x0b0d0c,fps=30,setsar=1[v];[1:a]atempo={tempo},apad,atrim=duration={seconds},loudnorm=I=-16:TP=-1.5:LRA=9[a]",
            "-map", "[v]", "-map", "[a]", "-t", seconds, "-c:v", "libx264", "-preset", "fast", "-crf", 19, "-pix_fmt", "yuv420p", "-c:a", "aac", "-ar", 48000, "-b:a", "192k", OUT/(name+"-cut.mp4"))
        lines = CAPTIONS[name]
        weights = [len(line.replace("SIMULATED CALLER: ", "").split()) for line in lines]
        for i,(line,weight) in enumerate(zip(lines,weights)):
            length = seconds * weight / sum(weights)
            path = OUT / f"caption-{name}-{i}.png"
            caption_image(line, path)
            caption_list.extend([f"file '{path}'", f"duration {length:.8f}"])
            def timestamp(t):
                ms = round(t*1000); return f"00:{ms//60000:02}:{ms//1000%60:02},{ms%1000:03}"
            srt.append(f"{subtitle_index}\n{timestamp(clock)} --> {timestamp(clock+length)}\n{line}\n")
            clock += length; subtitle_index += 1
    (OUT/"captions.srt").write_text("\n".join(srt))
    caption_list.append(caption_list[-2])
    (OUT/"captions.concat").write_text("\n".join(caption_list)+"\n")
    (OUT/"clips.concat").write_text("\n".join(f"file '{OUT/(name+'-cut.mp4')}'" for name,*_ in SEGMENTS)+"\n")
    run("ffmpeg", "-y", "-f", "concat", "-safe", 0, "-i", OUT/"clips.concat", "-c", "copy", OUT/"assembled.mp4")
    run("ffmpeg", "-y", "-i", OUT/"assembled.mp4", "-f", "concat", "-safe", 0, "-i", OUT/"captions.concat",
        "-filter_complex", "[0:v][1:v]overlay=0:0:format=auto[v]", "-map", "[v]", "-map", "0:a", "-t", 60, "-r", 30,
        "-c:v", "libx264", "-preset", "fast", "-crf", 18, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", OUT/"Emilia-60s-demo.mp4")
    measured = duration(OUT/"Emilia-60s-demo.mp4")
    assert abs(measured - 60) < 0.04, measured
    (OUT/"edit-receipt.json").write_text(json.dumps({"duration_seconds": measured, "segments": SEGMENTS, "narration_model": "gpt-4o-mini-tts-2025-12-15", "simulated_caller": "macOS Samantha speech", "warning": "Live Realtime/Astra response; no forced alert", "caption_timing": "Phrase timings approximated from word count", "detector": "Recovered Emilia v8, seed 1, explicit wideband assumption; controlled demo, not an accuracy or latency benchmark"}, indent=2))
    print("Finished: " + str(OUT/"Emilia-60s-demo.mp4"), flush=True)

if __name__ == "__main__":
    main()
