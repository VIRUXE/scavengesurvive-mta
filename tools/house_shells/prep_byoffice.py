"""Prepares the Verdant Meadows airstrip office shell's build (tools/house_shells/des_byoffice.py): extracts the vanilla
office (model 16326, des_byoffice), the game's own interior of its ground floor (airfieldhus1 and airfieldhus2, built
6.17 m under the house behind the DESHOUS entry marker) and the house's white door (Gen_doorEXT03, model 1498), DFFs
from gta3.img and COLs from countn2_4.col and dynamic2.col, into tools/trailer_shells/build/vanilla/ (where the Shell
class of tools/trailer_shells/common.py reads them), and writes the shell's texture dictionary,
house_shell/files/des_byoffice.txd: what the office, its interior and its door wear of des_byoffice.txd,
des_airfieldhus.txd and ext_doors_old.txd, plus the see-through house_window pane and the curtains its windows get.
Every texture also goes to build/tex/<name>.png for Blender, decoded with
gta-scout's TXDReader.

    python -m tools.house_shells.prep_byoffice [--gta DIR]
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
NAME = "des_byoffice"
# (model, its TXD, the COL archive holding its collision)
PARTS = (
    ("des_byoffice", "des_byoffice", "countn2_4.col"),
    ("airfieldhus1", "des_airfieldhus", "countn2_4.col"),
    ("airfieldhus2", "des_airfieldhus", "countn2_4.col"),
    ("gen_doorext03", "ext_doors_old", "dynamic2.col"),
)
GLASS = {"house_window", "ah_curtains1"}  # the see-through pane and the curtains, as the Fort Carson houses
# the vanilla interior's furniture (gta_int.img), hung as objects by house_shell: DFFs and PNGs for the renders only
PROPS = (
    ("cj_mlight8", "cj_lighting"), ("cj_foldchair", "cj_seating"), ("cj_b_sink2", "cj_bathroom"), ("cj_kitch1_fridge", "cj_kitchen"),
    ("low_tv_3", "cj_tv"), ("low_bed_5", "cj_beds"), ("low_dinning_1", "cj_tables"), ("cj_radiator_old", "cjtemp"), ("low_couch_1", "cj_sofa"),
)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("prep_byoffice: no GTA:SA folder (pass --gta)", file=sys.stderr)
        return 2
    gta3 = gta / "models" / "gta3.img"
    index = read_img_index(gta3)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    parts = []
    for model, txd, archive in PARTS:
        dff = read_img_entry(gta3, index[f"{model}.dff"])
        (vanilla / f"{model}.dff").write_bytes(dff)
        for col, data in parse_col_library(read_img_entry(gta3, index[archive])).items():
            if col.lower() == model:
                (vanilla / f"{model}.col").write_bytes(data)
        whole = read_img_entry(gta3, index[f"{txd}.txd"])
        names = {n[32:64].split(b"\0", 1)[0].decode("latin1").lower() for n in txd_natives(whole)[2]}
        parts.append(trim_txd(whole, dff_strings(dff) & names))
    parts.append(trim_txd(HOUSE_WINDOW_TXD.read_bytes(), GLASS))
    merged = merge_txd(parts)
    SHELL_FILES.mkdir(parents=True, exist_ok=True)
    (SHELL_FILES / f"{NAME}.txd").write_bytes(merged)
    (vanilla / f"{NAME}.txd").write_bytes(merged)
    env = {**os.environ, "GTA_SCOUT": os.environ.get("GTA_SCOUT", "/gta/sa/gta-scout")}
    subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"{NAME}.txd"), str(BUILD / "tex")], check=True, env=env)
    gta_int = gta / "models" / "gta_int.img"
    int_index = read_img_index(gta_int)
    for model, txd in PROPS:
        (vanilla / f"{model}.dff").write_bytes(read_img_entry(gta_int, int_index[f"{model}.dff"]))
        (vanilla / f"prop_{txd}.txd").write_bytes(read_img_entry(gta_int, int_index[f"{txd}.txd"]))
        subprocess.run(["node", str(HERE.parent / "trailer_shells" / "txd_png.mjs"), str(vanilla / f"prop_{txd}.txd"), str(BUILD / "tex")], check=True, env=env, stdout=subprocess.DEVNULL)
    print(f"prep_byoffice: {NAME} in {vanilla}, {NAME}.txd ({len(merged)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
