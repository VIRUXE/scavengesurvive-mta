"""The toxic cloud's puff texture: `python -m tools.toxic_textures` writes `toxic/files/puff.png`.

One billowing lump of gas on a transparent ground, white so the client tints it: a cauliflower outline made of
overlapping discs, broken up by cloud noise, lit from above and thinning to nothing at the foot so a puff standing
on the ground has no hard edge there. The seed is fixed, so a run gives the same file.
"""

from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 256
OUT = Path(__file__).resolve().parents[1] / "resources" / "[scavengesurvive]" / "toxic" / "files" / "puff.png"


def noise(rng, size, octaves=5):
    """Cloud noise 0..1: random grids of doubling detail, each smoothed up to the full size and halved in weight."""
    total, weight, amp = np.zeros((size, size)), 0.0, 1.0
    for o in range(octaves):
        cells = 4 * 2**o
        grid = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
        total += amp * np.asarray(grid.resize((size, size), Image.BICUBIC), dtype=float) / 255
        weight += amp
        amp *= 0.5
    return total / weight


def puff(rng):
    y, x = np.mgrid[0:SIZE, 0:SIZE] / (SIZE - 1)
    # a broad mound standing on the bottom edge, with lumps along its crown: big in the middle, smaller at the sides
    mound = np.sqrt(((x - 0.5) / 0.44) ** 2 + ((y - 0.74) / 0.42) ** 2)
    body = np.clip((1 - mound) / 0.35, 0, 1)
    for _ in range(34):
        cx = rng.uniform(0.12, 0.88)
        spread = 1 - abs(cx - 0.5) * 1.6
        cy = rng.uniform(0.26, 0.6) + (1 - spread) * 0.22
        r = rng.uniform(0.1, 0.19) * (0.6 + spread * 0.6)
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        body = np.maximum(body, np.clip(1 - d / r, 0, 1) ** 0.5)
    n = noise(rng, SIZE)
    alpha = np.clip(body * 1.6 - (1 - n) * 0.55, 0, 1) ** 0.8
    alpha *= np.clip((1 - y) / 0.18, 0, 1)  # thins out at the foot
    alpha *= np.clip(np.minimum(x, 1 - x) / 0.06, 0, 1) * np.clip(y / 0.06, 0, 1)  # never touches the border
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.BICUBIC)) / 255
    light = np.clip(0.62 + (1 - y) * 0.3 + (n - 0.5) * 0.35, 0, 1)  # brighter crowns, darker folds
    rgba = np.dstack([light, light, light, alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    puff(np.random.default_rng(20261122)).save(OUT, optimize=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
