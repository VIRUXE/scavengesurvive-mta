"""des_bighus03 (model 3303): the Fort Carson house in grey block and boards, des_bighus01's plan mirrored north to
south and standing 0.9 m higher on its lot, with no garage; a lean-to with a lattice porch stands west of it. It gets
01's three rooms (a living room behind the front door and the west porch door, a kitchen, a bedroom at the east end)
joined by open doorways.

    blender -b --python tools/house_shells/des_bighus03.py [-- --no-render]

Run tools/house_shells/prep.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: the house is the box
x -4.84..10.16, y -7.80..-1.80, walls from z -1.53 to the eaves at 1.52, the floor (door sills, porch) at -0.832.
The doors (des_adobedoor1) are painted 0.1 into the skin, the windows (sw_wind09) on it. Rooms stand 0.2 inside the
skin; partitions are 0.2 thick. The two doors are the same 1.0 x 2.03 m leaf, one model hung in each. Writes
house_shell/files/des_bighus03.dff/.col and des_bighus03_door.dff/.col, build/des_bighus03.json and
build/des_bighus03_doors.json (every leaf's hinge and heading).
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
from bighus import (  # noqa: E402
    BED_FLOOR, BED_WALL, CEILING, DOUBLE, KITCHEN_FLOOR, KITCHEN_WALL, LIVING_FLOOR, LIVING_WALL, TRIM,
    doorway, drop_cols, line_doorways, paint_doors, stretch_walls,
)

common.CURTAINS["des_bighus03"] = "ah_curtains1"
from common import BUILD, args  # noqa: E402

# rooms, 0.2 inside the skin; x splits: living | kitchen | bedroom (01's, the front wall now the north one)
HX0, HX1, HY0, HY1, FLOOR, CEIL = -4.64, 9.96, -7.60, -2.00, -0.832, 1.348
LIV1, KIT0, KIT1, BED0 = 3.10, 3.30, 6.20, 6.40
TOP, LOW, HIGH = 1.195, -0.164, 0.329  # window and door heads; the sills of the windows, and of the two high ones

s = common.Shell("des_bighus03")
drop_cols(s, (-4.84, -7.80, -1.53, 10.16, -1.80, 1.52))  # the house's solid box; porches, steps and fences stay
s.keep_col_mesh()  # lot ground, porch decks, steps and roofs: all outside the rooms

# doors, the front one first: its leaf is the model both hang
s.opening("door", "y", 1, 1.358, 2.359, FLOOR, TOP, HY1, hinge="right", reveal=TRIM)  # front, onto the north porch
s.opening("door", "x", -1, -7.500, -6.500, FLOOR, TOP, HX0, hinge="right", reveal=TRIM)  # west, onto the lean-to porch
paint_doors(s, "des_adobedoor1")

# windows: north (+y, the front), south (-y), east (+x), west (-x)
for u0, u1, z0, frame in ((-2.445, -1.764, LOW, "sash"), (-0.912, 0.552, LOW, DOUBLE), (4.270, 5.022, HIGH, "fixed"), (7.372, 8.171, HIGH, "fixed")):
    s.opening("window", "y", 1, u0, u1, z0, TOP, HY1, frame=frame, reveal=TRIM)
for u0, u1, frame in ((-3.684, -2.024, DOUBLE), (-0.609, 1.152, DOUBLE), (4.270, 5.022, "sash"), (7.372, 8.171, "sash")):
    s.opening("window", "y", -1, u0, u1, LOW, TOP, HY0, frame=frame, reveal=TRIM)
for u0, u1 in ((-6.583, -5.928), (-3.845, -3.165)):
    s.opening("window", "x", 1, u0, u1, LOW, TOP, HX1, frame="sash", reveal=TRIM)
for u0, u1, frame in ((-3.377, -2.697, "sash"), (-6.257, -4.793, DOUBLE)):
    s.opening("window", "x", -1, u0, u1, LOW, TOP, HX0, frame=frame, reveal=TRIM)

DOORWAYS = (("x", -5.18, -4.18, LIV1, KIT0, LIVING_WALL, LIVING_FLOOR), ("x", -7.08, -6.08, KIT1, BED0, BED_WALL, LIVING_FLOOR))
for axis, u0, u1, near, far, _wall, _floor in DOORWAYS:  # living room -> kitchen nearer the front, kitchen -> bedroom nearer the back
    doorway(s, axis, u0, u1, near, far, FLOOR)

before = set(s.bm.faces)
rooms = [
    s.room(HX0, LIV1, HY0, HY1, FLOOR, CEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
    s.room(KIT0, KIT1, HY0, HY1, FLOOR, CEIL, floor=KITCHEN_FLOOR, walls=KITCHEN_WALL, ceiling=CEILING),
    s.room(BED0, HX1, HY0, HY1, FLOOR, CEIL, floor=BED_FLOOR, walls=BED_WALL, ceiling=CEILING),
]
stretch_walls(s, set(s.bm.faces) - before, FLOOR, CEIL)
line_doorways(s, DOORWAYS, FLOOR, CEIL)
for r in rooms:
    s.room_cols(r, wall=0.2, roof=1.52)
# under the house floor down to the ground, so nothing crawls beneath it
s.col_box((-4.84, -7.80, -1.53), (10.16, -1.80, FLOOR - 0.3))

if "--no-render" not in args():
    import bpy

    s.render("v_top", (2.5, -4.8, 40.0), (2.5, -4.7, 0.0), lens=35, size=(900, 900))
    bpy.data.objects["ground"].location.z = -2.05
    for name, eye in (("lamp_living", (-0.8, -4.78, 1.0)), ("lamp_kitchen", (4.75, -4.78, 1.0)), ("lamp_bed", (8.2, -4.78, 1.0))):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy = 120
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
    s.render("outside_front", (-6.0, 7.2, 0.4), (2.0, -2.8, -0.1))
    s.render("outside_west", (-12.0, -10.0, 0.6), (-4.8, -6.0, 0.0))
    s.render("door_open", (1.0, 1.7, 0.6), (1.9, -1.9, 0.1), door_open=100)
    s.render("inside_living", (2.6, -7.2, 0.8), (-4.6, -3.8, 0.0), lens=16)
    s.render("inside_living_front", (-4.2, -7.2, 0.8), (2.0, -2.0, 0.0), lens=16)
    s.render("inside_kitchen", (5.9, -7.3, 0.8), (3.3, -2.3, 0.0), lens=16)
    s.render("inside_bedroom", (6.6, -7.4, 0.8), (9.9, -2.3, 0.0), lens=16)
s.export()
with open(os.path.join(BUILD, "des_bighus03_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
