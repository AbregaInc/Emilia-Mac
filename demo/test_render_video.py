import importlib.util
from pathlib import Path
import unittest
from PIL import Image, ImageFont
import tempfile

spec = importlib.util.spec_from_file_location("render_video", Path(__file__).with_name("render-video.py"))
video = importlib.util.module_from_spec(spec)
spec.loader.exec_module(video)

class DemoContractTests(unittest.TestCase):
    def test_exact_one_minute_timeline(self):
        self.assertEqual(sum(segment[1] for segment in video.SEGMENTS), 60)

    def test_every_segment_has_audio_and_captions(self):
        for name, seconds, source, start in video.SEGMENTS:
            self.assertTrue(video.CAPTIONS[name])
            self.assertGreater(seconds, 0)
            self.assertGreaterEqual(start, 0)
            self.assertTrue((video.OUT / (name + ".wav")).is_file())
            self.assertGreaterEqual(video.duration(video.OUT / source), start + seconds)

    def test_captions_fit_frame(self):
        font = ImageFont.truetype(video.FONT, 27)
        for lines in video.CAPTIONS.values():
            for line in lines:
                self.assertLess(font.getlength(line), 1850)

    def test_export_is_sixty_seconds_and_decodable(self):
        path = video.OUT / "Emilia-60s-demo.mp4"
        self.assertAlmostEqual(video.duration(path), 60, places=2)
        video.run("ffmpeg", "-v", "error", "-i", path, "-f", "null", "-")

    def test_real_border_and_card_share_the_recorded_display(self):
        with tempfile.TemporaryDirectory() as directory:
            frame = Path(directory) / "warning.png"
            video.run("ffmpeg", "-y", "-ss", 28, "-i", video.OUT / "Emilia-60s-demo.mp4", "-frames:v", 1, frame)
            image = Image.open(frame).convert("RGB")
            def warm_pixels(box):
                return sum(r > 170 and r > g * 1.5 and r > b * 1.5 for r, g, b in image.crop(box).getdata())
            self.assertGreater(warm_pixels((125, 100, 135, 900)), 2500, "Red screen border missing")
            self.assertGreater(warm_pixels((1390, 50, 1790, 280)), 400, "Warning card missing from recording display")

if __name__ == "__main__":
    unittest.main()
