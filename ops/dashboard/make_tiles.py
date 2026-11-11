#!/usr/bin/env python3
"""Builds the satellite tile pyramid the staff map's "Terrain" base map reads (tiles/{z}/{x}/{y}.jpg).

    python3 -I ops/dashboard/make_tiles.py --source-tiles DIR --out /var/www/nasa/ssmta/tiles
    python3 -I ops/dashboard/make_tiles.py --image world.png   --out /var/www/nasa/ssmta/tiles

--source-tiles is the `satellite_tiles` folder of github.com/interactive-game-maps/grand_theft_auto_san_andreas (zoom 5:
24 x 24 tiles of 256 px, one pixel per metre, file {x}/{y}.png with y = 0 on the north edge, so the first 6000 px
cover the world exactly). --image takes any square picture of the 6000 m world, north up, instead.

Output: zoom z has 2^z x 2^z tiles of 256 px over the 6000 m world, row 0 along the north edge (the page's CRS in
web/app.js). Zoom 0..5; beyond that the page upscales. Run with `-I`: the source folder is untrusted data.
The source is a fan render of Rockstar's game art with no licence of its own: keep the output on the LAN.
"""
import argparse
import os
from pathlib import Path

from PIL import Image

Image.MAX_IMAGE_PIXELS = 200_000_000
WORLD_PX = 6000
TILE = 256
MAX_ZOOM = 5


def stitch(source: Path) -> Image.Image:
    base = source / "5"
    n = 24
    canvas = Image.new("RGB", (n * TILE, n * TILE))
    for x in range(n):
        for y in range(n):
            tile = base / str(x) / f"{y}.png"
            if not tile.is_file():
                raise SystemExit(f"missing source tile {tile}")
            canvas.paste(Image.open(tile).convert("RGB"), (x * TILE, y * TILE))
    return canvas.crop((0, 0, WORLD_PX, WORLD_PX))


def main() -> None:
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--source-tiles", type=Path)
    src.add_argument("--image", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--quality", type=int, default=84)
    args = ap.parse_args()

    world = stitch(args.source_tiles) if args.source_tiles else Image.open(args.image).convert("RGB")
    if world.width != world.height:
        raise SystemExit("the world image must be square")

    side = TILE * 2**MAX_ZOOM
    master = world.resize((side, side), Image.LANCZOS)
    count = 0
    for z in range(MAX_ZOOM, -1, -1):
        size = TILE * 2**z
        level = master if z == MAX_ZOOM else master.resize((size, size), Image.LANCZOS)
        for x in range(2**z):
            folder = args.out / str(z) / str(x)
            folder.mkdir(parents=True, exist_ok=True)
            for y in range(2**z):
                level.crop((x * TILE, y * TILE, (x + 1) * TILE, (y + 1) * TILE)).save(
                    folder / f"{y}.jpg", quality=args.quality, optimize=True
                )
                count += 1
    print(f"wrote {count} tiles to {args.out}")


if __name__ == "__main__":
    main()
