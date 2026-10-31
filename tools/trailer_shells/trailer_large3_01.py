"""trailer_large3_01 (model 3170): single-wide mobile home with a bay window on +Y, screen door onto the porch on +X.

    blender -b --python tools/trailer_shells/trailer_large3_01.py [-- --no-render]
"""
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import CEILING, GLASS, LINO, TRIM, Shell, args  # noqa: E402

s = Shell("trailer_large3_01")
# skin at x -1.76 / 1.74 (the jalousie windows are recessed to -1.66 / 1.64), ends at y -5.65 (window pane recessed to
# -5.55) / 5.99, where a three-sided bay (x -1.23..1.19, z 1.22..2.48) stands out to y 6.24; walls end under the eaves
# at 2.47, the roof rises from 2.68 at the sides to 3.02 on the ridge
XN, XP, Y0, Y1, FLOOR, CEIL = -1.64, 1.62, -5.53, 5.89, 0.45, 2.58
SKIN_Y1 = 5.99
LOUVRE = [("h", 1 / 3), ("h", 2 / 3)]  # trail_win is a three-pane jalousie
RECESSED = -0.04  # a negative inset sets the glass back into the vanilla recess, 4 cm in front of its old pane
# the bay's plan, -X to +X along the end wall: its corners on the wall and its two outer corners
BAY = [(-1.23, SKIN_Y1), (-0.435, 6.24), (0.375, 6.24), (1.19, SKIN_Y1)]
BAY_Z0, BAY_Z1 = 1.23, 2.47
BAR, GLASS_BACK = 0.045, 0.02  # frame bar width; the bay's glass sits 2 cm inside its old faces


def obox(p, t, n, a0, a1, b0, b1, z0, z1, material):
    """A box along the bay pane through `p` (direction `t`, outward normal `n`): a0..a1 along it, b0..b1 out of it."""
    corner = {}
    for a in (a0, a1):
        for b in (b0, b1):
            for z in (z0, z1):
                corner[(a, b, z)] = tuple(p + t * a + n * b + Vector((0, 0, z)))
    quads = [
        [(a1, b0, z0), (a1, b1, z0), (a1, b1, z1), (a1, b0, z1)],
        [(a0, b1, z0), (a0, b0, z0), (a0, b0, z1), (a0, b1, z1)],
        [(a1, b1, z0), (a0, b1, z0), (a0, b1, z1), (a1, b1, z1)],
        [(a0, b0, z0), (a1, b0, z0), (a1, b0, z1), (a0, b0, z1)],
        [(a0, b0, z1), (a1, b0, z1), (a1, b1, z1), (a0, b1, z1)],
        [(a0, b1, z0), (a1, b1, z0), (a1, b0, z0), (a0, b0, z0)],
    ]
    for q in quads:
        s.face([corner[k] for k in q], material, light="out")


def glaze_bay(o, frame, inset):
    """Replaces the flat glazing of the bay's opening: a framed jalousie in each of the bay's three faces, a window
    seat on its floor and a ceiling under its eave."""
    alu = s.mat(rgb=(212, 214, 218))
    for (x0, y0), (x1, y1) in zip(BAY, BAY[1:]):
        p = Vector((x0, y0, 0))
        span = Vector((x1 - x0, y1 - y0, 0))
        length = span.length
        t = span / length
        n = Vector((-t.y, t.x, 0))
        b0, b1 = -GLASS_BACK - 0.03, -GLASS_BACK + 0.03
        obox(p, t, n, 0, BAR, b0, b1, BAY_Z0, BAY_Z1, alu)
        obox(p, t, n, length - BAR, length, b0, b1, BAY_Z0, BAY_Z1, alu)
        pz = [BAY_Z0, BAY_Z0 + BAR]
        for f in (1 / 3, 2 / 3):
            c = BAY_Z0 + f * (BAY_Z1 - BAY_Z0)
            pz += [c - BAR / 2, c + BAR / 2]
        pz += [BAY_Z1 - BAR, BAY_Z1]
        for i in range(0, len(pz), 2):
            obox(p, t, n, BAR, length - BAR, b0, b1, pz[i], pz[i + 1], alu)
        for i in range(1, len(pz) - 1, 2):
            za, zb = pz[i], pz[i + 1]
            q = [tuple(p + t * a - n * GLASS_BACK + Vector((0, 0, z))) for a, z in ((BAR, za), (length - BAR, za), (length - BAR, zb), (BAR, zb))]
            v0, v1 = (za - BAY_Z0) / (BAY_Z1 - BAY_Z0), (zb - BAY_Z0) / (BAY_Z1 - BAY_Z0)
            s._glass_faces.append((q, [(0, v0), (1, v0), (1, v1), (0, v1)], True))
    seat = [(x, y, BAY_Z0) for x, y in (BAY[0], BAY[3], BAY[2], BAY[1])]
    s.face(seat, s.mat(TRIM), scale=0.6)
    s.face([(x, y, BAY_Z1) for x, y, _z in reversed(seat)], s.mat(CEILING))


s.opening("door", "x", 1, -0.7, 0.36, FLOOR, 2.47, XP, hinge="left")
s.opening("window", "x", 1, -4.84, -3.45, 1.36, 2.34, XP, outer=1.64, frame=LOUVRE, glass_inset=RECESSED)
s.opening("window", "x", 1, 1.85, 2.6, 1.46, 2.34, XP, frame="sash")
s.opening("window", "x", 1, 3.47, 4.84, 1.36, 2.34, XP, outer=1.64, frame=LOUVRE, glass_inset=RECESSED)
s.opening("window", "x", -1, -3.67, -2.91, 1.36, 2.34, XN, outer=-1.66, frame="sash", glass_inset=RECESSED)
s.opening("window", "x", -1, -2.29, -1.03, 1.36, 2.34, XN, frame=LOUVRE)
s.opening("window", "x", -1, 3.7, 4.97, 1.36, 2.34, XN, outer=-1.66, frame=LOUVRE, glass_inset=RECESSED)
s.opening("window", "y", -1, -1.12, 0.02, 1.36, 2.34, Y0, outer=-5.55, frame=LOUVRE, glass_inset=RECESSED)
flat_glaze = s._glaze
s._glaze = glaze_bay
s.opening("window", "y", 1, BAY[0][0], BAY[3][0], BAY_Z0, BAY_Z1, Y1, outer=SKIN_Y1)
s._glaze = flat_glaze
room = s.room(XN, XP, Y0, Y1, FLOOR, CEIL, floor=LINO)

# the vanilla body box and the eave slab over the whole roof are solid: replace them with the room's walls, floor and
# roof, the chassis under the floor and the eaves past both ends
s.cols = [b for b in s.cols if not (b[0] <= -1.7 and b[3] >= 1.7 and b[4] - b[1] > 10)]
s.room_cols(room, wall=0.12, roof=2.72)
s.col_box((-1.76, -5.65, 0.0), (1.74, 5.99, FLOOR - 0.3))
s.col_box((-1.76, -5.9, 2.47), (1.74, -5.65, 2.68))
s.col_box((-1.76, SKIN_Y1, 2.47), (1.74, 6.46, 2.68))

if "--no-render" not in args():
    s.render("outside_door", (7.5, -3.5, 2.2), (0, 0, 1.4))
    s.render("outside_back", (-6.5, 4.0, 2.0), (0, 0, 1.4))
    s.render("outside_front", (2.5, 10.5, 2.0), (0, 5.5, 1.6))
    s.render("outside_rear", (-2.5, -10.5, 2.0), (0, -5.5, 1.6))
    s.render("inside_front", (0.0, -5.0, 1.65), (0, 5, 1.4), lens=16)
    s.render("inside_back", (0.0, 5.3, 1.65), (0, -5, 1.4), lens=16)
    s.render("bay_out", (1.5, 8.5, 1.9), (0, 6.1, 1.8), lens=35)
    s.render("bay_in", (0.3, 3.5, 1.7), (0, 6.1, 1.8), lens=24)
    s.render("window_out", (4.0, 4.2, 1.8), (1.7, 4.2, 1.8), lens=35)
    s.render("window_in", (-0.5, 4.2, 1.7), (1.7, 4.2, 1.8), lens=24)
    s.render("door_open", (5.5, 2.5, 1.8), (1.6, -0.2, 1.3), door_open=-100)
    s.render("door_open_other", (5.5, 2.5, 1.8), (1.6, -0.2, 1.3), door_open=100)
    s.render("inside_door", (-1.0, -2.0, 1.65), (1.7, -0.2, 1.4), lens=20)
s.export()
