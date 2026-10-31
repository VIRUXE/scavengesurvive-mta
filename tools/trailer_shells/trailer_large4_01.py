"""trailer_large4_01 (model 3173): single-wide mobile home under a porch awning, screen door onto the porch on +X.

    blender -b --python tools/trailer_shells/trailer_large4_01.py [-- --no-render]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import LINO, Shell, args  # noqa: E402

s = Shell("trailer_large4_01")
X, Y0, Y1, FLOOR, CEIL = 1.6, -5.55, 5.8, 0.45, 2.65
LOUVRE = [("h", 1 / 3), ("h", 2 / 3)]  # trail_win: three stacked panes

door = s.opening("door", "x", 1, -0.69, 0.36, FLOOR, 2.47, X, hinge="right").door
# the cut also takes a sliver of trail_wall4 at the jamb, which common._door would pick as the leaf's texture: the
# vanilla screen door maps trail_door whole
door["texture"], door["uv"] = "trail_door", [[0.0, 0.0], [1.0, 1.0]]
s.opening("window", "x", 1, -4.845, -4.003, 1.358, 2.338, X, frame=LOUVRE, glass_inset=0.0)
s.opening("window", "x", 1, 1.848, 2.597, 1.463, 2.338, X, frame="sash")
s.opening("window", "x", 1, 4.069, 4.842, 1.358, 2.338, X, frame=LOUVRE)
s.opening("window", "x", -1, -3.585, -2.915, 1.358, 2.338, -X, frame="sash", glass_inset=0.0)
s.opening("window", "x", -1, -1.752, -1.018, 1.358, 2.338, -X, frame=LOUVRE, glass_inset=0.0)
s.opening("window", "x", -1, 3.7, 4.966, 1.358, 2.338, -X, frame=LOUVRE)
s.opening("window", "y", -1, -1.119, 0.02, 1.358, 2.338, Y0, frame=LOUVRE)
s.opening("window", "y", 1, -1.231, -0.433, 1.146, 2.479, Y1, frame=LOUVRE, glass_inset=0.0)
s.opening("window", "y", 1, 0.378, 1.195, 1.146, 2.479, Y1, frame=LOUVRE, glass_inset=0.0)
room = s.room(-X, X, Y0, Y1, FLOOR, CEIL, floor=LINO)

# the vanilla body box is solid: replace it with the room's walls, floor and roof, the chassis under the floor and the
# raked +Y end wall past the room
s.cols = [b for b in s.cols if not (b[0] <= -1.7 and b[3] >= 1.7 and b[4] - b[1] > 10)]
s.room_cols(room, wall=0.15, roof=2.91)
s.col_box((-1.75, -5.65, -0.05), (1.75, 5.99, FLOOR - 0.3))
s.col_box((-1.75, Y1 + 0.15, FLOOR), (1.75, 6.25, 2.48))

if "--no-render" not in args():
    s.render("outside_door", (7.5, -3.5, 2.2), (0, 0, 1.4))
    s.render("outside_back", (-6.5, 4.0, 2.0), (0, 0, 1.4))
    s.render("outside_front", (2.5, 10.5, 2.0), (0, 5.5, 1.6))
    s.render("outside_rear", (-2.5, -10.5, 2.0), (0, -5.5, 1.6))
    s.render("inside_front", (0.0, -5.0, 1.65), (0, 5, 1.4), lens=16)
    s.render("inside_back", (0.0, 5.3, 1.65), (0, -5, 1.4), lens=16)
    s.render("door_open", (5.5, 2.5, 1.8), (1.6, -0.2, 1.3), door_open=-100)
    s.render("door_closed", (5.0, 0.6, 2.0), (1.7, -0.2, 1.4), lens=20)
    s.render("door_inside", (-1.2, -0.2, 1.6), (1.6, -0.2, 1.4), lens=16)
s.export()
