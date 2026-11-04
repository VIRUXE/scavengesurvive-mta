"""Builds the website's image assets from docs/images.

    python -m tools.site_assets [--clean]

Writes WebP copies under site/assets/img/ (committed, so GitHub Pages needs no build step) and
site/assets/img/index.json, which lists every generated file with its size and the caption of the
source (docs/images/scenes/index.json, docs/images/places/index.json, or the table below). The
originals in docs/images stay the archive; the site never links into docs/ or the wiki.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs" / "images"
OUT = ROOT / "site" / "assets" / "img"

# (source relative to docs/images, output relative to site/assets/img, widths, quality, caption)
SINGLES = [
    ("fort-defiance-sandstorm.jpg", "hero/sandstorm", (1920, 960), 82, "Fort Defiance around Grove Street in a sandstorm"),
    ("logo-reborn.png", "brand/logo", (512, 192, 64), 90, "Scavenge & Survive Reborn mark"),
    ("logo-reborn-hammer.png", "brand/hammer", (512, 192), 90, "The hammer mark"),
    ("loot-vehicle-blista.jpg", "shots/loot-vehicle", (1600, 800), 82, "A loot vehicle: smoking, half-wrecked and almost out of fuel"),
    ("world-item-hotdog.jpg", "shots/world-item", (1600, 800), 82, "A Hotdog on the ground with its label; every item is an object in the world"),
    ("hollow-house-replacement.jpg", "shots/hollow-house", (1600, 800), 82, "An upstream hollow house replacing the sealed vanilla model"),
    ("apparel-body-threequarter.jpg", "shots/apparel-armour", (1600, 800), 82, "The 14 spawn skins in body armour, pistol holstered"),
    ("apparel-captainscap.jpg", "shots/apparel-captainscap", (1600, 800), 82, "A Captain's Cap across the 14 spawn skins"),
    ("apparel-masks-female.jpg", "shots/apparel-masks", (1600, 800), 82, "Masks fitted on the female skins"),
    ("cut-hats-alone.jpg", "shots/cut-hats", (1800, 900), 82, "The nine hats cut off the headgear skins, as loot items"),
    ("cut-hats.jpg", "shots/cut-hats-worn", (2160, 1080), 82, "The nine cut hats, worn"),
    ("hatless-twins-helmet.jpg", "shots/hatless-helmet", (1200, 600), 82, "Skins whose mesh carries its own helmet"),
    ("hatless-twins-remodelled.jpg", "shots/hatless-remodelled", (1200, 600), 82, "The same skins with the headgear removed and the head rebuilt"),
    ("clothes-changing-bar.jpg", "shots/clothes-changing", (1600, 800), 82, "Changing clothes: the hold bar"),
    ("auth-dialog-register.jpg", "shots/auth-register", (1600, 800), 82, "The register dialog"),
    ("auth-dialog-welcome-countdown.jpg", "shots/auth-welcome", (1600, 800), 82, "The welcome text with its countdown"),
    ("studio-threequarter.jpg", "shots/studio", (1600, 800), 82, "The green-screen studio used for the apparel sheets"),
    ("bobcat_parts_1.png", "shots/bobcat-parts-1", (1400, 700), 85, "The twelve Bobcat salvage parts, good and bad"),
    ("bobcat_parts_2.png", "shots/bobcat-parts-2", (1400, 700), 85, "Bobcat salvage parts fitted and loose"),
    ("bobcat_tailgate_logo.png", "shots/bobcat-tailgate", (1500, 750), 85, "The Bobcat tailgate"),
    ("vehicles/sheet_1.png", "vehicles/sheet-1", (1600, 800), 82, "Vehicle renders, sheet 1"),
    ("vehicles/sheet_2.png", "vehicles/sheet-2", (1600, 800), 82, "Vehicle renders, sheet 2"),
    ("items/boxes/sheet_1.png", "items/boxes-sheet", (1600, 800), 82, "GTA's own boxes and crates, cut into items"),
]

FOLDERS = [
    # (source folder, output folder, widths, quality, caption index json or None)
    ("scenes", "scenes", (1600, 800), 82, "scenes/index.json"),
    ("places", "places", (1600, 800), 82, "places/index.json"),
    ("map", "map", (1536,), 88, None),
    ("items/all", "items", (256,), 85, None),
    ("vehicles", "vehicles", (480,), 85, None),
]

MAP_CAPTIONS = {
    "base": "San Andreas, the radar tiles",
    "overview": "Everything on one map",
    "zones": "The seven zones that decide how much loot each region holds",
    "loot": "Every loot point",
    "vehicles": "Every vehicle point",
    "drops": "Supply drop points",
    "spawns": "The beaches a new character wakes up on",
    "shelters": "Houses, trailers and cabins you can enter",
    "puzzles": "The code hunt and the puzzles",
    "fixtures": "Workbenches, machines, barbecues and campfires",
    "features": "Ladders, ziplines, fuel outlets and the rest",
}


def save(im: Image.Image, dest: Path, width: int, quality: int) -> tuple[int, int]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    w, h = im.size
    if w > width:
        im = im.resize((width, round(h * width / w)), Image.LANCZOS)
    has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
    im = im.convert("RGBA" if has_alpha else "RGB")
    im.save(dest, "WEBP", quality=quality, method=6)
    return im.size


def convert(src: Path, out_stem: str, widths, quality: int, caption: str, index: dict) -> None:
    im = Image.open(src)
    entry = {"caption": caption, "sizes": {}}
    for width in widths:
        suffix = "" if width == widths[0] else f"-{width}"
        dest = OUT / f"{out_stem}{suffix}.webp"
        w, h = save(im.copy(), dest, width, quality)
        entry["sizes"][str(width)] = {"file": dest.relative_to(OUT).as_posix(), "w": w, "h": h, "bytes": dest.stat().st_size}
    index[out_stem] = entry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clean", action="store_true", help="delete site/assets/img first")
    args = parser.parse_args()
    if args.clean and OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True, exist_ok=True)
    index: dict = {}
    for rel, stem, widths, quality, caption in SINGLES:
        src = SRC / rel
        if not src.exists():
            print("missing", src)
            continue
        convert(src, stem, widths, quality, caption, index)
    for folder, out, widths, quality, captions_file in FOLDERS:
        captions = json.loads((SRC / captions_file).read_text()) if captions_file else {}
        for src in sorted((SRC / folder).iterdir()):
            if src.suffix.lower() not in (".png", ".jpg", ".jpeg") or src.stem.startswith("sheet"):
                continue
            name = src.stem
            if folder == "map":
                caption = MAP_CAPTIONS.get(name, name)
            elif captions_file:
                caption = captions.get(name, {}).get("caption", name)
            else:
                caption = name.split("_", 1)[-1] if "_" in name else name
            convert(src, f"{out}/{name}", widths, quality, caption, index)
    (OUT / "index.json").write_text(json.dumps(index, indent=1, sort_keys=True) + "\n")
    total = sum(p.stat().st_size for p in OUT.rglob("*.webp"))
    print(f"{len(index)} assets, {total / 1024 / 1024:.1f} MB under {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
