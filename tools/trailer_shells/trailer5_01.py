"""trailer5_01 (model 3171): wheeled travel trailer, tall glazed door over the blue step on -X, one long room.

    blender -b --python tools/trailer_shells/trailer5_01.py [-- --no-render]

The body sits low (skin bottom z 0.35, the vanilla step's top 0.39), so the vanilla door, z 0.35..2.60, is already
walkable: the leaf starts at the floor, 0.40, to clear the step as it swings, and keeps the door's 2.2 m. The door is
trail_win2 stretched over its full height with v running down (1 at the sill, 0 at the head): the leaf's UVs are flipped
to match. The axle's wheel wells rise into the body to z 0.81 and are open to the outside, so the room's floor and
side walls are carved out of them (TravelShell.carve) and a hump covers each from inside. Both ends slant (the
front leans back above z 1.2, the back too): the front and back windows lie on them, recessed in their own vanilla
rings, and their frames and glass follow the slant (TravelShell._glaze).
"""
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import LINO, TRIM, Shell, args  # noqa: E402


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

    def carve(self, faces, lo, hi):
        """Deletes the parts of `faces` (new geometry only) inside the box lo..hi, split at its x and y sides first."""
        bm = self.bm
        fresh = set(faces)
        for axis, co in ((0, lo[0]), (0, hi[0]), (1, lo[1]), (1, hi[1]), (2, hi[2])):
            live = [f for f in fresh if f.is_valid]
            geom = list({v for f in live for v in f.verts}) + list({e for f in live for e in f.edges}) + live
            pn, pc = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
            pn[axis], pc[axis] = 1.0, co
            out = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=pc, plane_no=pn, dist=1e-4)
            fresh = {f for f in fresh if f.is_valid} | {f for f in out["geom"] if isinstance(f, bmesh.types.BMFace)}
            fresh |= {f for e in out["geom_cut"] if isinstance(e, bmesh.types.BMEdge) for f in e.link_faces}
        dead = [f for f in fresh if f.is_valid and all(lo[i] - 1e-3 <= f.calc_center_median()[i] <= hi[i] + 1e-3 for i in range(3))]
        bmesh.ops.delete(bm, geom=dead, context="FACES")

    def build_leaf(self):
        """The vanilla door maps trail_win2 upside down (v 1 at the sill): flip the leaf's door faces to match."""
        leaf = super().build_leaf()
        if leaf is None:
            return None
        (_ua, va), (_ub, vb) = next(o.door for o in self.openings if o.door)["uv"]
        mesh = leaf.data
        uv = mesh.uv_layers.active.data
        for p in mesh.polygons:
            if p.material_index == 0:
                for li in p.loop_indices:
                    uv[li].uv.y = va + vb - uv[li].uv.y
        return leaf


s = TravelShell("trailer5_01")
# skin: -X at -1.220, +X at 1.306 (the +X double window's pane recessed to 1.206); the ends slant, tightest between the
# floor and the ceiling at the ceiling: front -3.30, back 2.64; roof underside 2.91 (2.86 / 2.81 at the slanted eaves)
SKIN0, SKIN1, X0, X1, Y0, Y1, FLOOR, CEIL = -1.22, 1.306, -1.12, 1.10, -3.20, 2.54, 0.40, 2.70
SASH2 = [("v", 0.5), ("h", 0.5)]  # two sash windows side by side (the texture repeats twice along the wall)

door = s.opening("door", "x", -1, -1.054, -0.162, FLOOR, 2.603, X0, hinge="left")
# the cut also takes slivers of the skin beside the door: the leaf wears the glazed door's own texture and UV extent
glazed = [(lo, hi) for t, lo, hi in door.removed if t == "trail_win2"]
door.door["texture"] = "trail_win2"
door.door["uv"] = [[min(lo[i] for lo, _hi in glazed) for i in (0, 1)], [max(hi[i] for _lo, hi in glazed) for i in (0, 1)]]
s.opening("window", "x", -1, 0.252, 2.396, 1.355, 2.110, X0, frame=SASH2)
s.opening("window", "x", -1, -2.906, -1.880, 1.355, 2.110, X0, frame="sash")
s.opening("window", "x", 1, -3.022, -1.880, 1.355, 2.110, X1, frame="sash")
# recessed double window: vanilla ring from the skin to the pane at 1.206, kept; glass just behind the pane
s.opening("window", "x", 1, 0.195, 2.183, 1.355, 2.110, X1, outer=1.206, frame=SASH2, glass_inset=0.03)
# on the slanted ends, each pane recessed 0.1 in its own ring
s.opening("window", "y", -1, -0.902, 0.999, 1.328, 2.076, Y0, frame="sash")
s.opening("window", "y", 1, -0.424, 0.661, 1.333, 2.110, Y1, frame="sash")
before = set(s.bm.faces)
room = s.room(X0, X1, Y0, Y1, FLOOR, CEIL, floor=LINO)
# the wheel wells are open to the outside below their ceiling (z 0.809): the room's floor and side walls must not run
# through them, or they show through the opening around each wheel
fresh = [f for f in s.bm.faces if f not in before]
WELL_Y0, WELL_Y1, WELL_TOP = 0.315, 1.328, 0.809
s.carve(fresh, (X0 - 0.01, WELL_Y0, FLOOR - 0.01), (-0.605, WELL_Y1, WELL_TOP))
fresh = [f for f in s.bm.faces if f not in before]
s.carve(fresh, (0.691, WELL_Y0, FLOOR - 0.01), (X1 + 0.01, WELL_Y1, WELL_TOP))
# humps over the wheel arches (vanilla well: x -1.22..-0.605 and 0.691..1.31, y 0.315..1.328, up to z 0.81)
trim = s.mat(TRIM)
HUMP_Y0, HUMP_Y1, HUMP_Z = 0.27, 1.38, 0.88
s.box((0.64, HUMP_Y0, FLOOR), (X1, HUMP_Y1, HUMP_Z), trim, skip=("+x", "-z"))
s.box((X0, HUMP_Y0, FLOOR), (-0.55, HUMP_Y1, HUMP_Z), trim, skip=("-x", "-z"))
# plinth along the front wall over the tow bar's A-frame, whose arms reach into the body to y -3.10, z 0.55
PLINTH_Y, PLINTH_Z = -3.04, 0.62
s.box((X0, Y0, FLOOR), (X1, PLINTH_Y, PLINTH_Z), trim, skip=("-y", "-z", "-x", "+x"))

# the vanilla body box is solid: replace it with the room's walls, floor and roof
s.cols = [b for b in s.cols if not (b[0] <= -1.2 and b[3] >= 1.3 and b[4] - b[1] > 5)]
s.room_cols(room, wall=0.12, roof=2.95)
s.col_box((SKIN0, -3.25, CEIL), (SKIN1, 2.62, 2.95))  # roof, full width between the slanted ends
s.col_box((SKIN0, -3.45, 0.01), (SKIN1, 2.75, FLOOR))  # underbody down to the ground, wheels inside
s.col_box((SKIN0, -3.58, 0.45), (SKIN1, Y0 - 0.12, 2.1))  # the front slant's bulge past the room's wall
s.col_box((SKIN0, Y1 + 0.12, 0.45), (SKIN1, 2.85, 2.0))  # the back slant's bulge past the room's wall
s.col_box((X1 + 0.12, Y0, FLOOR), (SKIN1, Y1, CEIL))  # +X: the room's wall sits 0.2 inside the skin
s.col_box((0.64, HUMP_Y0, FLOOR), (X1, HUMP_Y1, HUMP_Z))
s.col_box((X0, HUMP_Y0, FLOOR), (-0.55, HUMP_Y1, HUMP_Z))
s.col_box((X0, Y0, FLOOR), (X1, PLINTH_Y, PLINTH_Z))

if "--no-render" not in args():
    s.render("outside_door", (-7.0, -0.5, 1.8), (0, -0.5, 1.4))
    s.render("outside_right", (7.0, -0.5, 1.8), (0, -0.5, 1.4))
    s.render("outside_front", (2.5, -9.0, 2.0), (0, -3.5, 1.5))
    s.render("outside_back", (-2.0, 8.0, 2.0), (0, 2.5, 1.5))
    s.render("inside_front", (0.0, 2.2, 1.65), (0, -5, 1.4), lens=16)
    s.render("inside_back", (0.0, -2.9, 1.65), (0, 5, 1.4), lens=16)
    s.render("inside_door", (0.8, 0.5, 1.6), (-1.2, -0.6, 1.4), lens=16)
    s.render("front_window_out", (0.8, -6.0, 1.9), (0, -3.5, 1.75), lens=28)
    s.render("back_window_out", (-0.6, 5.5, 1.9), (0.1, 2.8, 1.75), lens=28)
    s.render("window_in_x", (-0.3, 1.2, 1.65), (1.3, 1.2, 1.7), lens=20)
    s.render("wheel_left", (-3.5, 0.8, 1.2), (-1.0, 0.8, 0.6), lens=28)
    s.render("door_open_plus", (-5.0, 1.8, 1.8), (-1.3, -0.6, 1.2), door_open=100)
    s.render("door_open_minus", (-5.0, 1.8, 1.8), (-1.3, -0.6, 1.2), door_open=-100)
s.export()
