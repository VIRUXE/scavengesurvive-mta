"""Prepares the Marquis cabin's build (tools/marquis_cabin/cabin.py): extracts the vanilla marquis.dff/.txd from
gta3.img into tools/marquis_cabin/build/vanilla/, writes the cabin's texture dictionary build/vanilla/cabin.txd (the
interior textures picked with gta-scout, out of gta_int.img) and decodes every texture the build draws with to
build/tex/<name>.png for Blender, with gta-scout's TXDReader (node, tools/trailer_shells/txd_png.mjs).

    python -m tools.marquis_cabin.prep [--gta DIR]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from tools.extract_samp_models import detect_gta, merge_txd, read_img_entry, read_img_index, trim_txd

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
SCOUT = Path(os.environ.get("GTA_SCOUT", str(ROOT.parents[3] / "gta-scout")))
TXD_PNG = ROOT / "tools" / "trailer_shells" / "txd_png.mjs"
# the cabin's textures (gta_int.img dictionary -> texture), chosen in gta-scout (asset-catalog search, 2026-11-08)
CABIN = {
    "bdupshifi": "bdup2_wood",  # mahogany joinery: linings, bulkheads, lockers, settee bases
    "lee_strip2": "strip_wood",  # planked cabin sole
    "cj_beds": "cj_matress2",  # the V-berth's mattress (striped ticking)
    "kit3hghg": "stove_1",  # galley cooker front
}
# ship headlining lives in gta3.img, not gta_int (riveted panels, gta-scout: frieghter2sfe / sf_ship_ceiling)
HULL = {"frieghter2sfe": "sf_ship_ceiling"}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("marquis_cabin.prep: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    vanilla, tex = BUILD / "vanilla", BUILD / "tex"
    vanilla.mkdir(parents=True, exist_ok=True)
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    for name in ("marquis.dff", "marquis.txd"):
        (vanilla / name).write_bytes(read_img_entry(gta3, index[name]))
    gta_int = gta / "models" / "gta_int.img"
    int_index = read_img_index(gta_int)
    parts = [trim_txd(read_img_entry(gta_int, int_index[f"{txd}.txd"]), {name}) for txd, name in CABIN.items()]
    parts += [trim_txd(read_img_entry(gta3, index[f"{txd}.txd"]), {name}) for txd, name in HULL.items()]
    (vanilla / "cabin.txd").write_bytes(merge_txd(parts))
    env = {**os.environ, "GTA_SCOUT": str(SCOUT)}
    for txd in (vanilla / "marquis.txd", vanilla / "cabin.txd", gta / "models" / "generic" / "vehicle.txd"):
        subprocess.run(["node", str(TXD_PNG), str(txd), str(tex)], check=True, env=env)
    return 0


if __name__ == "__main__":
    sys.exit(main())
