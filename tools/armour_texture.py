"""Build the armour vest's dedicated dictionary from its reviewed HD atlas.

    python -m tools.armour_texture

The vest keeps its original DFF, UVs and texture name. Model 19515 uses
swatagrey.txd independently of the SWAT helmet's swathgrey.txd.
"""
from pathlib import Path

from PIL import Image

from tools.make_vending import write_txd
from tools.wheel_hd import native_dxt1

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "data" / "armour_texture" / "swat.png"
OUTPUT = ROOT / "resources" / "[scavengesurvive]" / "samp_models" / "files" / "swatagrey.txd"


def main():
    with Image.open(SOURCE) as image:
        if image.size != (512, 1024):
            raise ValueError(f"Expected a 512x1024 atlas, got {image.size}")
        if image.convert("RGBA").getextrema()[3] != (255, 255):
            raise ValueError("The vest atlas must be opaque")
        write_txd(OUTPUT, [native_dxt1("swat", image)])
    print(f"{OUTPUT.relative_to(ROOT)}: {OUTPUT.stat().st_size:,} bytes, BC1, 11 mip levels")


if __name__ == "__main__":
    main()
