"""Prepares the trailer shells' build (tools/trailer_shells/<model>.py): extracts the nine vanilla trailers (models
3167-3175, DFF from gta3.img, COL from counxref.col / cuntysouth.col) into tools/trailer_shells/build/vanilla/, and
writes the one texture dictionary they all share, house_shell/files/trailers.txd: the vanilla `trailers` dictionary
plus the trailer interior's panelling, ceiling, carpet, lino, trim and curtain (gta_int.img trailerkb.txd) and the
house shells' see-through house_window pane. Every texture also goes to build/tex/<name>.png for Blender, decoded with
gta-scout's TXDReader (node).

    python -m tools.trailer_shells.prep [--gta DIR]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from tools.extract_samp_models import detect_gta, parse_col_library, read_img_entry, read_img_index, trim_txd
from tools.make_fort_kit import merge_txd

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
SHELL_FILES = ROOT / "resources" / "[scavengesurvive]" / "house_shell" / "files"
HOUSE_WINDOW_TXD = ROOT / "resources" / "[scavengesurvive]" / "models" / "files" / "house_window.txd"
TRAILERS = {
    3167: "trailer_large1_01",
    3168: "trailer2_01",
    3169: "trailer_large2_01",
    3170: "trailer_large3_01",
    3171: "trailer5_01",
    3172: "trailer6_01",
    3173: "trailer_large4_01",
    3174: "sm_airstrm_sml_",
    3175: "sm_airstrm_med_",
}
COL_ARCHIVES = ("counxref.col", "cuntysouth.col")
INTERIOR = {"tr_wall2", "tr_wall3", "carp19s", "tr_floor2", "tr_wood1", "curtain_sink2"}  # out of trailerkb.txd


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("trailer_shells.prep: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3, gta_int = gta / "models" / "gta3.img", gta / "models" / "gta_int.img"
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    index = read_img_index(gta3)
    for name in TRAILERS.values():
        (vanilla / f"{name}.dff").write_bytes(read_img_entry(gta3, index[f"{name}.dff"]))
    wanted = set(TRAILERS.values())
    for archive in COL_ARCHIVES:
        for name, data in parse_col_library(read_img_entry(gta3, index[archive])).items():
            if name.lower() in wanted:
                (vanilla / f"{name.lower()}.col").write_bytes(data)
    trailers = read_img_entry(gta3, index["trailers.txd"])
    kb = read_img_entry(gta_int, read_img_index(gta_int)["trailerkb.txd"])
    glass = trim_txd(HOUSE_WINDOW_TXD.read_bytes(), {"house_window"})
    merged = merge_txd([trailers, trim_txd(kb, INTERIOR), glass])
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    (SHELL_FILES / "trailers.txd").write_bytes(merged)
    (vanilla / "trailers.txd").write_bytes(merged)
    tex = BUILD / "tex"
    subprocess.run(["node", str(HERE / "txd_png.mjs"), str(vanilla / "trailers.txd"), str(tex)], check=True)
    print(f"trailer_shells.prep: {len(TRAILERS)} trailers in {vanilla}, trailers.txd ({len(merged)} bytes), PNGs in {tex}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
