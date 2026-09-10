"""Assemble a 60 s demo from real recordings and original OpenAI narration."""
import json
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, str(Path(__file__).resolve().parent))
from storyboard import STORY

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/demo"
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"

SEGMENTS = [row[:4] for row in STORY]
AUDIO = {"caller": "caller-system.wav"}
CAPTIONS = {row[0]: [("SIMULATED CALLER: " if row[0] == "caller" else "") + row[4].replace("GPT-six", "GPT-6")] for row in STORY}

def caption_lines(text):
    font = ImageFont.truetype(FONT, 25)
    lines = [""]
    for word in text.split():
        candidate = (lines[-1] + " " + word).strip()
        if font.getlength(candidate) > 1700:
            lines.append(word)
        else:
            lines[-1] = candidate
    return lines

def run(*args):
    subprocess.run([str(a) for a in args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)]))

def caption_image(text, path):
    image = Image.new("RGBA", (1920, 1080))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, 25)
    lines = caption_lines(text)
    width = max(font.getlength(line) for line in lines)
    x = (1920 - width) // 2
    draw.rounded_rectangle((x-22, 797, x+width+22, 809+28*len(lines)), radius=10, fill=(8, 12, 10, 242))
    for i,line in enumerate(lines):
        draw.text(((1920-font.getlength(line))/2, 802+28*i), line, font=font, fill=(246, 244, 235))
    image.save(path)

def research_card(name, path):
    image = Image.new("RGBA", (1920,1080))
    draw = ImageDraw.Draw(image)
    draw.rectangle((175,185,765,740), fill=(11,13,12,255))
    title, lines = {
        "research": ("EMILIA AUTORESEARCH", ["OpenAI models at the helm", "Codex research workflow", "", "Plan experiments", "Run and verify", "Evaluate → iterate", "", "Existing research · predates hackathon"]),
        "architecture": ("EMILIA v8 · ON DEVICE", ["3 seconds of audio", "↓", "4-block W2v-BERT encoder", "↓", "Router + fitted classifier heads", "↓", "Synthetic-voice evidence", "", "Seed 1 · assumed wideband"]),
        "contribution": ("BUILT AT THE HACKATHON", ["Native macOS app", "Mic + system audio", "Realtime + Astra integration", "Amber + grounded red warnings", "", "Built using Astra in Codex", "", "Emilia research predates this event"]),
    }[name]
    draw.text((190,218),title,font=ImageFont.truetype(FONT,29),fill=(255,157,48))
    for i,line in enumerate(lines):
        draw.text((190,284+i*43),line,font=ImageFont.truetype(FONT,26),fill=(235,234,221))
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
        # Clip-local narration and captions start together. No word-count timing estimates.
        assert tempo <= 1.30, (name, "Narration too long; rewrite instead of rushing", tempo)
        card = OUT / (name + "-card.png")
        extra = []
        vf = "[0:v]scale=1670:1080,pad=1920:1080:125:0:color=0x0b0d0c,fps=30,setsar=1[v]"
        if name in ("research", "architecture", "contribution"):
            research_card(name, card)
            extra = ["-loop", "1", "-i", card]
            vf = vf.replace("[v]", "[base]") + ";[base][2:v]overlay=0:0[v]"
        run("ffmpeg", "-y", "-ss", start, "-i", OUT/source, "-i", OUT/AUDIO.get(name, name+".wav"),
            *extra, "-filter_complex", f"{vf};[1:a]atempo={tempo},apad,atrim=duration={seconds},loudnorm=I=-16:TP=-1.5:LRA=9[a]",
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
    (OUT/"edit-receipt.json").write_text(json.dumps({"duration_seconds": measured, "segments": SEGMENTS, "narration_model": "gpt-4o-mini-tts-2025-12-15", "simulated_caller": "macOS Samantha speech", "warning": "Live Realtime/Astra response; no forced alert", "caption_timing": "One caption per narration clip, aligned to its matching visible state", "research": "Existing Codex autoresearch directed by OpenAI models; informational overlays, not a recording of a research run", "detector": "Recovered Emilia v8, seed 1, explicit wideband assumption; controlled demo, not an accuracy or latency benchmark"}, indent=2))
    print("Finished: " + str(OUT/"Emilia-60s-demo.mp4"), flush=True)

if __name__ == "__main__":
    main()
