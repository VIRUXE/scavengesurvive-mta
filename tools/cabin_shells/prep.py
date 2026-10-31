"""Prepares the log cabin shell's build (tools/cabin_shells/cw2_logcabins.py): extracts the vanilla cabin row (model
17067, DFF and TXD from gta3.img, COL from countryw_4.col) into tools/trailer_shells/build/vanilla/ (the Shell class of
tools/trailer_shells/common.py reads its vanilla files there), and writes the texture dictionary of the shell,
house_shell/files/cw2_logcabins.txd: the vanilla one plus the see-through house_window pane and the curtains of the
trailers' windows. Every texture also goes to build/tex/<name>.png for Blender, decoded with gta-scout's TXDReader.

    python -m tools.cabin_shells.prep [--gta DIR]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from tools.extract_samp_models import detect_gta, merge_txd, parse_col_library, read_img_entry, read_img_index, trim_txd
from tools.trailer_shells.prep import BUILD, HOUSE_WINDOW, HOUSE_WINDOW_TXD, SHELL_FILES

HERE = Path(__file__).resolve().parent
NAME = "cw2_logcabins"
COL_ARCHIVE = "countryw_4.col"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("cabin_shells.prep: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    (vanilla / f"{NAME}.dff").write_bytes(read_img_entry(gta3, index[f"{NAME}.dff"]))
    for name, data in parse_col_library(read_img_entry(gta3, index[COL_ARCHIVE])).items():
        if name.lower() == NAME:
            (vanilla / f"{NAME}.col").write_bytes(data)
    glass = trim_txd(HOUSE_WINDOW_TXD.read_bytes(), HOUSE_WINDOW)
    merged = merge_txd([read_img_entry(gta3, index[f"{NAME}.txd"]), glass])
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    (SHELL_FILES / f"{NAME}.txd").write_bytes(merged)
    (vanilla / f"{NAME}.txd").write_bytes(merged)
    tex = BUILD / "tex"
    subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"{NAME}.txd"), str(tex)], check=True)
    print(f"cabin_shells.prep: {NAME} in {vanilla}, {NAME}.txd ({len(merged)} bytes), PNGs in {tex}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
