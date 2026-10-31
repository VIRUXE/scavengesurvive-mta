"""GTA's boxes, crates and bags as item spots (tools/world_boxes.py, tools/extract_world_boxes.py).

Every upright placement of a source model, the Rockstar ones (tools/data/world_box_parts.json `natives`) and
upstream's map objects (handed over by maps.py, which then leaves them out), becomes:
- one spot per box in it, { uname, x, y, z, rz, interior }: the box's base in the world and its heading, written to
  world/data/boxes.lua for world/server/boxes.lua to keep an item on;
- for a Rockstar placement, a removal { model, x, y, z, radius } (removeWorldModel's interior defaults to every one);
- where the source has a remnant (its pallets and planks), an object of the remnant model where the source stood.
Removals and remnants go to maps/data/BOXES.lua, built by the maps client like any zone. A tilted placement (a box
pile on its side) is left as it is.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from tools.world_boxes import SOURCES

from .common import lua_value, write_text

PARTS_JSON = Path(__file__).resolve().parents[1] / "data" / "world_box_parts.json"
HEADER = ("-- GENERATED FILE - do not edit; run: python -m tools.convert maps (tools/convert/world_boxes.py)\n"
          "-- GTA's boxes, crates and bags as item spots: { uname, x, y, z, rz, interior }, the box's base and heading.\n")
UPRIGHT = 0.98  # cos of the most a placement may lean and still have its boxes taken out
RADIUS = 0.25
RANGE = 300.0


def source_models() -> set[int]:
    return {s["model"] for s in SOURCES}


def euler_matrix(rx: float, ry: float, rz: float) -> list[list[float]]:
    """An object's rotation matrix from its SA-MP/MTA rotation (GTA's ZXY: R = Rz * Rx * Ry)."""
    x, y, z = (math.radians(v) for v in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return [
        [cz * cy - sz * sx * sy, -sz * cx, cz * sy + sz * sx * cy],
        [sz * cy + cz * sx * sy, cz * cx, sz * sy - cz * sx * cy],
        [-cx * sy, sx, cx * cy],
    ]


def spots_of(boxes: list[dict], pos, rot, interior: int) -> list[list]:
    yaw = math.degrees(math.atan2(rot[1][0], rot[0][0]))
    out = []
    for b in boxes:
        local = (b["x"], b["y"], b["z"])
        world = [pos[i] + sum(rot[i][k] * local[k] for k in range(3)) for i in range(3)]
        out.append([b["uname"], *(round(v, 3) for v in world), round((yaw + b["yaw"]) % 360, 1), interior])
    return out


def convert(upstream: list[list], out_world: Path, out_maps: Path) -> dict:
    """upstream: maps.py's object rows of the source models, [model, x, y, z, rx, ry, rz, world, interior, range]."""
    data = json.loads(PARTS_JSON.read_text())
    sources = {int(k): v for k, v in data["sources"].items()}
    spots, objects, removals, tilted = [], [], [], 0
    for n in data["natives"]:
        model, pos, interior, rot = n[0], n[1:4], n[4], [n[5:8], n[8:11], n[11:14]]
        if rot[2][2] < UPRIGHT:
            tilted += 1
            continue
        src = sources[model]
        spots += spots_of(src["boxes"], pos, rot, interior)
        removals.append([model, *pos, RADIUS])
        if src["remnant"]:
            yaw = round(math.degrees(math.atan2(rot[1][0], rot[0][0])) % 360, 2)
            objects.append([src["remnant"], *pos, 0, 0, yaw, -1, interior, RANGE])
    for o in upstream:
        rot = euler_matrix(o[4], o[5], o[6])
        if rot[2][2] < UPRIGHT:
            tilted += 1
            continue
        src = sources[o[0]]
        interior = max(o[8], 0)
        spots += spots_of(src["boxes"], o[1:4], rot, interior)
        if src["remnant"]:
            objects.append([src["remnant"], *o[1:]])
    spots.sort(key=lambda s: (s[5], s[1], s[2], s[3], s[0]))
    lines = [HEADER, "return {", "    spots = {"] + [f"        {lua_value(s)}," for s in spots] + ["    },", "}", ""]
    write_text(Path(out_world) / "data" / "boxes.lua", "\n".join(lines))
    return {"files": [], "objects": objects, "removals": removals, "materials": [], "spots": len(spots), "tilted": tilted}
