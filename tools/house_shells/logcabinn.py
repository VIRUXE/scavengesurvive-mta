"""logcabinn (model 18267): the log cabin in the Whetstone woods on Mount Chiliad (and the two copies upstream's maps
place, in Flint County and on an island off the south coast), rebuilt from nothing on the vanilla footprint: same
floor level, the three doorways and the windows where they were, the roofed east porch, the open deck and its ramp,
the west stoop and stairs, the lean-to at the north end, so the loot points in and around it and the quarry-key
puzzle's props stay where they are. The vanilla model is a paper box one face thick with its lighting baked almost
black, and its log walls are a second model (18230, logcabinnlogs, removed by house_shell).

    blender -b --python tools/house_shells/logcabinn.py [-- --no-render] [-- --prelit] [-- --views=a,b]

Run tools/house_shells/prep_logcabinn.py first: the cabin wears the Shady Cabin's texture dictionary
(house_shell/files/logcabinn01.txd) and is built with its builder (tools/house_shells/logcabinn01.py: the primitives,
the collision, the light bake, the renders). What it builds, in the cabin's own frame (x east, y north, the walls
centred on the origin, floor top at z 0.08; moved 1.13 m north into the model's frame at the end), over ground that
lies 1.5 m under the floor on every side:

* a fieldstone foundation and four walls of round logs, saddle-notched, chinked, eleven courses, the gables boarded;
* framed and glazed windows with shutters; three framed doorways (west to the stoop, east to the porch and to the
  deck), each with a braced plank door that swings (one leaf model, logcabinn_door);
* a roof with a thickness: rafters with tails at the eaves, a ridge beam, tie beams with king posts and struts,
  board sheathing seen from inside, rusted corrugated sheets on top as the vanilla cabin wears;
* a stone chimney on the west wall with a fireplace, hearth and mantel inside; a board partition with a doorway making
  two rooms; a bunk, a table with benches, a shelf;
* the east porch under a tin roof on posts with knee braces, the open deck at its north end, the plank ramp down from
  the deck along the porch, pole railings, the framing, posts and braces underneath; firewood, a bench and a barrel;
* the west stoop under a tin awning with stairs down to the north;
* the lean-to at the north end: tin sheets on rafters and purlins, three posts, a slatted back, a wood stack and a
  chopping block; old sheets leaning on it and on the south wall.

Writes house_shell/files/logcabinn.dff/.col and logcabinn_door.dff/.col and build/logcabinn_doors.json (each leaf's
hinge and heading, and the vanilla log walls to remove).
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logcabinn01 as shady  # noqa: E402
from logcabinn01 import BOARD, DECK, DOOR, FLOOR, GLASS, SOOT, STONE, TIMBER, TIN, COURSE, R, Z, rnd  # noqa: E402
from common import BUILD, OUT, args  # noqa: E402
import common  # noqa: E402

NAME = "logcabinn"
SHIFT = (0.0, 1.13, 0.0)  # the cabin's frame -> the model's (the vanilla walls stand at y -7.34 and 9.55)
F = 0.08  # floor top: the loot points stand on it
GL = -1.5  # the ground round the cabin (the loot points outside lie on it)
GROUND = -2.3  # how deep the foundation and the posts reach
HX, HY = 4.95, 8.2  # centre lines of the long (east, west) and end (north, south) log walls
LONG_Z = [0.17 + COURSE * i for i in range(11)]  # the long walls' courses; top at 3.54
END_Z = [0.01 + COURSE * i for i in range(11)]  # the end walls': half a course off; top at 3.38
PLATE = 3.59  # underside of the roof over the long walls' centre lines
PITCH = 0.45  # rise per metre
ROOF_T = 0.10
EAVE, VERGE = 5.7, HY + 0.65
# openings, on course joints: (u0, u1, z0, z1)
WIN_LONG_Z, WIN_END_Z = (1.29, 2.57), (1.45, 2.73)
DOOR_Z = (F, 2.25)
CH_U = 0.5  # the chimney's centre along the west wall
FIREBOX = (CH_U - 0.6, CH_U + 0.6, F, 1.29)
WEST = [(-6.2, -4.9) + WIN_LONG_Z, FIREBOX, (3.93, 5.03) + DOOR_Z]
EAST = [(-6.2, -4.9) + WIN_LONG_Z, (-1.4, -0.3) + DOOR_Z, (4.1, 5.2) + DOOR_Z]
NORTH = [(-2.9, -1.6) + WIN_END_Z, (1.6, 2.9) + WIN_END_Z]
SOUTH = [(-2.9, -1.6) + WIN_END_Z, (1.6, 2.9) + WIN_END_Z]
PART_Y, PART_DOOR = 2.4, (-0.55, 0.55, F, 2.25)  # the partition and its doorway
# east porch (roofed), the open deck north of it, the ramp down from the deck's south edge
PORCH = (HX + 0.27, 9.1, -8.83, 3.65)  # x0, x1, y0, y1
DECK_OPEN = (HX + 0.27, 11.69, 3.65, 8.81)
RAMP = (9.1, 11.69, 3.65, -2.73)  # x0, x1, y at the deck, y at the ground
STOOP = (-7.49, -HX - 0.27, 3.42, 5.66)  # the west landing
STAIR = (-7.38, -5.78, 5.66, 0.2, 0.3)  # x0, x1, top y, rise, run (going north)
LEANTO = (-4.6, 4.85, HY + 0.16, 14.3, 3.45, 0.31)  # x0, x1, y at the wall, y at the eave, z at the wall, fall per metre


def zu(x):
    """Underside of the main roof at x."""
    return PLATE + (HX - abs(x)) * PITCH


class LogCabin(shady.Cabin):
    GROUND_PLANE = (GL, 0.0)
    # The vanilla definition draws this model from both sides (countryS.ide flag 2097152), and the game copies that
    # onto each placement when it creates it, so clearing the flag later does not reach the cabins already standing:
    # two faces back to back in one plane would both be drawn and flicker. Each two-sided sheet's back stands this far
    # behind its front instead.
    BACK_GAP = 0.015

    def __init__(self):
        super().__init__(NAME)

    # ---- the parts -------------------------------------------------------------------------------------------
    def foundation(self):
        x, y = HX + 0.27, HY + 0.27
        for lo, hi, facing in (
            ((-x, -y, GROUND), (-x, y, -0.03), (-1, 0, 0)), ((x, -y, GROUND), (x, y, -0.03), (1, 0, 0)),
            ((-x, -y, GROUND), (x, -y, -0.03), (0, -1, 0)), ((-x, y, GROUND), (x, y, -0.03), (0, 1, 0)),
        ):
            du = Vector((hi[0] - lo[0], hi[1] - lo[1], 0))
            self.grid(lo, du, (0, 0, hi[2] - lo[2]), max(1, round(du.length / 1.8)), 2, STONE, facing, scale=1.25)
        self.grid((-x, -y, -0.03), (2 * x, 0, 0), (0, 2 * y, 0), 1, 1, STONE, (0, 0, 1), scale=1.25)  # the ledge under the sill logs
        self.cbox((-x, -y, GROUND), (x, y, F), "wood", False)  # foundation and floor in one block

    def floor(self):
        x, y = HX - 0.1, HY - 0.1
        self.grid((-x, -y, F), (2 * x, 0, 0), (0, 2 * y, 0), 8, 14, FLOOR, (0, 0, 1), scale=2.6, vdir=(0, 1, 0))

    def wall_col(self, axis, c, lo, hi, top, holes):
        """A log wall's collision: slabs between its doorways and over them."""
        t, a = 0.2, lo
        for d0, d1, _, z1 in sorted(h for h in holes if h[2:] == DOOR_Z):
            self.cbox(self.wp(axis, c - t, a, F), self.wp(axis, c + t, d0, top))
            self.cbox(self.wp(axis, c - t, d0, z1), self.wp(axis, c + t, d1, top))
            a = d1
        self.cbox(self.wp(axis, c - t, a, F), self.wp(axis, c + t, hi, top))

    def walls(self):
        self.log_wall("x", -HX, HY, LONG_Z, WEST)
        self.log_wall("x", HX, HY, LONG_Z, EAST)
        self.log_wall("y", HY, HX, END_Z, NORTH)
        self.log_wall("y", -HY, HX, END_Z, SOUTH)
        shut = {(-HX, 0): ("open", "askew"), (HX, 0): ("open", "open")}
        for c, holes in ((-HX, WEST), (HX, EAST)):
            for i, h in enumerate(holes):
                if h == FIREBOX:
                    continue
                if h[2:] == DOOR_Z:
                    self.lining("x", c, *h, sill=False)
                    self.casing("x", c, -1, *h, sill=False)
                    self.casing("x", c, 1, *h, sill=False)
                    self.wbox("x", c - 0.2, c + 0.2, h[0], h[1], F - 0.02, F + 0.025, TIMBER, scale=0.6)  # threshold
                else:
                    self.window("x", c, h, shutters=shut[(c, i)])
        self.window("y", HY, NORTH[0], shutters=(None, None))  # under the lean-to
        self.window("y", HY, NORTH[1], shutters=(None, None))
        self.window("y", -HY, SOUTH[0], shutters=("open", None))
        self.window("y", -HY, SOUTH[1], shutters=("askew", "open"))
        # gables: boards outside and inside, from the top log to the roof
        base = END_Z[-1] + R - 0.04
        for s in (1, -1):
            for face in (s * (HY + 0.07), s * (HY - 0.07)):
                n = 10
                xe = HX + 0.2
                for i in range(n):
                    xa, xb = -xe + 2 * xe * i / n, -xe + 2 * xe * (i + 1) / n
                    q = [(xa, face, base), (xb, face, base), (xb, face, zu(xb) + 0.02), (xa, face, zu(xa) + 0.02)]
                    self.poly(q, BOARD, scale=2.2, facing=(0, s if abs(face) > HY else -s, 0))
            self.beam((-HX - 0.2, s * (HY + 0.1), base + 0.05), (HX + 0.2, s * (HY + 0.1), base + 0.05), 0.04, 0.14)  # drip board
            self.ctri([(-HX - 0.2, s * HY, base), (HX + 0.2, s * HY, base), (0, s * HY, zu(0))], "wood", True)
        top = LONG_Z[-1] + R
        self.wall_col("x", -HX, -HY - 0.2, HY + 0.2, top, WEST)
        self.wall_col("x", HX, -HY - 0.2, HY + 0.2, top, EAST)
        self.wall_col("y", HY, -HX, HX, top, ())
        self.wall_col("y", -HY, -HX, HX, top, ())

    def roof(self):
        ridge_t = zu(0) + ROOF_T
        for s in (1, -1):
            run = Vector((s * EAVE, 0, -EAVE * PITCH))
            n = Vector((s * PITCH, 0, 1))
            self.tin_roof((0, -VERGE, ridge_t), (0, 1, 0), 2 * VERGE, run, sheet=0.93)
            self.grid((0, -VERGE, ridge_t - 0.035), (0, 2 * VERGE, 0), run, 9, 4, BOARD, n, scale=2.2, vdir=(0, 1, 0))  # under the sheets' gaps
            self.grid((0, -VERGE, zu(0)), (0, 2 * VERGE, 0), run, 9, 4, BOARD, -n, scale=2.2, vdir=(0, 1, 0))
            ex, ez = s * EAVE, zu(EAVE)
            self.poly([(ex, -VERGE, ez), (ex, VERGE, ez), (ex, VERGE, ez + ROOF_T), (ex, -VERGE, ez + ROOF_T)], TIMBER, uvs=[(0, 0.02), (12, 0.02), (12, 0.1), (0, 0.1)], facing=(s, 0, 0))
            self.beam((ex + s * 0.02, -VERGE, ez - 0.03), (ex + s * 0.02, VERGE, ez - 0.03), 0.035, 0.19)  # fascia
            for y in (-VERGE - 0.02, VERGE + 0.02):  # barge boards
                self.beam((0, y, zu(0)), (ex, y, ez), 0.045, 0.24)
            for i in range(18):  # rafters, their tails out under the eave
                y = -8.5 + 17.0 * i / 17
                self.beam((s * 0.06, y, zu(0.06) - 0.085), (s * (EAVE - 0.06), y, zu(EAVE - 0.06) - 0.085), 0.07, 0.17, caps=(False, True))
            a, b = Vector((0, 0, ridge_t + 0.045)), Vector((s * 0.3, 0, ridge_t + 0.045 - 0.3 * PITCH + 0.012))  # ridge cap
            self.grid(a + Vector((0, -VERGE - 0.03, 0)), (0, 2 * VERGE + 0.06, 0), b - a, 6, 1, TIN, n, scale=1.6, vdir=(0, 1, 0))
            self.ctri([(0, -VERGE, ridge_t), (0, VERGE, ridge_t), (ex, VERGE, ez + ROOF_T), (ex, -VERGE, ez + ROOF_T)], "tin", True)
        self.beam((0, -8.6, zu(0) - 0.2), (0, 8.6, zu(0) - 0.2), 0.12, 0.26)  # ridge beam
        for y in (-5.6, -2.2, PART_Y, 5.4):  # tie beams, king posts and struts
            zt = LONG_Z[-1] - 0.02  # let into the top logs, so the ends stay under the roof
            self.cyl((-HX + 0.08, y, zt), (HX - 0.08, y, zt), 0.125, (0, 1, 0), caps=(False, False))
            self.beam((0, y, zt + 0.1), (0, y, zu(0) - 0.3), 0.14, 0.14, up=(0, 1, 0), caps=(False, False))
            for s in (1, -1):
                self.beam((s * 0.12, y, zt + 0.35), (s * 2.6, y, zu(2.6) - 0.22), 0.09, 0.12, up=(0, 1, 0), caps=(False, False))

    def chimney(self):
        """On the west wall. Written looking at it from inside: u along the wall from the chimney's centre, v the
        distance from the cabin's centre line (HX at the wall, more outside), mapped to the cabin's frame."""

        def m(p):
            return Vector((-p[1], CH_U + p[0], p[2]))

        def mn(n):
            return (-n[1], n[0], n[2])

        def vpoly(q, tex, facing, **kw):
            return self.poly([m(p) for p in q], tex, facing=mn(facing), **kw)

        names = {"+x": "+y", "-x": "-y", "+y": "-x", "-y": "+x", "+z": "+z", "-z": "-z"}

        def vbox(lo, hi, tex, skip=(), **kw):
            a, b = m(lo), m(hi)
            return self.box([min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)], tex, skip=tuple(names[k] for k in skip), **kw)

        def vcbox(lo, hi, *a):
            self.cbox(m(lo), m(hi), *a)

        top = 6.45
        y0, y1 = HX + 0.12, HX + 1.0
        grid = dict(scale=1.25)
        vbox((-0.95, y0, GROUND), (0.95, y1, 3.5), STONE, skip=("-z", "+z"), **grid)
        base = [(-0.95, y0, 3.5), (0.95, y0, 3.5), (0.95, y1, 3.5), (-0.95, y1, 3.5)]  # shoulders in to the stack
        neck = [(-0.48, y0 + 0.08, 4.25), (0.48, y0 + 0.08, 4.25), (0.48, y1 - 0.04, 4.25), (-0.48, y1 - 0.04, 4.25)]
        mid = Vector((0, (y0 + y1) / 2, 3.9))
        for i in range(4):
            j = (i + 1) % 4
            q = [base[i], base[j], neck[j], neck[i]]
            vpoly(q, STONE, sum((Vector(p) for p in q), Vector()) / 4 - mid, scale=1.25)
        vbox(neck[0], (0.48, y1 - 0.04, top), STONE, skip=("-z", "+z"), **grid)
        vbox((-0.56, y0, top), (0.56, y1 + 0.04, top + 0.13), STONE, **grid)  # cap
        vbox((-0.3, y0 + 0.24, top + 0.13), (0.3, y1 - 0.2, top + 0.15), SOOT, skip=("-z",))  # the flue's mouth
        vcbox((-0.95, y0, GROUND), (0.95, y1, 3.5), "stone")
        vcbox((-0.56, y0, 3.5), (0.56, y1, top + 0.13), "stone")
        # inside: the surround round the firebox, the breast above it, hearth and mantel
        f0, f1 = HX - 0.55, HX - 0.12
        a, b = -0.6, 0.6
        za, zb = F + 0.12, FIREBOX[3] - 0.2
        us, zs = [-1.15, a + 0.05, b - 0.05, 1.15], [F, za, zb, 2.45]
        for i in range(3):
            for j in range(3):
                if i == 1 and j == 1:
                    continue
                vpoly([(us[i], f0, zs[j]), (us[i + 1], f0, zs[j]), (us[i + 1], f0, zs[j + 1]), (us[i], f0, zs[j + 1])], STONE, (0, -1, 0), scale=1.25)
        for x, n in ((-1.15, (-1, 0, 0)), (1.15, (1, 0, 0))):
            vpoly([(x, f0, F), (x, f1, F), (x, f1, 2.45), (x, f0, 2.45)], STONE, n, scale=1.25)
        vpoly([(-1.15, f0, 2.45), (1.15, f0, 2.45), (0.7, f0 + 0.1, 2.9), (-0.7, f0 + 0.1, 2.9)], STONE, (0, -1, 0.3), scale=1.25)
        for x, n in ((-1, (-1, 0, 0.3)), (1, (1, 0, 0.3))):
            vpoly([(x * 1.15, f0, 2.45), (x * 1.15, f1, 2.45), (x * 0.7, f1, 2.9), (x * 0.7, f0 + 0.1, 2.9)], STONE, n, scale=1.25)
        fy = f0 + 0.1  # the breast, up to the sheathing as it falls to the wall
        vpoly([(-0.7, fy, 2.9), (0.7, fy, 2.9), (0.7, fy, zu(fy) + 0.02), (-0.7, fy, zu(fy) + 0.02)], STONE, (0, -1, 0), scale=1.25)
        for x, n in ((-0.7, (-1, 0, 0)), (0.7, (1, 0, 0))):
            vpoly([(x, fy, 2.9), (x, f1, 2.9), (x, f1, zu(f1) + 0.02), (x, fy, zu(fy) + 0.02)], STONE, n, scale=1.25)
        back = HX + 0.5
        fb = [(a + 0.05, f0, za), (b - 0.05, f0, za), (b - 0.05, f0, zb), (a + 0.05, f0, zb)]
        bk = [(a + 0.18, back, za), (b - 0.18, back, za), (b - 0.18, back, zb - 0.15), (a + 0.18, back, zb - 0.15)]
        centre = Vector((0, (f0 + back) / 2, (za + zb) / 2))
        for i in range(4):
            j = (i + 1) % 4
            q = [fb[i], fb[j], bk[j], bk[i]]
            vpoly(q, SOOT, centre - sum((Vector(p) for p in q), Vector()) / 4)
        vpoly(bk, SOOT, (0, -1, 0))
        vbox((-1.3, f0 - 0.6, F), (1.3, f0, F + 0.12), STONE, skip=("-z", "+y"), **grid)  # hearth
        self.beam(m((-1.35, f0 - 0.09, 1.56)), m((1.35, f0 - 0.09, 1.56)), 0.2, 0.13)  # mantel
        vcbox((-1.15, f0, F), (a + 0.05, HX, 2.45), "stone", False)
        vcbox((b - 0.05, f0, F), (1.15, HX, 2.45), "stone", False)
        vcbox((a, f0, zb), (b, HX, 2.45), "stone", False)
        vcbox((-0.7, fy, 2.45), (0.7, HX, zu(fy)), "stone", False)
        vcbox((-1.3, f0 - 0.6, F), (1.3, f0, F + 0.12), "stone", False)

    def partition(self):
        x0, x1, top = -HX + 0.17, HX - 0.17, LONG_Z[-1] + R
        (a, b, za, zb) = PART_DOOR
        us, zs = [x0, a, b, x1], [F, zb, top]
        for side in (1, -1):
            y = PART_Y + side * 0.05
            for i in range(3):
                for j in range(2):
                    if i == 1 and j == 0:
                        continue
                    n = max(1, round((us[i + 1] - us[i]) / 1.6))
                    self.grid((us[i], y, zs[j]), (us[i + 1] - us[i], 0, 0), (0, 0, zs[j + 1] - zs[j]), n, 1, BOARD, (0, side, 0), scale=2.2)
        self.lining("y", PART_Y, a, b, za, zb, sill=False, depth=0.07)
        for side in (1, -1):
            d = PART_Y + side * 0.075
            self.beam((a - 0.05, d, F), (a - 0.05, d, zb + 0.1), 0.1, 0.04, up=(0, 1, 0), caps=(False, False))
            self.beam((b + 0.05, d, F), (b + 0.05, d, zb + 0.1), 0.1, 0.04, up=(0, 1, 0), caps=(False, False))
            self.beam((a - 0.1, d, zb + 0.05), (b + 0.1, d, zb + 0.05), 0.04, 0.1)
            self.beam((x0, d, F + 0.06), (a - 0.1, d, F + 0.06), 0.03, 0.12)  # skirting
            self.beam((b + 0.1, d, F + 0.06), (x1, d, F + 0.06), 0.03, 0.12)
        self.cbox((x0, PART_Y - 0.06, F), (a, PART_Y + 0.06, top), "wood", False)
        self.cbox((b, PART_Y - 0.06, F), (x1, PART_Y + 0.06, top), "wood", False)
        self.cbox((a, PART_Y - 0.06, zb), (b, PART_Y + 0.06, top), "wood", False)

    def furniture(self):
        # a bunk against the north wall, between its windows
        x0, x1, y0, y1 = -1.0, 1.05, HY - 0.2 - 1.0, HY - 0.2
        for x in (x0 + 0.04, x1 - 0.04):
            for y in (y0 + 0.04, y1 - 0.04):
                self.beam((x, y, F), (x, y, F + 1.75), 0.08, 0.08, up=(0, 1, 0), caps=(False, True))
        for z in (F + 0.45, F + 1.35):
            self.grid((x0, y0, z), (x1 - x0, 0, 0), (0, y1 - y0, 0), 2, 1, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(0, 1, 0))
            for y in (y0 + 0.02, y1 - 0.02):
                self.beam((x0, y, z - 0.07), (x1, y, z - 0.07), 0.03, 0.16)
            for x in (x0 + 0.02, x1 - 0.02):
                self.beam((x, y0, z - 0.07), (x, y1, z - 0.07), 0.03, 0.16)
        self.cbox((x0, y0, F), (x1, y1, F + 0.47), "wood", False)
        self.cbox((x0, y0, F + 1.25), (x1, y1, F + 1.37), "wood", False)
        # a shelf on brackets along the south room's east wall, between the window and the porch door
        xs = HX - 0.19
        self.grid((xs - 0.3, -4.4, F + 1.55), (0.3, 0, 0), (0, 2.5, 0), 1, 2, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(0, 1, 0))
        self.beam((xs - 0.3, -4.4, F + 1.53), (xs - 0.3, -1.9, F + 1.53), 0.025, 0.05)
        for y in (-4.2, -3.15, -2.1):
            self.beam((xs - 0.02, y, F + 1.2), (xs - 0.27, y, F + 1.52), 0.04, 0.05, up=(0, 1, 0), caps=(False, False))
        # a plank table and two benches in the middle of the south room
        tx0, tx1, ty0, ty1, tz = -1.2, 0.6, -3.85, -3.0, F + 0.76
        self.grid((tx0, ty0, tz), (tx1 - tx0, 0, 0), (0, ty1 - ty0, 0), 2, 1, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(1, 0, 0))
        for y in (ty0 + 0.01, ty1 - 0.01):
            self.beam((tx0, y, tz - 0.05), (tx1, y, tz - 0.05), 0.025, 0.1)
        for x in (tx0 + 0.15, tx1 - 0.15):
            for y in (ty0 + 0.1, ty1 - 0.1):
                self.beam((x, y, F), (x, y, tz - 0.01), 0.07, 0.07, up=(0, 1, 0), caps=(False, False))
            self.beam((x, ty0 + 0.1, F + 0.25), (x, ty1 - 0.1, F + 0.25), 0.03, 0.08)
        self.cbox((tx0, ty0, tz - 0.1), (tx1, ty1, tz), "wood", False)
        for by0 in (ty0 - 0.5, ty1 + 0.22):
            self.grid((tx0 + 0.1, by0, F + 0.45), (tx1 - tx0 - 0.2, 0, 0), (0, 0.28, 0), 2, 1, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(1, 0, 0))
            for x in (tx0 + 0.28, tx1 - 0.28):
                self.box((x - 0.02, by0 + 0.03, F), (x + 0.02, by0 + 0.25, F + 0.45), TIMBER, scale=0.6, skip=("+z", "-z"))
            self.cbox((tx0 + 0.1, by0, F), (tx1 - 0.1, by0 + 0.28, F + 0.46), "wood", False)

    def deck(self, x0, x1, y0, y1):
        nx, ny = max(1, round((x1 - x0) / 1.3)), max(1, round((y1 - y0) / 1.3))
        self.grid((x0, y0, F), (x1 - x0, 0, 0), (0, y1 - y0, 0), nx, ny, DECK, (0, 0, 1), scale=0.74, udir=(1, 0, 0))
        self.grid((x0, y0, F - 0.05), (x1 - x0, 0, 0), (0, y1 - y0, 0), nx, ny, DECK, (0, 0, -1), scale=0.74, udir=(1, 0, 0))
        self.cbox((x0, y0, F - 0.28), (x1, y1, F), "wood", True)

    def post(self, x, y, top, size=0.16):
        self.beam((x, y, GROUND), (x, y, top), size, size, up=(0, 1, 0), caps=(False, False))
        self.cbox((x - size / 2, y - size / 2, GROUND), (x + size / 2, y + size / 2, top))

    def porch(self):
        px0, px1, py0, py1 = PORCH
        dx0, dx1, dy0, dy1 = DECK_OPEN
        top, t = F, 0.05
        self.deck(px0, px1, py0, py1)
        self.deck(dx0, dx1, dy0, dy1)
        outline = [(px0, py0), (px1, py0), (px1, py1), None, (dx1, dy0), (dx1, dy1), (dx0, dy1)]  # rim boards
        for a, b in zip(outline, outline[1:]):
            if a and b:
                self.beam((a[0], a[1], top - 0.135), (b[0], b[1], top - 0.135), 0.04, 0.27)
        # beams along y under the boards, posts under the beams, braces between the posts of the outer rows
        rows = [(px0 + 0.5, py0 + 0.1, dy1 - 0.1), (7.35, py0 + 0.1, dy1 - 0.1), (px1 - 0.12, py0 + 0.1, dy1 - 0.1), (10.35, dy0 + 0.1, dy1 - 0.1), (dx1 - 0.12, dy0 + 0.1, dy1 - 0.1)]
        ys = [py0 + 0.15, -5.38, -2.53, 0.42, dy0 + 0.15, 6.1, dy1 - 0.15]
        for x, y0, y1 in rows:
            self.beam((x, y0, top - t - 0.11), (x, y1, top - t - 0.11), 0.11, 0.22)
            mine = [y for y in ys if y0 - 0.2 <= y <= y1 + 0.2]
            for y in mine:
                self.post(x, y, top - t - 0.22)
            if x in (px1 - 0.12, dx1 - 0.12):
                for k, (ya, yb) in enumerate(zip(mine, mine[1:])):  # a brace per bay, from a post's foot to the next one's head
                    lo, hi = (ya, yb) if k % 2 == 0 else (yb, ya)
                    self.beam((x + 0.1, lo, GL + 0.2), (x + 0.1, hi, -0.35), 0.035, 0.13, caps=(True, True))
        for x0, x1 in ((px0 + 0.5, 7.35), (7.35, px1 - 0.12), (px1 - 0.12, 10.35), (10.35, dx1 - 0.12)):  # under the deck's north end
            lo, hi = (x0, x1) if x0 < 8 else (x1, x0)
            self.beam((lo, dy1 - 0.05, -0.35), (hi, dy1 - 0.05, GL + 0.2), 0.13, 0.035, up=(0, 1, 0))
        # railings: the porch's south end and east edge, the deck's east and north edges
        e = 0.09
        self.pole_rail((px0 + 0.25, py0 + e, top), (px1 - e, py0 + e, top))
        self.pole_rail((px1 - e, py0 + e, top), (px1 - e, py1 - e, top))
        self.pole_rail((dx1 - e, dy0 + e, top), (dx1 - e, dy1 - e, top))
        self.pole_rail((dx1 - e, dy1 - e, top), (dx0 + 0.25, dy1 - e, top))
        # the porch roof: posts, beam, knee braces, ledger on the wall, rafters, purlins, tin sheets
        rx0, rx1, rz0, fall = HX + 0.45, px1 + 0.2, 3.1, 0.14
        ry0, ry1 = py0 + 0.2, py1 - 0.2

        def rz(x):
            return rz0 - (x - rx0) * fall

        bx = px1 - 0.3
        bz = rz(bx) - 0.19 - 0.1
        for y in (py0 + 0.33, -5.38, -2.53, 0.42, py1 - 0.35):
            self.beam((bx, y, top), (bx, y, bz - 0.1), 0.15, 0.15, up=(0, 1, 0), caps=(False, False))
            self.cbox((bx - 0.075, y - 0.075, top), (bx + 0.075, y + 0.075, bz))
            for s in (1, -1):
                if ry0 < y + s * 0.6 < ry1:
                    self.beam((bx, y, bz - 0.7), (bx, y + s * 0.6, bz - 0.1), 0.07, 0.09, caps=(False, False))
        self.beam((bx, ry0, bz), (bx, ry1, bz), 0.15, 0.2)
        self.beam((HX + 0.2, ry0, rz(HX + 0.2) - 0.24), (HX + 0.2, ry1, rz(HX + 0.2) - 0.24), 0.05, 0.2)  # ledger
        n = 11
        for i in range(n):
            y = ry0 + 0.12 + (ry1 - ry0 - 0.24) * i / (n - 1)
            self.beam((HX + 0.17, y, rz(HX + 0.17) - 0.13), (rx1 - 0.06, y, rz(rx1 - 0.06) - 0.13), 0.06, 0.13, caps=(False, True))
        for x in (6.0, 7.3, 8.6):
            self.beam((x, ry0, rz(x) - 0.035), (x, ry1, rz(x) - 0.035), 0.06, 0.05)
        self.tin_roof((rx0, ry0, rz0), (0, 1, 0), ry1 - ry0, (rx1 - rx0, 0, rz(rx1) - rz0), missing=(4,))
        self.ctri([(rx0, ry0, rz0), (rx0, ry1, rz0), (rx1, ry1, rz(rx1)), (rx1, ry0, rz(rx1))], "tin", True)
        # firewood stacked on the porch north of the door, a bench south of it
        fx = HX + 0.24
        for row in range(4):
            y = 0.5 + (0.07 if row % 2 else 0.0)
            while y < 2.9:
                r = rnd.uniform(0.07, 0.1)
                z = top + 0.09 + row * 0.165 + rnd.uniform(-0.01, 0.01)
                x1 = fx + 0.42 + rnd.uniform(-0.05, 0.05)
                self.cyl((fx, y + r, z), (x1, y + r, z), r, (0, 1, 0), sides=8, caps=(False, True))
                y += 2 * r + 0.004
        self.cbox((fx, 0.5, top), (fx + 0.45, 2.95, top + 0.72))
        by0, by1, bxa, bxb = -4.4, -2.7, HX + 0.28, HX + 0.68
        self.grid((bxa, by0, top + 0.45), (bxb - bxa, 0, 0), (0, by1 - by0, 0), 1, 1, DECK, (0, 0, 1), two=DECK, scale=0.74, udir=(0, 1, 0))
        self.beam((bxb, by0, top + 0.425), (bxb, by1, top + 0.425), 0.03, 0.05)
        for y in (by0 + 0.12, by1 - 0.12):
            self.box((bxa + 0.03, y - 0.02, top), (bxb - 0.03, y + 0.02, top + 0.45), TIMBER, scale=0.6, skip=("+z", "-z"))
        self.cbox((bxa, by0, top), (bxb, by1, top + 0.46))
        # a rain barrel in the deck's corner by the wall
        bx, by = HX + 0.75, dy1 - 0.75
        rings = [(0.0, 0.27), (0.45, 0.33), (0.9, 0.27)]
        for (za, ra), (zb, rb) in zip(rings, rings[1:]):
            self.cyl((bx, by, top + za), (bx, by, top + zb), ra, (1, 0, 0), sides=10, mode="pole", caps=(False, False), r1=rb)
        ring = [(bx + 0.25 * math.cos(2 * math.pi * k / 10), by + 0.25 * math.sin(2 * math.pi * k / 10), top + 0.84) for k in range(10)]
        self.poly(ring, SOOT, facing=(0, 0, 1))  # the water
        for z in (0.12, 0.45, 0.78):
            r = 0.335 if z == 0.45 else 0.29
            self.cyl((bx, by, top + z - 0.02), (bx, by, top + z + 0.02), r, (1, 0, 0), sides=10, mode="pole", caps=(False, False))
        self.cbox((bx - 0.3, by - 0.3, top), (bx + 0.3, by + 0.3, top + 0.9))

    def ramp(self):
        x0, x1, ya, yb = RAMP
        za, zb = F, GL + 0.03
        n = Vector((0, -(za - zb), ya - yb))
        self.grid((x0, yb, zb), (x1 - x0, 0, 0), (0, ya - yb, za - zb), 2, 5, DECK, n, two=DECK, scale=0.74, udir=(1, 0, 0))
        slope = Vector((0, ya - yb, za - zb))
        up = Vector((0, -slope.z, slope.y)).normalized()
        k = 1
        while k * 0.45 < slope.length - 0.2:  # cleats across the boards
            p = Vector((0, yb, zb)) + slope.normalized() * (k * 0.45) + up * 0.015
            self.beam((x0 + 0.06, p.y, p.z), (x1 - 0.06, p.y, p.z), 0.05, 0.03, up=up)
            k += 1
        for x in (x0 + 0.08, (x0 + x1) / 2, x1 - 0.08):  # stringers, a pair of posts half way down
            self.beam((x, ya, za - 0.15), (x, yb - 0.1, zb - 0.17), 0.07, 0.22, caps=(False, True))
        ym = (ya + yb) / 2
        for x in (x0 + 0.08, x1 - 0.08):
            self.post(x, ym, (za + zb) / 2 - 0.2, 0.12)
        self.ctri([(x0, yb, zb), (x1, yb, zb), (x1, ya, za), (x0, ya, za)], "wood", True)
        self.pole_rail((x1 - 0.09, ya, za), (x1 - 0.09, yb + 0.1, zb))

    def stoop(self):
        x0, x1, y0, y1 = STOOP
        top, e = F, 0.09
        self.deck(x0, x1, y0, y1)
        for a, b in (((x1, y0), (x0, y0)), ((x0, y0), (x0, y1))):
            self.beam((a[0], a[1], top - 0.135), (b[0], b[1], top - 0.135), 0.04, 0.27)
        for x in (x0 + 0.12, x1 - 0.2):
            self.beam((x, y0, top - 0.16), (x, y1, top - 0.16), 0.11, 0.22)
            for y in (y0 + 0.12, y1 - 0.12):
                self.post(x, y, top - 0.27)
        self.pole_rail((x1 - 0.25, y0 + e, top), (x0 + e, y0 + e, top))
        self.pole_rail((x0 + e, y0 + e, top), (x0 + e, y1 - e, top), posts=False)
        # the awning over the door: two posts, a beam, three rafters, tin
        ax0, ax1, az0, fall = -HX - 0.18, x0 - 0.15, 2.85, 0.14
        ay0, ay1 = y0 - 0.15, y1 + 0.15

        def rz(x):
            return az0 - (ax0 - x) * fall

        bx = x0 + 0.12
        bz = rz(bx) - 0.16
        for y in (y0 + 0.12, y1 - 0.12):
            self.beam((bx, y, top), (bx, y, bz - 0.08), 0.12, 0.12, up=(0, 1, 0), caps=(False, False))
            self.cbox((bx - 0.06, y - 0.06, top), (bx + 0.06, y + 0.06, bz))
        self.beam((bx, ay0, bz), (bx, ay1, bz), 0.12, 0.16)
        for y in (ay0 + 0.1, (ay0 + ay1) / 2, ay1 - 0.1):
            self.beam((-HX - 0.17, y, rz(-HX - 0.17) - 0.07), (ax1 + 0.05, y, rz(ax1 + 0.05) - 0.07), 0.05, 0.1, caps=(False, True))
        self.tin_roof((ax0, ay0, az0), (0, 1, 0), ay1 - ay0, (ax1 - ax0, 0, rz(ax1) - az0), sheet=0.9)
        self.ctri([(ax0, ay0, az0), (ax0, ay1, az0), (ax1, ay1, rz(ax1)), (ax1, ay0, rz(ax1))], "tin", True)

    def stairs(self):
        x0, x1, y0, rise, run = STAIR
        n = next(i for i in range(2, 14) if F - i * rise <= GL + 0.04)  # the last riser lands on the ground
        for i in range(1, n):
            z, y = F - i * rise, y0 + (i - 1) * run
            self.box((x0, y - 0.02, z - 0.045), (x1, y + run + 0.02, z), DECK, scale=0.74, udir=(1, 0, 0))
        length = (n - 1) * run
        bottom = F - n * rise
        for x in (x0 + 0.04, x1 - 0.04):
            self.beam((x, y0 - 0.05, F - 0.2), (x, y0 + length + 0.25, bottom - 0.1), 0.06, 0.3, caps=(False, True))
            for y, z in ((y0 + 0.12, F - rise), (y0 + length - 0.1, bottom + rise)):
                self.cyl((x, y, z - 0.3), (x, y, z + 1.0), 0.055, (1, 0, 0), sides=6, mode="pole", caps=(False, True))
            self.cyl((x, y0 + 0.12, F - rise + 0.95), (x, y0 + length - 0.1, bottom + rise + 0.95), 0.045, (1, 0, 0), sides=6, mode="pole")
            self.cyl((x, y0 + 0.12, F - rise + 0.5), (x, y0 + length - 0.1, bottom + rise + 0.5), 0.035, (1, 0, 0), sides=6, mode="pole", caps=(False, False))
            self.beam((x, y0 + length, GROUND), (x, y0 + length, bottom + 0.1), 0.12, 0.12, up=(0, 1, 0), caps=(False, False))
        self.ctri([(x0, y0, F), (x1, y0, F), (x1, y0 + length + run, bottom), (x0, y0 + length + run, bottom)], "wood", True)
        for x in (x0, x1):
            self.ctri([(x, y0, F - 0.3), (x, y0 + length + run, bottom - 0.3), (x, y0 + length + run, bottom + 0.95), (x, y0, F + 0.95)], "wood", True)

    def leaning_sheet(self, x0, x1, y_foot, y_head, height, tex=TIN):
        """An old corrugated sheet standing on the ground, leaning on a wall."""
        q = [(x0, y_foot, GL - 0.1), (x1, y_foot, GL - 0.1), (x1, y_head, GL + height), (x0, y_head, GL + height)]
        uvs = [(0, 0), ((x1 - x0) / 2.2, 0), ((x1 - x0) / 2.2, height / 2.2), (0, height / 2.2)]
        n = Vector((0, y_foot - y_head, 0.3))
        self.poly(q, tex, uvs=uvs, facing=n)
        back = n.normalized() * self.BACK_GAP
        self.poly([Vector(p) - back for p in q], tex, uvs=uvs, facing=-n)

    def leanto(self):
        x0, x1, yw, ye, zw, fall = LEANTO

        def rz(y):
            return zw - (y - yw) * fall

        by = ye - 0.45
        bz = rz(by) - 0.2 - 0.11
        posts = (x0 + 0.25, (x0 + x1) / 2, x1 - 0.25)
        for x in posts:
            self.post(x, by, bz - 0.11, 0.18)
            for s in (1, -1):
                if x0 < x + s * 0.8 < x1:
                    self.beam((x, by, bz - 0.95), (x + s * 0.8, by, bz - 0.11), 0.08, 0.1, up=(0, 1, 0), caps=(False, False))
        self.beam((x0, by, bz), (x1, by, bz), 0.16, 0.22, up=Z)
        self.beam((x0, HY + 0.22, rz(HY + 0.22) - 0.3), (x1, HY + 0.22, rz(HY + 0.22) - 0.3), 0.06, 0.22)  # ledger
        n = 8
        for i in range(n):
            x = x0 + 0.12 + (x1 - x0 - 0.24) * i / (n - 1)
            self.beam((x, HY + 0.2, rz(HY + 0.2) - 0.16), (x, ye - 0.06, rz(ye - 0.06) - 0.16), 0.07, 0.16, caps=(False, True))
        for y in (9.3, 10.9, 12.5, 14.0):
            self.beam((x0, y, rz(y) - 0.045), (x1, y, rz(y) - 0.045), 0.06, 0.07)
        self.tin_roof((x0, yw, zw), (1, 0, 0), x1 - x0, (0, ye - yw, rz(ye) - zw), missing=(6,), sheet=0.95)
        self.ctri([(x0, yw, zw), (x1, yw, zw), (x1, ye, rz(ye)), (x0, ye, rz(ye))], "tin", True)
        # the slatted back and the east side, a post half way along it
        for h in (0.3, 0.75, 1.2, 1.65, 2.1):
            self.beam((x0 + 0.25, by + 0.1, GL + h + rnd.uniform(-0.03, 0.03)), (x1 - 0.25, by + 0.1, GL + h + rnd.uniform(-0.03, 0.03)), 0.035, 0.15, up=Z)
        self.cbox((x0 + 0.25, by + 0.06, GROUND), (x1 - 0.25, by + 0.16, GL + 2.2))
        xe = x1 - 0.25
        for h in (0.3, 0.75, 1.2):
            self.beam((xe + 0.1, by, GL + h + rnd.uniform(-0.03, 0.03)), (xe + 0.1, HY + 0.45, GL + h + rnd.uniform(-0.03, 0.03)), 0.035, 0.15, up=Z)
        self.cbox((xe + 0.04, HY + 0.45, GROUND), (xe + 0.16, by, GL + 1.3))
        self.post(xe, 11.1, GL + 1.4, 0.14)
        # split wood stacked against the foundation, a chopping block
        for row in range(5):
            x = -3.3 + (0.08 if row % 2 else 0.0)
            while x < 0.9:
                r = rnd.uniform(0.08, 0.115)
                z = GL + 0.1 + row * 0.19 + rnd.uniform(-0.01, 0.01)
                self.cyl((x + r, HY + 0.3, z), (x + r, HY + 0.3 + 0.45 + rnd.uniform(-0.05, 0.05), z), r, (1, 0, 0), sides=8, caps=(False, True))
                x += 2 * r + 0.004
        self.cbox((-3.3, HY + 0.27, GROUND), (0.95, HY + 0.78, GL + 1.0))
        self.cyl((2.7, 11.2, GL - 0.15), (2.7, 11.2, GL + 0.42), 0.27, (1, 0, 0), sides=10, caps=(False, True))
        self.cbox((2.45, 10.95, GROUND), (2.95, 11.45, GL + 0.42))
        # old sheets leaning on the back of the lean-to and on the south wall
        self.leaning_sheet(0.4, 1.35, by + 0.85, by + 0.2, 1.9)
        self.leaning_sheet(1.45, 2.4, by + 0.7, by + 0.2, 1.95, shady.TIN2)
        self.leaning_sheet(0.5, 1.45, -HY - 1.0, -HY - 0.3, 2.0, shady.TIN2)
        self.leaning_sheet(-3.6, -2.65, -HY - 0.85, -HY - 0.3, 1.5)

    def extras(self):
        for s in (1, -1):  # a louvred vent high in each gable
            y = s * (HY + 0.075)
            self.beam((-0.4, y + s * 0.02, 4.75), (0.4, y + s * 0.02, 4.75), 0.05, 0.07)
            self.beam((-0.4, y + s * 0.02, 5.35), (0.4, y + s * 0.02, 5.35), 0.05, 0.07)
            for x in (-0.37, 0.37):
                self.beam((x, y + s * 0.02, 4.75), (x, y + s * 0.02, 5.35), 0.07, 0.05, up=(0, 1, 0), caps=(False, False))
            for i in range(6):
                z = 4.82 + i * 0.09
                self.poly([(-0.34, y + s * 0.005, z), (0.34, y + s * 0.005, z), (0.34, y + s * 0.05, z + 0.07), (-0.34, y + s * 0.05, z + 0.07)], TIMBER, uvs=[(0, 0.42), (0.5, 0.42), (0.5, 0.58), (0, 0.58)], facing=(0, s, 0.6))
            self.poly([(-0.34, y + s * 0.004, 4.78), (0.34, y + s * 0.004, 4.78), (0.34, y + s * 0.004, 5.32), (-0.34, y + s * 0.004, 5.32)], SOOT, facing=(0, s, 0))

    # ---- output ----------------------------------------------------------------------------------------------
    def finish(self):
        for q, uv in self.glass:
            n = (q[1] - q[0]).cross(q[2] - q[1]).normalized() * 0.006  # the pane's two faces, a hair apart
            self.poly([p + n for p in q], GLASS, uvs=uv)
            self.poly([p - n for p in reversed(q)], GLASS, uvs=list(reversed(uv)))
        self.bake()
        glass = self.mat(GLASS)
        for f in self.bm.faces:
            f.smooth = False
            if f.material_index == glass:
                for loop in f.loops:
                    loop[self.day], loop[self.night] = common.GLASS_DAY, common.GLASS_NIGHT
        m = Matrix.Translation(Vector(SHIFT))
        bmesh.ops.transform(self.bm, matrix=m, verts=self.bm.verts)
        bmesh.ops.transform(self.col, matrix=m, verts=self.col.verts)
        self.bm.normal_update()
        self.bm.to_mesh(self.mesh)
        self.col.to_mesh(self.col_mesh)
        self.mesh.update()
        self.colobj = bpy.data.objects.new(NAME + "_colmesh", self.col_mesh)
        bpy.context.scene.collection.objects.link(self.colobj)
        self.colobj.dff.type = "COL"
        self.colobj.hide_render = True
        # the leaf, the same in the three doorways: hinged on the doorway's south jamb, closed along +y
        (u0, u1), (z0, z1) = WEST[2][:2], DOOR_Z
        w, h, t = u1 - u0 - 0.03, z1 - z0 - 0.03, 0.06
        mesh = bpy.data.meshes.new(NAME + "_door")
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day, night = bm.loops.layers.color.new("Col"), bm.loops.layers.color.new("Col.001")
        for tex in (DOOR, TIMBER):
            mesh.materials.append(self.mesh.materials[self.mat(tex)])
        lit = ((0.4, 0.39, 0.37, 1.0), (0.15, 0.15, 0.16, 1.0))

        def quad(vs, mi, uvs):
            f = bm.faces.new([bm.verts.new(v) for v in vs])
            f.material_index = mi
            for loop, c in zip(f.loops, uvs):
                loop[uv].uv = c
                loop[day], loop[night] = lit

        y0, y1 = -t / 2, t / 2
        full = [(0.02, 0.01), (0.98, 0.01), (0.98, 0.99), (0.02, 0.99)]
        quad([(0, y0, 0), (w, y0, 0), (w, y0, h), (0, y0, h)], 0, full)
        quad([(w, y1, 0), (0, y1, 0), (0, y1, h), (w, y1, h)], 0, full)
        e = [(0, 0.02), (1, 0.02), (1, 0.08), (0, 0.08)]
        quad([(0, y1, 0), (0, y0, 0), (0, y0, h), (0, y1, h)], 1, e)
        quad([(w, y0, 0), (w, y1, 0), (w, y1, h), (w, y0, h)], 1, e)
        quad([(0, y0, h), (w, y0, h), (w, y1, h), (0, y1, h)], 1, e)
        quad([(0, y1, 0), (w, y1, 0), (w, y0, 0), (0, y0, 0)], 1, e)
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        self.leaf = bpy.data.objects.new(NAME + "_door", mesh)
        bpy.context.scene.collection.objects.link(self.leaf)
        self.leaf_size = (w, h, t)
        self.doors = []
        for c, hole in ((-HX, WEST[2]), (HX, EAST[1]), (HX, EAST[2])):
            hinge = m @ Vector((c, hole[0] + 0.015, F + 0.015))
            self.doors.append({"hinge": [round(v, 4) for v in hinge], "rz": 90.0})
        self.door = self.doors[0]  # the one the renders hang the leaf in
        self.twins = []
        for d in self.doors[1:]:  # the other two, closed, for the renders only
            twin = bpy.data.objects.new(NAME + "_door_twin", mesh)
            twin.location, twin.rotation_euler = d["hinge"], (0, 0, math.radians(d["rz"]))
            bpy.context.scene.collection.objects.link(twin)
            self.twins.append(twin)

    def export(self):
        for o in [bpy.data.objects.get(n) for n in ("cam", "sun", "ground")] + self.twins:
            if o:
                bpy.data.objects.remove(o)
        os.makedirs(OUT, exist_ok=True)
        one = common.Shell._export_one
        one(None, NAME, self.obj, [], self.colobj)
        self.leaf.location, self.leaf.rotation_euler = (0, 0, 0), (0, 0, 0)
        w, h, t = self.leaf_size
        one(None, NAME + "_door", self.leaf, [[0, -t / 2, 0, w, t / 2, h]])
        with open(os.path.join(BUILD, NAME + "_doors.json"), "w") as f:
            # the vanilla log walls are a model of their own (18230, logcabinnlogs), placed beside this one
            json.dump({"doors": self.doors, "remove": [{"model": 18230, "pos": [5.15, 0.37, 0.36], "radius": 3.0}]}, f, indent=2)
        print(f"export: {NAME} ({len(self.mesh.polygons)} faces, {len(self.mesh.loops)} corners, {len(self.col_mesh.polygons)} collision triangles)")


if __name__ == "__main__":
    c = LogCabin()
    c.foundation()
    c.floor()
    c.walls()
    c.roof()
    c.chimney()
    c.partition()
    c.furniture()
    c.porch()
    c.ramp()
    c.stoop()
    c.stairs()
    c.leanto()
    c.extras()
    c.finish()

    if "--no-render" not in args():
        only = [a.split("=", 1)[1] for a in args() if a.startswith("--views=")]
        only = only[0].split(",") if only else None
        if "--prelit" in args():
            c.prelit_materials()
        views = {  # in the model's frame
            "front_se": ((25.0, -19.0, 4.0), (2.5, 0.5, 1.0), 28, 0),
            "porch_e": ((20.0, 2.5, 1.9), (6.0, -0.5, 1.3), 28, 0),
            "west_sw": ((-21.0, -13.0, 2.6), (-2.0, 2.5, 1.2), 28, 0),
            "leanto_nw": ((-15.0, 25.0, 1.6), (0.0, 10.0, 0.6), 28, 0),
            "door_w": ((-10.0, 2.6, 1.9), (-5.2, 5.8, 1.1), 24, 55),
            "deck": ((11.0, 9.3, 1.8), (6.5, -2.0, 1.0), 20, 0),
            "inside_south": ((3.9, -5.6, 1.75), (-4.6, 1.8, 1.2), 16, 0),
            "inside_north": ((3.9, 4.2, 1.75), (-2.5, 9.3, 1.2), 16, 0),
            "roof_frame": ((-3.6, -5.2, 0.9), (2.0, 2.5, 5.2), 16, 0),
        }
        lamps = []
        for name, eye in (("lamp_south", (0.0, -2.5, 2.6)), ("lamp_north", (0.0, 6.6, 2.6))):
            lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
            lamp.data.energy, lamp.data.color = 260, (1.0, 0.82, 0.6)
            lamp.location = eye
            bpy.context.scene.collection.objects.link(lamp)
            lamps.append(lamp)
        for view, (eye, target, lens, door_open) in views.items():
            if only is None or view in only:
                c.render(view + ("_prelit" if "--prelit" in args() else ""), eye, target, lens=lens, door_open=door_open)
        for lamp in lamps:
            bpy.data.objects.remove(lamp)
    if "--prelit" not in args():
        c.export()
