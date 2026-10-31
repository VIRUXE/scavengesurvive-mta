"""cw2_logcabins (model 17067): the row of six identical log cabins by the Flint County road, each one room behind a
front door, a window beside it and one in each gable wall. Every cabin is the same box, only moved (the last two stand
up the slope, the others down it); the script finds each one's offset from its door panel, then builds the openings,
and the empty room of cabin 0 once per offset.

    blender -b --python tools/cabin_shells/cw2_logcabins.py [-- --no-render]

Run tools/cabin_shells/prep.py first. The vanilla skin is single-sided logs (walls x +-3.0, y +-2.0, z up to 2.31, gable
roof); the window and door panels are painted 0.1 into it. The room (empty) starts 0.2 inside the skin, so the log walls get the
thickness of a cabin. Windows and the door are cut through the skin where the painted panels are. Writes
house_shell/files/cw2_logcabins.dff/.col and cw2_logcabins_door.dff/.col, build/cw2_logcabins.json (one door) and
build/cw2_logcabins_cabins.json (each cabin's offset and door hinge).
"""
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
import common  # noqa: E402

LOG, WOOD = "cw2_logwall", "des_ghotwood1"
common.TRIM = WOOD
common.DOOR_GAP = 0.002  # the leaf fills the doorway: no daylight at the jambs, head or sill
common.DOOR_THICK = 0.08  # as deep as the reveal, flush with the room wall
common.SCALE.update({LOG: 1.0, WOOD: 1.4})
common.CURTAINS["cw2_logcabins"] = "ah_curtains1"
from common import BUILD, args  # noqa: E402

X, Y, FLOOR, CEIL = 2.8, 1.8, 0.06, 2.28  # the room, inside the 3.0 x 2.0 skin
# (axis, side, u0, u1, z0, z1, inner, kind, frame) in cabin 0's frame; u runs along the wall
OPENINGS = [
    ("y", -1, -0.48, 0.48, FLOOR, 2.11, -Y, "door", "slider"),
    ("y", -1, -2.08, -1.40, 1.05, 2.11, -Y, "window", "fixed"),
    ("x", 1, -0.80, 0.81, 1.06, 2.11, X, "window", "slider"),
    ("x", -1, -0.62, 0.63, 1.15, 2.11, -X, "window", "slider"),
]
# the loot points of cabin 0, on the empty floor
LOOT = [("west", (-1.8, 1.3, FLOOR + 0.02)), ("middle", (1.2, -0.55, FLOOR + 0.02)), ("east", (1.95, 1.62, FLOOR + 0.02)), ("front", (-2.4, -1.45, FLOOR + 0.02))]


def offsets(s):
    """Each cabin's (dx, dy, dz) from cabin 0, by the door panel (material 4) of each: two triangles apiece."""
    door = s.mat("villagreen128256")
    centres = {}
    for f in s.bm.faces:
        if f.material_index == door:
            c = f.calc_center_median()
            centres.setdefault(round(c.y / 3), []).append(c)
    found = [(sum(c.x for c in v) / len(v) - 0.0, sum(c.y for c in v) / len(v), sum(c.z for c in v) / len(v)) for v in centres.values()]
    base = min(found, key=lambda p: abs(p[0]) + abs(p[1] + 1.9))
    return sorted((round(p[0] - base[0], 3), round(p[1] - base[1], 3), round(p[2] - base[2], 3)) for p in found)


s = common.Shell("cw2_logcabins")
cabins = offsets(s)
print("cabins", cabins)
assert len(cabins) == 6, cabins
s.cols = []  # the vanilla boxes are solid cabins


def shift(axis, u0, u1, z0, z1, inner, dx, dy, dz):
    du, dn = (dy, dx) if axis == "x" else (dx, dy)  # u runs along the wall, inner along its normal
    return u0 + du, u1 + du, z0 + dz, z1 + dz, inner + dn


leaves = []
for dx, dy, dz in cabins:
    for axis, side, u0, u1, z0, z1, inner, kind, frame in OPENINGS:
        a, b, c, d, e = shift(axis, u0, u1, z0, z1, inner, dx, dy, dz)
        o = s.opening(kind, axis, side, a, b, c, d, e, frame=frame, glass_inset=0.04, reveal=WOOD)
        if kind == "door":
            leaves.append((dx, dy, dz, o.door["hinge"]))
    room = s.room(-X + dx, X + dx, -Y + dy, Y + dy, FLOOR + dz, CEIL + dz, floor=WOOD, walls=LOG, ceiling=WOOD)
    s.room_cols(room, wall=0.2, roof=2.5)

if "--no-render" not in args():
    s.openings.sort(key=lambda o: not (o.door and abs(o.door["hinge"][0] - 0.478) < 0.01 and abs(o.door["hinge"][1] + 1.84) < 0.01))  # the renders hang the first door: cabin 0's
    lamp2 = bpy.data.objects.new("lamp2", bpy.data.lights.new("lamp2", "POINT"))
    lamp2.data.energy = 150
    lamp2.location = (0.0, 0.0, CEIL - 0.3)
    bpy.context.scene.collection.objects.link(lamp2)
    s.render("outside_front", (-4.0, -9.0, 2.2), (0.0, -2.0, 1.2))
    s.render("outside_east", (10.0, -3.0, 2.2), (3.0, 0.0, 1.2))
    s.render("outside_west", (-10.0, 3.0, 2.2), (-3.0, 0.0, 1.2))
    s.render("door_open", (-3.5, -4.5, 1.7), (0.0, -2.0, 1.1), door_open=100)
    s.render("inside_door", (-1.0, 1.4, 1.6), (0.5, -2.0, 1.1), lens=16)
    s.render("inside_back", (0.5, -1.5, 1.6), (0.0, 2.0, 1.2), lens=16)
    s.render("inside_east", (-2.4, 0.0, 1.6), (3.0, 0.0, 1.2), lens=16)
    s.render("inside_west", (2.4, 0.0, 1.6), (-3.0, 0.0, 1.2), lens=16)
s.export()
with open(os.path.join(BUILD, "cw2_logcabins_cabins.json"), "w") as f:
    json.dump({"cabins": [{"offset": [dx, dy, dz], "hinge": [round(v, 4) for v in h]} for dx, dy, dz, h in leaves], "loot": [{"name": n, "at": list(p)} for n, p in LOOT]}, f, indent=2)
