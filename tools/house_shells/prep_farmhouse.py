"""Prepares the Bone County farmhouse shell's build (tools/house_shells/des_farmhouse1.py): extracts the vanilla house
(model 16280, des_farmhouse1_, its DFF from gta3.img and its COL from countn2_10.col) into
tools/trailer_shells/build/vanilla/ (where the Shell class of tools/trailer_shells/common.py reads it), and writes the
shell's texture dictionary, house_shell/files/des_farmhouse1.txd: what the house wears of oldwest.txd, the run-down
interior the Fort Carson houses have (ganghoos.txd in gta_int.img), plus the see-through house_window pane and its
curtains. Every texture also goes to build/tex/<name>.png for Blender, decoded with gta-scout's TXDReader.

    python -m tools.house_shells.prep_farmhouse [--gta DIR]
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
VANILLA_NAME, NAME, TXD, COL_ARCHIVE = "des_farmhouse1_", "des_farmhouse1", "oldwest", "countn2_10.col"
INTERIOR = ("gta_int.img", "ganghoos", {"mp_burn_wall2", "mp_burn_wall4", "mp_burn_ceiling", "mp_burn_carpet1", "ab_wood1", "kitchen-wall1", "barbersflr1"})
GLASS = {"house_window", "ah_curtains1"}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("prep_farmhouse: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    dff = read_img_entry(gta3, index[f"{VANILLA_NAME}.dff"])
    (vanilla / f"{NAME}.dff").write_bytes(dff)
    for col, data in parse_col_library(read_img_entry(gta3, index[COL_ARCHIVE])).items():
        if col.lower() == VANILLA_NAME:
            (vanilla / f"{NAME}.col").write_bytes(data)
    whole = read_img_entry(gta3, index[f"{TXD}.txd"])
    names = {n[32:64].split(b"\0", 1)[0].decode("latin1").lower() for n in txd_natives(whole)[2]}
    img, txd, wanted = INTERIOR
    archive = gta / "models" / img
    parts = [
        trim_txd(whole, dff_strings(dff) & names),
        trim_txd(read_img_entry(archive, read_img_index(archive)[f"{txd}.txd"]), wanted),
        trim_txd(HOUSE_WINDOW_TXD.read_bytes(), GLASS),
    ]
    merged = merge_txd(parts)
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    (SHELL_FILES / f"{NAME}.txd").write_bytes(merged)
    (vanilla / f"{NAME}.txd").write_bytes(merged)
    env = {**os.environ, "GTA_SCOUT": os.environ.get("GTA_SCOUT", "/gta/sa/gta-scout")}
    subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"{NAME}.txd"), str(BUILD / "tex")], check=True, env=env)
    print(f"prep_farmhouse: {NAME} in {vanilla}, {NAME}.txd ({len(merged)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
