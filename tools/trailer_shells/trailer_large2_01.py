"""trailer_large2_01 (model 3169): single-wide mobile home, screen door onto the porch on +X.

    blender -b --python tools/trailer_shells/trailer_large2_01.py [-- --no-render]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import LINO, Shell, args  # noqa: E402

s = Shell("trailer_large2_01")
X, Y0, Y1, FLOOR, CEIL = 1.6, -5.45, 5.8, 0.45, 2.55

s.opening("door", "x", 1, -0.69, 0.36, FLOOR, 2.47, X, hinge="left")
s.opening("window", "x", 1, 3.47, 4.82, 1.36, 2.34, X)
s.opening("window", "x", 1, 0.8, 1.55, 1.65, 2.41, X, frame="sash")
s.opening("window", "x", 1, -4.84, -4.04, 1.36, 2.34, X, frame="sash")
s.opening("window", "x", -1, 2.51, 3.7, 1.36, 2.34, -X)
s.opening("window", "x", -1, 0.32, 1.57, 1.36, 2.34, -X)
s.opening("window", "x", -1, -3.67, -2.91, 1.36, 2.34, -X, frame="sash")
s.opening("window", "y", 1, -1.23, 1.2, 1.36, 2.34, Y1, frame=[("v", 1 / 3), ("v", 2 / 3)])
s.opening("window", "y", -1, -0.53, 0.02, 1.36, 2.12, Y0, frame="sash")
room = s.room(-X, X, Y0, Y1, FLOOR, CEIL, floor=LINO)

# the vanilla body box is solid: replace it with the room's walls, floor and roof
s.cols = [b for b in s.cols if not (b[0] <= -1.7 and b[3] >= 1.7 and b[4] - b[1] > 10 and b[2] < 0.5)]
s.room_cols(room, wall=0.15, roof=2.68)

if "--no-render" not in args():
    s.render("outside_door", (6.5, -3.0, 2.2), (0, 0, 1.4))
    s.render("outside_back", (-6.0, 4.0, 2.0), (0, 0, 1.4))
    s.render("inside_front", (0.0, -4.8, 1.65), (0, 5, 1.4), lens=16)
    s.render("inside_back", (0.0, 5.0, 1.65), (0, -5, 1.4), lens=16)
    s.render("door_open", (5.0, 1.5, 1.8), (1.6, -0.2, 1.3), door_open=-100)
s.export()
