"""sheet.py <out.png> <modes> <prefix> [<prefix> ...]: one row per prefix and mode (modes: grey, tex or grey,tex) of the ten review views."""
import sys

from PIL import Image, ImageDraw

VIEWS = ["f", "fl", "l", "bl", "b", "br", "r", "fr", "top", "low"]
out, modes, prefixes = sys.argv[1], sys.argv[2].split(","), sys.argv[3:]
T = 200
W = Image.new("RGB", (len(VIEWS) * T, T * len(prefixes) * len(modes)), (30, 30, 30))
d = ImageDraw.Draw(W)
row = 0
for p in prefixes:
    for mode in modes:
        for c, v in enumerate(VIEWS):
            try:
                im = Image.open(f"{p}-{mode}-{v}.png").convert("RGB").resize((T, T))
            except FileNotFoundError:
                continue
            W.paste(im, (c * T, row * T))
        d.text((4, row * T + 4), p.replace("\\", "/").split("/")[-1] + " " + mode, fill=(255, 255, 0))
        row += 1
W.save(out)
print(W.size)
