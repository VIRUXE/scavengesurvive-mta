"""des_bighus01 (model 3305): the Fort Carson weatherboard house, a long single-storey house on a 25 m lot with its
garage standing apart behind it. The house gets three rooms (a living room behind the front door and the west porch
door, a kitchen, a bedroom at the east end) joined by open doorways; the garage one room behind its side door. The
garage's roller door stays the vanilla painted one, shut.

    blender -b --python tools/house_shells/des_bighus01.py [-- --no-render]

Run tools/house_shells/prep.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: the house is the box
x -4.84..10.16, y -4.98..1.02, walls from z -1.88 to the eaves at 0.62 (gables to 2.12), the floor (door sills, porch,
steps) at -1.73; the garage is x 0.95..8.95, y 5.30..10.30, on the ground (-2.93) up to its eaves at 0.07. The doors
(comptdoor2) are painted 0.1 into the skin, the windows (sw_wind09) on it. Rooms stand 0.2 inside the skin, so the
walls have a house's thickness; partitions are 0.2 thick. The three doors are the same 1.0 x 2.03 m leaf, one model
hung in each. Writes house_shell/files/des_bighus01.dff/.col and des_bighus01_door.dff/.col, build/des_bighus01.json
and build/des_bighus01_doors.json (every leaf's hinge and heading).
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
from bighus import (  # noqa: E402
    BED_FLOOR, BED_WALL, CEILING, DOUBLE, GARAGE_FLOOR, GARAGE_WALL, KITCHEN_FLOOR, KITCHEN_WALL, LIVING_FLOOR, LIVING_WALL, TRIM,
    doorway, drop_cols, line_doorways, paint_doors, stretch_walls,
)

common.CURTAINS["des_bighus01"] = "ah_curtains1"
from common import BUILD, args  # noqa: E402

# house rooms, 0.2 inside the skin; x splits: living | kitchen | bedroom
HX0, HX1, HY0, HY1, FLOOR, CEIL = -4.64, 9.96, -4.78, 0.82, -1.73, 0.45
LIV1, KIT0, KIT1, BED0 = 3.10, 3.30, 6.20, 6.40
# garage room (its roller door, recessed to x 1.154 between y 5.91 and 9.83, stays shut behind the west wall)
GX0, GX1, GY0, GY1, GFLOOR, GCEIL = 1.35, 8.75, 5.50, 10.10, -2.90, -0.10

s = common.Shell("des_bighus01")
# the house's and the garage's solid boxes go; the porch, steps, fences and flagpole stay
drop_cols(s, (-4.84, -4.98, -2.43, 10.16, 1.02, 0.62), (0.95, 5.30, -2.93, 8.95, 10.30, 0.07))

s.keep_col_mesh()  # lot ground, porch decks, steps and roofs: all outside the rooms

# doors, the front one first: its leaf is the model all three hang
s.opening("door", "y", -1, 1.358, 2.359, FLOOR, 0.296, HY0, hinge="left", reveal=TRIM)  # front, by the steps
s.opening("door", "x", -1, -0.276, 0.725, FLOOR, 0.296, HX0, hinge="left", reveal=TRIM)  # west, onto the lattice porch
s.opening("door", "y", -1, 2.928, 3.955, GFLOOR - 0.01, -0.885, GY0, hinge="left", reveal=TRIM)  # garage side door
paint_doors(s, "comptdoor2")

# house windows: south (-y), north (+y), east (+x), west (-x)
for u0, u1, z0, frame in ((-2.445, -1.764, -1.062, "sash"), (-0.912, 0.552, -1.062, DOUBLE), (4.270, 5.022, -0.570, "fixed"), (7.372, 8.171, -0.570, "fixed")):
    s.opening("window", "y", -1, u0, u1, z0, 0.296, HY0, frame=frame, reveal=TRIM)
for u0, u1, frame in ((-3.684, -2.024, DOUBLE), (-0.609, 1.152, DOUBLE), (4.270, 5.022, "sash"), (7.372, 8.171, "sash")):
    s.opening("window", "y", 1, u0, u1, -1.062, 0.296, HY1, frame=frame, reveal=TRIM)
for u0, u1 in ((-3.611, -2.930), (-0.848, -0.192)):
    s.opening("window", "x", 1, u0, u1, -1.062, 0.296, HX1, frame="sash", reveal=TRIM)
for u0, u1, frame in ((-4.079, -3.398, "sash"), (-1.983, -0.519, DOUBLE)):
    s.opening("window", "x", -1, u0, u1, -1.062, 0.296, HX0, frame=frame, reveal=TRIM)
# garage windows
s.opening("window", "y", -1, 6.168, 6.966, -1.619, -0.753, GY0, frame="sash", reveal=TRIM)
for u0, u1 in ((3.065, 3.818), (6.168, 6.966)):
    s.opening("window", "y", 1, u0, u1, -1.619, -0.753, GY1, frame="sash", reveal=TRIM)
s.opening("window", "x", 1, 6.803, 8.725, -1.403, -0.544, GX1, frame=DOUBLE, reveal=TRIM)


DOORWAYS = (("x", -2.60, -1.60, LIV1, KIT0, LIVING_WALL, LIVING_FLOOR), ("x", -0.70, 0.30, KIT1, BED0, BED_WALL, LIVING_FLOOR))
for axis, u0, u1, near, far, _wall, _floor in DOORWAYS:  # living room -> kitchen nearer the front, kitchen -> bedroom nearer the back
    doorway(s, axis, u0, u1, near, far, FLOOR)


before = set(s.bm.faces)
rooms = [
    s.room(HX0, LIV1, HY0, HY1, FLOOR, CEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
    s.room(KIT0, KIT1, HY0, HY1, FLOOR, CEIL, floor=KITCHEN_FLOOR, walls=KITCHEN_WALL, ceiling=CEILING),
    s.room(BED0, HX1, HY0, HY1, FLOOR, CEIL, floor=BED_FLOOR, walls=BED_WALL, ceiling=CEILING),
    s.room(GX0, GX1, GY0, GY1, GFLOOR, GCEIL, floor=GARAGE_FLOOR, walls=GARAGE_WALL, ceiling=TRIM),
]
stretch_walls(s, set(s.bm.faces) - before, FLOOR, CEIL)
line_doorways(s, DOORWAYS, FLOOR, CEIL)
for r in rooms[:3]:
    s.room_cols(r, wall=0.2, roof=0.62)
s.room_cols(rooms[3], wall=0.2, roof=0.07)
# under the house floor down to the ground, so nothing crawls beneath it
s.col_box((-4.84, -4.98, -2.43), (10.16, 1.02, FLOOR - 0.3))

if "--no-render" not in args():
    import bpy

    s.render("v_top", (2.5, 2.5, 40.0), (2.5, 2.6, 0.0), lens=35, size=(900, 900))
    bpy.data.objects["ground"].location.z = -2.95
    for name, eye, at in (
        ("lamp_living", (-0.8, -2.0, 0.1), None),
        ("lamp_kitchen", (4.75, -2.0, 0.1), None),
        ("lamp_bed", (8.2, -2.0, 0.1), None),
        ("lamp_garage", (5.0, 7.8, -0.4), None),
    ):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy = 120
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
    s.render("outside_front", (-6.0, -14.0, -0.5), (2.0, -4.0, -1.0))
    s.render("door_open", (1.0, -8.5, -0.3), (1.9, -4.9, -0.8), door_open=100)
    s.render("inside_living", (2.6, 0.4, -0.1), (-4.6, -3.0, -0.9), lens=16)
    s.render("inside_living_front", (-4.2, 0.4, -0.1), (2.0, -4.8, -0.9), lens=16)
    s.render("inside_kitchen", (5.9, 0.5, -0.1), (3.3, -4.5, -0.9), lens=16)
    s.render("inside_bedroom", (6.6, 0.6, -0.1), (9.9, -4.5, -0.9), lens=16)
    s.render("inside_garage", (8.4, 9.8, -0.6), (1.4, 5.6, -1.9), lens=16)
s.export()
with open(os.path.join(BUILD, "des_bighus01_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
