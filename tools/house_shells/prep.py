"""Prepares the Fort Carson house shells' builds (tools/house_shells/des_bighus0N.py): extracts the vanilla houses
(models 3305, 3304 and 3303: des_bighus01-03, DFFs and their shared TXD des_bighus from gta3.img, COLs from
cuntdesxref.col) into tools/trailer_shells/build/vanilla/ (the
Shell class of tools/trailer_shells/common.py reads its vanilla files there), and writes each
shell's texture dictionary, house_shell/files/des_bighus0N.txd: what the house wears of the vanilla one, the interior's walls, floors and ceiling (picked with
GTA Scout out of the run-down house interior ganghoos.txd in gta_int.img, and the concrete of ce_burbhouse.txd in
gta3.img), plus the see-through house_window pane and its curtains. Every texture also goes to build/tex/<name>.png
for Blender, decoded with gta-scout's TXDReader (GTA_SCOUT points at the gta-scout clone).

    python -m tools.house_shells.prep [--gta DIR]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from tools.extract_samp_models import detect_gta, dff_strings, merge_txd, parse_col_library, read_img_entry, read_img_index, trim_txd, txd_natives
from tools.trailer_shells.prep import BUILD, HOUSE_WINDOW_TXD, SHELL_FILES

HERE = Path(__file__).resolve().parent
NAMES, TXD = ("des_bighus01", "des_bighus02", "des_bighus03"), "des_bighus"
COL_ARCHIVE = "cuntdesxref.col"
# (image, dictionary, textures) of the interior
INTERIOR = (
    ("gta_int.img", "ganghoos", {"mp_burn_wall2", "mp_burn_wall4", "mp_burn_ceiling", "mp_burn_carpet1", "ab_wood1", "kitchen-wall1", "barbersflr1"}),
    ("gta3.img", "ce_burbhouse", {"floor_tileone_256"}),
)
GLASS = {"house_window", "ah_curtains1"}
TRIM = "des_ghotwood1"  # the reveals' and the garages' boards, worn by every house even where its vanilla skin is not


def vanilla_textures(dff: bytes, txd: bytes) -> set[str]:
    """What a house wears out of des_bighus.txd (the dictionary serves all three houses and the yards around them),
    plus the trim its reveals take. A name in the DFF with a space in it ("des_dirt2 trackl") is read as two."""
    names = {n[32:64].split(b"\0", 1)[0].decode("latin1").lower() for n in txd_natives(txd)[2]}
    used = dff_strings(dff)
    used |= {n for n in names if " " in n and all(w in used for w in n.split())}
    return (used & names) | {TRIM}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("house_shells.prep: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    cols = parse_col_library(read_img_entry(gta3, index[COL_ARCHIVE]))
    shared = read_img_entry(gta3, index[f"{TXD}.txd"])
    interior = []
    for img, txd, names in INTERIOR:
        archive = gta / "models" / img
        interior.append(trim_txd(read_img_entry(archive, read_img_index(archive)[f"{txd}.txd"]), names))
    interior.append(trim_txd(HOUSE_WINDOW_TXD.read_bytes(), GLASS))
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    tex = BUILD / "tex"
    env = {**os.environ, "GTA_SCOUT": os.environ.get("GTA_SCOUT", "/gta/sa/gta-scout")}
    for name in NAMES:
        dff = read_img_entry(gta3, index[f"{name}.dff"])
        (vanilla / f"{name}.dff").write_bytes(dff)
        for col, data in cols.items():
            if col.lower() == name:
                (vanilla / f"{name}.col").write_bytes(data)
        merged = merge_txd([trim_txd(shared, vanilla_textures(dff, shared))] + interior)
        (SHELL_FILES / f"{name}.txd").write_bytes(merged)
        (vanilla / f"{name}.txd").write_bytes(merged)
        subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"{name}.txd"), str(tex)], check=True, env=env)
        print(f"house_shells.prep: {name} in {vanilla}, {name}.txd ({len(merged)} bytes), PNGs in {tex}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
