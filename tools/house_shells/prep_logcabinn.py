"""Prepares the Shady Cabin's build (tools/house_shells/logcabinn01.py): writes the texture dictionary of the rebuilt
cabin, house_shell/files/logcabinn01.txd, out of the game's own textures (found with gta-scout's catalogue and a scan
of the TXD names in gta3.img): the peeled log wall and log end, old boards, floor and deck planks, the mossy shake roof,
rusted corrugated sheets, fieldstone, the braced plank door and the hinged shutter, plus the house shells' see-through
house_window pane. Every texture also goes to tools/trailer_shells/build/tex/<name>.png for Blender, decoded with
gta-scout's TXDReader. The vanilla model (18259, logcabinn01) is not read: the cabin is built from nothing.

    python -m tools.house_shells.prep_logcabinn [--gta DIR]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from tools.extract_samp_models import detect_gta, merge_txd, read_img_entry, read_img_index, trim_txd
from tools.trailer_shells.prep import BUILD, HOUSE_WINDOW_TXD, SHELL_FILES

HERE = Path(__file__).resolve().parent
NAME = "logcabinn01"
# texture -> the gta3.img dictionary it is taken from
TEXTURES = {
    "cw2_logwall": "desn_truckstop",
    "gen_log_end": "gta_brokentrees",
    "sw_cabinwall01": "sw_oldshack",
    "sw_cabshut01": "sw_oldshack",
    "sw_cabinroof": "desn2_minestuff",
    "sw_corrug": "ce_loadbay",
    "des_oldtinroof": "des_boneyard",
    "des_ghotwood1": "a51_stores",
    "planks01": "rc_warhoose",
    "sw_woodflloor": "sw_apartments",
    "stonewall_la": "oc_flats_gnd_sfs",
    "cj_wooddoor4": "ext_doors2",
}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("prep_logcabinn: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    parts = []
    for texture, txd in TEXTURES.items():
        entry = index.get(f"{txd}.txd") or next(v for k, v in index.items() if k.startswith(txd) and k.endswith(".txd"))
        parts.append(trim_txd(read_img_entry(gta3, entry), {texture}))
    parts.append(trim_txd(HOUSE_WINDOW_TXD.read_bytes(), {"house_window"}))
    merged = merge_txd(parts)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    (SHELL_FILES / f"{NAME}.txd").write_bytes(merged)
    (vanilla / f"{NAME}.txd").write_bytes(merged)
    env = {**os.environ, "GTA_SCOUT": os.environ.get("GTA_SCOUT", "/gta/sa/gta-scout")}
    subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"{NAME}.txd"), str(BUILD / "tex")], check=True, env=env)
    print(f"prep_logcabinn: {NAME}.txd ({len(merged)} bytes, {len(TEXTURES) + 1} textures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
