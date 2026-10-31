"""trailer2_01 (model 3168): wheeled travel trailer, glazed door over the blue step on -X, lounge and back bedroom.

    blender -b --python tools/trailer_shells/trailer2_01.py [-- --no-render]

The body sits low (skin bottom z 0.35, the vanilla step's top 0.39), so the vanilla door, z 0.35..2.60, is already
walkable: the leaf starts at the floor, 0.40, to clear the step as it swings. The axle's wheel arches rise into the
body to z 0.81 behind the door, so the bedroom gets a hump over each. The front and back ends slant: the front window
and the back window lie on them, and their frames and glass follow the slant (TravelShell._glaze).
"""
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import CARPET, EPS, LINO, SCALE, TRIM, Opening, Shell, args  # noqa: E402


class TravelShell(Shell):
    def _glaze(self, o, frame, inset):
        """Frames and glass on a slanted end follow the skin: built upright, then sheared along the wall normal so
        they keep `inset` behind the skin at every height."""
        n = 0 if o.axis == "x" else 1
        bottom = sum(d for (u, z), d in o.outer.items() if z == o.z0) / 2 - o.side * inset
        top = sum(d for (u, z), d in o.outer.items() if z == o.z1) / 2 - o.side * inset
        d0 = (bottom + top) / 2
        before, glass_before = set(self.bm.faces), len(self._glass_faces)
        super()._glaze(o, frame, inset)
        if abs(top - bottom) < 0.01:
            return
        slope = (top - bottom) / (o.z1 - o.z0)

        def shift(z):
            return bottom + slope * (z - o.z0) - d0

        for v in {v for f in self.bm.faces if f not in before for v in f.verts}:
            v.co[n] += shift(v.co.z)
        for q, _uv, _out in self._glass_faces[glass_before:]:
            for p in q:
                p[n] += shift(p.z)


def mirror_pass(o, inner):
    """The far side of a pass opening, so the next room's wall (at `inner`) gets the hole and a collision gap too."""
    m = Opening("pass", o.axis, -o.side, o.u0, o.u1, o.z0, o.z1, inner)
    s.openings.append(m)
    return m


s = TravelShell("trailer2_01")
SKIN, X, Y0, Y1, FLOOR, CEIL = 1.4, 1.22, -4.46, 4.61, 0.40, 2.70
PART0, PART1 = 0.18, 0.30  # partition between the lounge (front, door) and the bedroom (back, over the axle)
JALOUSIE = [("h", 1 / 3), ("h", 2 / 3)]

s.opening("door", "x", -1, -1.05, -0.16, FLOOR, 2.60, -X, hinge="left")
# recessed side windows: vanilla frame ring from the skin to the pane at 1.30, kept; glass just behind the pane
s.opening("window", "x", -1, -4.21, -2.78, 1.35, 2.37, -X, outer=-1.30, frame=JALOUSIE, glass_inset=0.03)
s.opening("window", "x", 1, -4.21, -2.78, 1.35, 2.37, X, outer=1.30, frame=JALOUSIE, glass_inset=0.03)
s.opening("window", "x", 1, -1.17, -0.46, 1.35, 1.95, X, outer=1.30, frame="sash", glass_inset=0.03)
# flat windows painted on the skin over the axle
s.opening("window", "x", -1, 2.15, 3.58, 1.35, 2.37, -X, frame=JALOUSIE)
s.opening("window", "x", 1, 2.15, 3.58, 1.35, 2.37, X, frame=JALOUSIE)
# on the slanted ends: front pane recessed in its own ring, back window flat on the skin
s.opening("window", "y", -1, -1.08, 1.09, 1.33, 2.37, Y0, frame=[("v", 0.5)] + JALOUSIE)
s.opening("window", "y", 1, -0.34, 0.35, 1.35, 1.94, Y1, frame="sash")
arch = s.opening("pass", "y", 1, -0.45, 0.45, FLOOR, 2.40, PART0, outer=PART1)
far_side = mirror_pass(arch, PART1)
# humps over the wheel arches (vanilla arch: |x| 0.79..1.40, y 0.32..2.25, up to z 0.81): the bedroom's side walls
# stop above them, or their backs would show under the arches between the wheels
HUMP = (0.74, 0.30, 2.30, 0.88)
hump_walls = [Opening("hump", "x", side, HUMP[1], HUMP[2], FLOOR, HUMP[3], side * X) for side in (-1, 1)]
s.openings += hump_walls

lounge = s.room(-X, X, Y0, PART0, FLOOR, CEIL, floor=LINO)
bedroom = s.room(-X, X, PART1, Y1, FLOOR, CEIL)
# the bedroom's floor stops at the humps too, or it shows through the arches from outside
carpet = s.mat(CARPET)
bed_floor = [f for f in s.bm.faces if f.material_index == carpet and all(abs(v.co.z - FLOOR) < EPS for v in f.verts) and f.calc_center_median().y > PART1]
bmesh.ops.delete(s.bm, geom=bed_floor, context="FACES")
for fx0, fx1, fy0, fy1 in ((-HUMP[0], HUMP[0], PART1, HUMP[2]), (-X, X, HUMP[2], Y1)):
    s.face([(fx0, fy0, FLOOR), (fx1, fy0, FLOOR), (fx1, fy1, FLOOR), (fx0, fy1, FLOOR)], carpet, scale=SCALE[CARPET])
trim = s.mat(TRIM)
s.box((HUMP[0], HUMP[1], FLOOR), (X, HUMP[2], HUMP[3]), trim, skip=("+x", "-z", "-y"))
s.box((-X, HUMP[1], FLOOR), (-HUMP[0], HUMP[2], HUMP[3]), trim, skip=("-x", "-z", "-y"))
for o in hump_walls:
    s.openings.remove(o)  # not doorways: the bedroom's side collision stays whole

# the vanilla body box is solid: replace it with the rooms' walls, floor and roof
s.cols = [b for b in s.cols if not (b[0] <= -1.39 and b[3] >= 1.39 and b[4] - b[1] > 8)]
s.room_cols(lounge, roof=2.95)
s.room_cols(bedroom, roof=2.95)
s.openings.remove(far_side)  # only there for the bedroom's wall and collision
s.col_box((-SKIN, -4.20, CEIL), (SKIN, 4.40, 3.15))  # roof, full height between the slanted ends
s.col_box((-SKIN, -4.62, 0.0), (SKIN, 4.78, FLOOR))  # underbody down to the ground, wheels inside
s.col_box((-SKIN, -4.82, 0.9), (SKIN, Y0 - 0.12, 2.1))  # the front slant's bulge past the lounge wall
s.col_box((-SKIN, Y1 + 0.12, 0.9), (SKIN, 4.88, 2.0))  # the back slant's bulge past the bedroom wall
s.col_box((HUMP[0], HUMP[1], FLOOR), (X + 0.12, HUMP[2], HUMP[3]))
s.col_box((-X - 0.12, HUMP[1], FLOOR), (-HUMP[0], HUMP[2], HUMP[3]))
for wheel_x0, wheel_x1 in ((0.99, 1.27), (-1.27, -0.99)):
    s.col_box((wheel_x0, 0.44, 0.0), (wheel_x1, 2.12, 0.75))

if "--no-render" not in args():
    lamp2 = bpy.data.objects.new("lamp2", bpy.data.lights.new("lamp2", "POINT"))
    lamp2.data.energy = 120
    lamp2.location = (0.0, 2.5, CEIL - 0.3)
    bpy.context.scene.collection.objects.link(lamp2)
    s.render("door_open_plus", (-5.0, 1.8, 1.8), (-1.4, -0.6, 1.2), door_open=100)
    s.render("door_open_minus", (-5.0, 1.8, 1.8), (-1.4, -0.6, 1.2), door_open=-100)
    s.render("outside_door", (-7.0, 2.5, 2.0), (0, -0.5, 1.4))
    s.render("outside_right", (7.0, -2.5, 2.0), (0, 0, 1.4))
    s.render("outside_front", (3.5, -10.0, 2.5), (0, -4.5, 1.6))
    s.render("outside_back", (-3.0, 10.0, 2.5), (0, 4.5, 1.6))
    s.render("inside_front", (0.0, -0.2, 1.65), (0, -5, 1.4), lens=16)
    s.render("inside_back", (0.0, -3.8, 1.65), (0, 5, 1.4), lens=16)
    s.render("bedroom_back", (0.0, 0.6, 1.65), (0, 5, 1.3), lens=16)
    s.render("bedroom_front", (0.0, 4.3, 1.65), (0, -5, 1.2), lens=16)
    s.render("front_window_out", (0.8, -6.3, 1.9), (0, -4.7, 1.85), lens=28)
    bpy.data.objects.remove(lamp2)
s.export()
