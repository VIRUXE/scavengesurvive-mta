"""Writes the port's world overlay for the server's collision module (ml_sageom, https://github.com/VIRUXE/sa-geom).

    python -m tools.geom_overlay [--dff]

The module carries the vanilla map; world/server/geom.lua hands it this overlay on start so server-side ground and ray
queries (lib geom.lua) match what players stand on. Two files in resources/[scavengesurvive]/world/geom/:

- port.map: the maps resource's objects and removals and the puzzles' objects, main world only (dimension and interior
  -1 or 0), as MTA <object>/<removeWorldObject> rows: the same selection as tools/spawn_ground.py's overlay().
- overlay.toml: that map plus a [[col]] entry per model of every model pack (samp_models, hat_models, door_models,
  prop_models, box_models) with its id, from the pack's own files/ (no game files needed), and one per vanilla model
  house_shell rebuilds (the houses, trailers, log cabins and des_westrn9_), with the vanilla id, so the server stands
  on the shell's floor as players do. Paths are relative to the manifest, so the module finds them under the server's
  resources folder.

port.map also carries what house_shell does at each house it lists: the vanilla objects it removes and the frozen
stock props it furnishes it with (its swinging doors stay out).

--dff also lists each model's mesh ([[dff]], for placing items by their shape). Only module builds with world format v2
read that key; v1 rejects the whole manifest, so leave it off until the deployed module is v2.

Rerun after maps/data, world/data/puzzles.lua or a model pack changes, commit the result, and restart the server (an
overlay cannot be taken out of a running module; world/server/geom.lua logs geom.overlayStale until then).
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.render_places import MAPS, PUZZLES, REMOVAL, ROW  # noqa: E402
from tools.spawn_ground import MODEL_PACKS, RES, lua_models  # noqa: E402

OUT = RES / "world" / "geom"
MANIFEST_COL = re.compile(r'\[(\d+)\] = \{[^}]*?\bcol = "([^"]+)"')
SHELL = RES / "house_shell"


def shell_cols() -> list[tuple[int, str]]:
    """(vanilla id, COL name in house_shell/files) of every model house_shell replaces (its client/main.lua)."""
    cols = [(3250, "des_westrn9"), (11092, "burgalrystore_sfs")]
    trailers = (SHELL / "trailers.lua").read_text(encoding="utf8")
    cols += [(int(i), n) for i, n in re.findall(r'\[(\d+)\] = \{\s*dff = "([^"]+)"', trailers)]
    cabins = (SHELL / "cabins.lua").read_text(encoding="utf8")
    cols.append((int(re.search(r"model = (\d+)", cabins)[1]), re.search(r'dff = "([^"]+)"', cabins)[1]))
    houses = (SHELL / "houses.lua").read_text(encoding="utf8")
    cols += [(int(i), n) for i, n in re.findall(r'model = (\d+),\s*dff = "([^"]+)"', houses)]
    return cols


def shell_rows() -> list[str]:
    """The removals and props house_shell's hangHouseDoors applies at each placement houses.lua lists."""
    rows = []
    houses = (SHELL / "houses.lua").read_text(encoding="utf8")
    for block in re.split(r"\n    \{\n", houses)[1:]:

        def section(name, block=block):
            m = re.search(rf"\n        {name} = \{{(.*?)\n        \}},", block, re.S)
            return [[float(v) for v in r.split(",")] for r in re.findall(r"\{ ([^{}]+) \}", m[1])] if m else []

        removes, props = section("remove"), section("props")
        for x, y, z, rz in section("placements"):
            c, s = math.cos(math.radians(rz)), math.sin(math.radians(rz))

            def at(px, py, pz, x=x, y=y, z=z, c=c, s=s):
                return x + px * c - py * s, y + px * s + py * c, z + pz

            for m, px, py, pz, rad in removes:
                wx, wy, wz = at(px, py, pz)
                rows.append(f'<removeWorldObject model="{int(m)}" radius="{rad:g}" posX="{wx:.4f}" posY="{wy:.4f}" posZ="{wz:.4f}" interior="0"/>')
            for m, px, py, pz, prz in props:
                wx, wy, wz = at(px, py, pz)
                rows.append(f'<object model="{int(m)}" posX="{wx:.4f}" posY="{wy:.4f}" posZ="{wz:.4f}" rotX="0.0" rotY="0.0" rotZ="{(rz + prz) % 360:g}" interior="0"/>')
    return rows


def port_map() -> tuple[str, int, int]:
    rows, objects, removals = ["<map>"], 0, 0
    for path in sorted(MAPS.glob("*.lua")) + [PUZZLES]:
        text = path.read_text(encoding="utf8")
        for m, x, y, z, rx, ry, rz, world, interior in ROW.findall(text):
            if int(world) in (-1, 0) and int(interior) in (-1, 0):
                rows.append(f'<object model="{m}" posX="{x}" posY="{y}" posZ="{z}" rotX="{rx}" rotY="{ry}" rotZ="{rz}" interior="0"/>')
                objects += 1
        if "removals = {" in text:
            for m, x, y, z, r in REMOVAL.findall(text[text.index("removals = {") :]):
                rows.append(f'<removeWorldObject model="{m}" radius="{r}" posX="{x}" posY="{y}" posZ="{z}" interior="0"/>')
                removals += 1
    rows += shell_rows()
    rows.append("</map>")
    return "\n".join(rows) + "\n", objects, removals


def manifest(dff: bool) -> tuple[str, int]:
    out, models = ["# Generated by tools/geom_overlay.py; do not edit.", '[[map]]\npath = "port.map"'], 0
    for res, name in MODEL_PACKS:
        files = RES / res / "files"
        text = (RES / res / name).read_text(encoding="utf8")
        cols = {int(i): c for i, c in MANIFEST_COL.findall(text)}
        for mid, mesh in sorted(lua_models(RES / res / name).items()):
            col = cols.get(mid, mesh)
            if (files / f"{col}.col").exists():
                out.append(f'[[col]]\npath = "../../{res}/files/{col}.col"\nid = {mid}')
                models += 1
            if dff and (files / f"{mesh}.dff").exists():
                out.append(f'[[dff]]\npath = "../../{res}/files/{mesh}.dff"\nid = {mid}')
    for mid, col in shell_cols():
        assert (SHELL / "files" / f"{col}.col").exists(), col
        out.append(f'[[col]]\npath = "../../house_shell/files/{col}.col"\nid = {mid}')
        models += 1
    return "\n".join(out) + "\n", models


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dff", action="store_true", help="list model meshes too (module world format v2 only)")
    a = ap.parse_args(argv)
    OUT.mkdir(exist_ok=True)
    text, objects, removals = port_map()
    (OUT / "port.map").write_text(text, encoding="utf8", newline="\n")
    toml, models = manifest(a.dff)
    (OUT / "overlay.toml").write_text(toml, encoding="utf8", newline="\n")
    print(f"{OUT}: {objects} objects, {removals} removals, {models} models with collision")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
