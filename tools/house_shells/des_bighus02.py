"""des_bighus02 (model 3304): the Fort Carson house in barn boards, des_bighus01's plan turned a quarter about Z (01's
south front faces east here) with no garage, its front door instead on a deck across the south end. It gets 01's three
rooms (a living room at the south end behind the front door and the east side door, a kitchen, a bedroom at the north
end) joined by open doorways.

    blender -b --python tools/house_shells/des_bighus02.py [-- --no-render]

Run tools/house_shells/prep.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: the house is the box
x 0.62..6.62, y -6.83..8.17, walls from z -2.43 to the eaves at 0.62 (gables to 2.22), the floor (door sills, decks) at
-1.73. The doors (comptdoor2) are painted 0.1 into the skin, the windows (sw_wind09) on it. Rooms stand 0.2 inside the
skin; partitions are 0.2 thick. The two doors are the same 1.0 x 2.03 m leaf, one model hung in each. Writes
house_shell/files/des_bighus02.dff/.col and des_bighus02_door.dff/.col, build/des_bighus02.json and
build/des_bighus02_doors.json (every leaf's hinge and heading).
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

common.CURTAINS["des_bighus02"] = "ah_curtains1"
from common import BUILD, args  # noqa: E402

# rooms, 0.2 inside the skin; y splits, south to north: living | kitchen | bedroom
HX0, HX1, HY0, HY1, FLOOR, CEIL = 0.82, 6.42, -6.63, 7.97, -1.73, 0.45
LIV1, KIT0, KIT1, BED0 = 1.11, 1.31, 4.21, 4.41
TOP, LOW, HIGH = 0.296, -1.062, -0.570  # window and door heads; the sills of the windows, and of the two high ones

s = common.Shell("des_bighus02")
drop_cols(s, (0.62, -6.83, -2.43, 6.62, 8.17, 0.62))  # the house's solid box; decks, steps and rails stay
s.keep_col_mesh()  # lot ground, decks, steps and roof: all outside the rooms

# doors, the front one first: its leaf is the model both hang
s.opening("door", "y", -1, 5.322, 6.322, FLOOR, TOP, HY0, hinge="left", reveal=TRIM)  # front, onto the south deck
s.opening("door", "x", 1, -0.627, 0.374, FLOOR, TOP, HX1, hinge="left", reveal=TRIM)  # east, onto the side steps
paint_doors(s, "comptdoor2")

# windows: east (+x), west (-x), north (+y), south (-y)
for u0, u1, z0, frame in ((-4.430, -3.750, LOW, "sash"), (-2.897, -1.434, LOW, DOUBLE), (2.285, 3.037, HIGH, "fixed"), (5.387, 6.185, HIGH, "fixed")):
    s.opening("window", "x", 1, u0, u1, z0, TOP, HX1, frame=frame, reveal=TRIM)
for u0, u1, frame in ((-5.669, -4.009, DOUBLE), (-2.595, -0.833, DOUBLE), (2.285, 3.037, "sash"), (5.387, 6.185, "sash")):
    s.opening("window", "x", -1, u0, u1, LOW, TOP, HX0, frame=frame, reveal=TRIM)
for u0, u1 in ((1.838, 2.494), (4.577, 5.257)):
    s.opening("window", "y", 1, u0, u1, LOW, TOP, HY1, frame="sash", reveal=TRIM)
for u0, u1, frame in ((1.519, 2.199, "sash"), (3.615, 5.079, DOUBLE)):
    s.opening("window", "y", -1, u0, u1, LOW, TOP, HY0, frame=frame, reveal=TRIM)

DOORWAYS = (("y", 3.24, 4.24, LIV1, KIT0, LIVING_WALL, LIVING_FLOOR), ("y", 1.34, 2.34, KIT1, BED0, BED_WALL, LIVING_FLOOR))
for axis, u0, u1, near, far, _wall, _floor in DOORWAYS:  # living room -> kitchen nearer the east side, kitchen -> bedroom nearer the west
    doorway(s, axis, u0, u1, near, far, FLOOR)

before = set(s.bm.faces)
rooms = [
    s.room(HX0, HX1, HY0, LIV1, FLOOR, CEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
    s.room(HX0, HX1, KIT0, KIT1, FLOOR, CEIL, floor=KITCHEN_FLOOR, walls=KITCHEN_WALL, ceiling=CEILING),
    s.room(HX0, HX1, BED0, HY1, FLOOR, CEIL, floor=BED_FLOOR, walls=BED_WALL, ceiling=CEILING),
]
stretch_walls(s, set(s.bm.faces) - before, FLOOR, CEIL)
line_doorways(s, DOORWAYS, FLOOR, CEIL)
for r in rooms:
    s.room_cols(r, wall=0.2, roof=0.62)
# under the house floor down to the ground, so nothing crawls beneath it
s.col_box((0.62, -6.83, -2.43), (6.62, 8.17, FLOOR - 0.3))

if "--no-render" not in args():
    import bpy

    s.render("v_top", (3.6, 0.7, 40.0), (3.6, 0.8, 0.0), lens=35, size=(900, 900))
    bpy.data.objects["ground"].location.z = -2.95
    for name, eye in (("lamp_living", (3.64, -2.79, 0.1)), ("lamp_kitchen", (3.64, 2.76, 0.1)), ("lamp_bed", (3.64, 6.21, 0.1))):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy = 120
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
    s.render("outside_east", (15.6, -8.0, -0.5), (5.6, 0.0, -1.0))
    s.render("outside_south", (12.0, -18.0, -0.5), (4.0, -7.0, -1.0))
    s.render("door_open", (5.0, -11.5, -0.3), (5.8, -6.9, -0.8), door_open=100)
    s.render("inside_living", (1.24, 0.6, -0.1), (4.6, -6.6, -0.9), lens=16)
    s.render("inside_living_front", (1.24, -6.2, -0.1), (6.4, 0.0, -0.9), lens=16)
    s.render("inside_kitchen", (1.14, 3.9, -0.1), (6.1, 1.3, -0.9), lens=16)
    s.render("inside_bedroom", (1.04, 4.6, -0.1), (6.1, 7.9, -0.9), lens=16)
s.export()
with open(os.path.join(BUILD, "des_bighus02_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
