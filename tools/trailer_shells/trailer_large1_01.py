"""trailer_large1_01 (model 3167): single-wide mobile home with a bump-out annex on +X, screen door on the annex's +Y side.

    blender -b --python tools/trailer_shells/trailer_large1_01.py [-- --no-render]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import LINO, Shell, args  # noqa: E402

s = Shell("trailer_large1_01")
# main body: skin at x -1.754 / 1.746 (the -X windows are recessed to -1.654), ends at y -6.003 / 5.997 (the -Y window
# pane leans in to -5.904); annex: skin x 1.746..4.246 (window pane recessed to 4.146), y -1.154..2.116, eave at 2.468
FLOOR, CEIL, ANNEX_CEIL = 0.45, 2.62, 2.52
MX0, MX1, MY0, MY1 = -1.55, 1.646, -5.80, 5.897
AX0, AX1, AY0, AY1 = 1.846, 4.046, -1.054, 2.016
LOUVRE = [("h", 1 / 3), ("h", 2 / 3)]  # trail_win is a three-pane jalousie

s.opening("door", "y", 1, 2.26, 3.317, FLOOR, 2.468, AY1, hinge="right")
s.opening("window", "x", 1, 0.162, 0.911, 1.159, 1.919, AX1, frame="sash")
s.opening("window", "x", 1, -4.843, -3.439, 1.159, 2.139, MX1, frame=LOUVRE)
s.opening("window", "x", 1, 3.428, 4.822, 1.159, 2.139, MX1, frame=LOUVRE)
s.opening("window", "x", -1, -4.317, -2.913, 1.159, 2.139, MX0, frame=LOUVRE)
s.opening("window", "x", -1, -0.558, 1.572, 1.159, 2.139, MX0, frame=LOUVRE)
s.opening("window", "x", -1, 2.306, 3.7, 1.159, 2.139, MX0, frame=LOUVRE)
s.opening("window", "y", -1, -0.534, 0.525, 1.159, 2.139, MY0, frame=LOUVRE)
s.opening("window", "y", 1, -0.534, 0.525, 1.159, 2.139, MY1, frame=LOUVRE)
s.opening("pass", "x", 1, AY0, AY1, FLOOR, ANNEX_CEIL, MX1, outer=AX0)
main = s.room(MX0, MX1, MY0, MY1, FLOOR, CEIL)
annex = s.room(AX0, AX1, AY0, AY1, FLOOR, ANNEX_CEIL, floor=LINO, open_sides=("-x",))

# the vanilla body and annex boxes are solid: replace them with the rooms' walls, floors and roofs
s.cols = [b for b in s.cols if not (b[2] < 0.1 and b[5] > 2.5)]
s.room_cols(main, wall=0.15, roof=2.8)
s.room_cols(annex, wall=0.15, roof=2.6, open_sides=("-x",))

if "--no-render" not in args():
    s.render("outside_door", (7.0, 7.5, 2.2), (2.0, 0, 1.4))
    s.render("outside_front", (8.0, -6.0, 2.4), (1.0, 0, 1.4))
    s.render("outside_back", (-6.5, 6.0, 2.0), (0, 0, 1.4))
    s.render("outside_left", (-7.0, -5.0, 2.0), (0, 0, 1.4))
    s.render("inside_front", (0.0, 5.4, 1.65), (0, -5, 1.4), lens=16)
    s.render("inside_back", (0.0, -5.3, 1.65), (0, 5, 1.4), lens=16)
    s.render("inside_annex", (-1.2, 0.5, 1.65), (4, 0.5, 1.4), lens=16)
    s.render("inside_door", (2.5, -0.8, 1.65), (2.8, 3, 1.3), lens=16)
    s.render("door_open_pos", (6.0, 5.5, 1.8), (2.8, 2.1, 1.3), door_open=100)
    s.render("door_open_neg", (6.0, 5.5, 1.8), (2.8, 2.1, 1.3), door_open=-100)
    s.render("window_out", (-4.0, 0.5, 1.7), (-1.7, 0.5, 1.6), lens=35)
    s.render("window_in", (0.5, 0.5, 1.65), (-1.6, 0.5, 1.6), lens=24)
s.export()
