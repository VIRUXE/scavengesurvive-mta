"""trailer6_01 (model 3172): long tandem-axle travel trailer, two glazed doors over blue steps on -X, lounge and back
bedroom.

    blender -b --python tools/trailer_shells/trailer6_01.py [-- --no-render]

The body sits low (skin bottom z 0.347, the vanilla steps' tops 0.389), so the doors, z 0.347..2.603, are already
walkable: the leaf starts at the floor, 0.40, to clear the step as it swings. Each door is trail_win2 stretched over its
full height with v running down (1 at the sill, 0 at the head): the leaf's UVs are flipped to match. The shell takes one
door, so only the front one (y -1.57..-0.68, into the lounge) opens; the back one (y 3.14..4.03) stays the vanilla
painted door outside, and the bedroom shows the same door on its wall inside. The two axles' wheel wells (|x| past
0.78, y 0.315..2.249, up to z 0.809) are open to the outside, so the lounge's floor and side walls are carved out of
them (TravelShell.carve) and a hump covers each from inside. Both ends slant: the front window (three jalousies under
an awning) is recessed in its own ring on the front slant, the back's small sash window is painted flat on the back
slant; their frames and glass follow the slant (TravelShell._glaze). The underside chamfers up behind y 5.4, so the
bedroom's floor stops there and a plinth (the bed's base) runs over the chamfer to the back wall.
"""
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import EPS, LINO, TRIM, Opening, Shell, args  # noqa: E402


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
        """Deletes the parts of `faces` (new geometry only) inside the box lo..hi, split at its sides first."""
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


def mirror_pass(o, inner):
    """The far side of a pass opening, so the next room's wall (at `inner`) gets the hole and a collision gap too."""
    m = Opening("pass", o.axis, -o.side, o.u0, o.u1, o.z0, o.z1, inner)
    s.openings.append(m)
    return m


s = TravelShell("trailer6_01")
# skin: -X at -1.393 (its jalousie at the front recessed to -1.293), +X at 1.407 (its back jalousie and the small sash
# window recessed to 1.307); roof skin 3.147, no inner face; the front slants from -4.85 at the waist to -4.58 at the
# ceiling, the back from 6.19 to 6.04
SKIN0, SKIN1, X0, X1, Y0, Y1, FLOOR, CEIL = -1.393, 1.407, -1.19, 1.20, -4.50, 5.93, 0.40, 2.80
PART0, PART1 = 2.55, 2.67  # partition between the lounge (front, door, over the axles) and the bedroom (back)
JALOUSIE = [("h", 1 / 3), ("h", 2 / 3)]  # trail_win is a three-pane jalousie
BACK_DOOR = (3.14, 4.032)  # the second vanilla door, kept shut

door = s.opening("door", "x", -1, -1.572, -0.680, FLOOR, 2.603, X0, hinge="left")
# the cut also takes slivers of the skin beside the door: the leaf wears the glazed door's own texture and UV extent
glazed = [(lo, hi) for t, lo, hi in door.removed if t == "trail_win2"]
door.door["texture"] = "trail_win2"
door.door["uv"] = [[min(lo[i] for lo, _hi in glazed) for i in (0, 1)], [max(hi[i] for _lo, hi in glazed) for i in (0, 1)]]
# recessed jalousies: vanilla frame ring from the skin to the pane, kept; glass just behind the pane
s.opening("window", "x", -1, -4.214, -2.786, 1.355, 2.367, X0, outer=-1.293, frame=JALOUSIE, glass_inset=0.03)
s.opening("window", "x", 1, 3.234, 4.663, 1.355, 2.367, X1, outer=1.307, frame=JALOUSIE, glass_inset=0.03)
s.opening("window", "x", 1, -0.572, 0.349, 1.355, 1.876, X1, outer=1.307, frame="sash", glass_inset=0.03)
# flat jalousies painted on the skin
s.opening("window", "x", 1, -3.940, -2.786, 1.355, 2.367, X1, frame=JALOUSIE)
s.opening("window", "x", -1, 1.039, 1.945, 1.355, 2.367, X0, frame=JALOUSIE)
# on the slanted ends: the front's three jalousies recessed in their ring, the back's sash flat on the skin
FRONT_MULLIONS = [("v", (-0.527 + 1.075) / 2.175), ("v", (0.582 + 1.075) / 2.175)]
s.opening("window", "y", -1, -1.075, 1.100, 1.337, 2.349, Y0, frame=FRONT_MULLIONS + JALOUSIE)
s.opening("window", "y", 1, -0.337, 0.351, 1.355, 1.944, Y1, frame="sash")
arch = s.opening("pass", "y", 1, -0.45, 0.45, FLOOR, 2.40, PART0, outer=PART1)
far_side = mirror_pass(arch, PART1)

before = set(s.bm.faces)
lounge = s.room(X0, X1, Y0, PART0, FLOOR, CEIL, floor=LINO)
# the wheel wells are open to the outside below their ceiling (z 0.809): the lounge's floor and side walls must not run
# through them, or they show through the opening around the wheels
WELL_Y0, WELL_Y1, WELL_TOP = 0.315, 2.249, 0.809
fresh = [f for f in s.bm.faces if f not in before]
s.carve(fresh, (X0 - 0.01, WELL_Y0, FLOOR - 0.01), (-0.778, WELL_Y1, WELL_TOP))
fresh = [f for f in s.bm.faces if f not in before]
s.carve(fresh, (0.792, WELL_Y0, FLOOR - 0.01), (X1 + 0.01, WELL_Y1, WELL_TOP))
before = set(s.bm.faces)
bedroom = s.room(X0, X1, PART1, Y1, FLOOR, CEIL)
# the underside chamfers up behind y 5.4 (z 0.38 at 5.5, 0.47 at 5.93): the bedroom's floor and walls stop short of it
CHAMFER_Y, PLINTH_Z = 5.45, 0.62
fresh = [f for f in s.bm.faces if f not in before]
s.carve(fresh, (X0 - 0.01, CHAMFER_Y, FLOOR - 0.01), (X1 + 0.01, Y1 + 0.01, PLINTH_Z))
trim = s.mat(TRIM)
s.box((X0, CHAMFER_Y, FLOOR), (X1, Y1, PLINTH_Z), trim, skip=("-z", "+y", "-x", "+x"))
# humps over the wheel arches (vanilla well: x -1.393..-0.778 and 0.792..1.407, y 0.315..2.249, up to z 0.809)
HUMP_Y0, HUMP_Y1, HUMP_Z = 0.27, 2.30, 0.88
s.box((0.74, HUMP_Y0, FLOOR), (X1, HUMP_Y1, HUMP_Z), trim, skip=("+x", "-z"))
s.box((X0, HUMP_Y0, FLOOR), (-0.72, HUMP_Y1, HUMP_Z), trim, skip=("-x", "-z"))
# the shut back door, seen from the bedroom: a trim casing on the wall and the vanilla door's texture over it (u along
# +y, v 1 at the sill), facing into the room
DOOR_TOP, CASING = 2.603, 0.05
s.box((X0, BACK_DOOR[0] - CASING, FLOOR), (X0 + 0.03, BACK_DOOR[1] + CASING, DOOR_TOP + CASING), trim, skip=("-x", "-z"))
dx, dz = X0 + 0.035, DOOR_TOP - 0.347
corners = [(BACK_DOOR[0], FLOOR), (BACK_DOOR[1], FLOOR), (BACK_DOOR[1], DOOR_TOP), (BACK_DOOR[0], DOOR_TOP)]
uvs = [((y - BACK_DOOR[0]) / (BACK_DOOR[1] - BACK_DOOR[0]), (DOOR_TOP - z) / dz) for y, z in corners]
s.face([(dx, y, z) for y, z in corners], s.mat("trail_win2"), uvs=uvs)

# the vanilla body box is solid: replace it with the rooms' walls, floor and roof
s.cols = [b for b in s.cols if not (b[0] <= -1.39 and b[3] >= 1.40 and b[4] - b[1] > 8)]
s.room_cols(lounge, roof=3.15)
s.room_cols(bedroom, roof=3.15)
s.openings.remove(far_side)  # only there for the bedroom's wall and collision
s.col_box((SKIN0, -4.62, CEIL), (SKIN1, 6.10, 3.15))  # roof, full width between the slanted ends
s.col_box((SKIN0, -4.85, 0.0), (SKIN1, 6.10, FLOOR))  # underbody down to the ground, wheels inside
s.col_box((SKIN0, -4.87, 0.40), (SKIN1, Y0 - 0.12, 2.5))  # the front slant's bulge past the lounge wall
s.col_box((SKIN0, Y1 + 0.12, 0.40), (SKIN1, 6.20, 3.0))  # the back slant's bulge past the bedroom wall
s.col_box((X1 + 0.12, Y0, FLOOR), (SKIN1, Y1, CEIL))  # +X: the rooms' wall sits 0.2 inside the skin
s.col_box((SKIN0, Y0, FLOOR), (X0 - 0.12, -1.572, CEIL))  # -X likewise, either side of the door
s.col_box((SKIN0, -0.680, FLOOR), (X0 - 0.12, Y1, CEIL))
s.col_box((0.74, HUMP_Y0, FLOOR), (X1, HUMP_Y1, HUMP_Z))
s.col_box((X0, HUMP_Y0, FLOOR), (-0.72, HUMP_Y1, HUMP_Z))
s.col_box((X0, CHAMFER_Y, FLOOR), (X1, Y1, PLINTH_Z))

if "--no-render" not in args():
    lamp2 = bpy.data.objects.new("lamp2", bpy.data.lights.new("lamp2", "POINT"))
    lamp2.data.energy = 120
    lamp2.location = (0.0, 4.3, CEIL - 0.3)
    bpy.context.scene.collection.objects.link(lamp2)
    s.render("outside_door", (-9.0, 0.5, 2.0), (0, 0.5, 1.5), size=(800, 450))
    s.render("outside_right", (9.0, -0.5, 2.0), (0, 0.5, 1.5), size=(800, 450))
    s.render("outside_front", (3.5, -11.0, 2.5), (0, -4.5, 1.6), size=(640, 400))
    s.render("outside_back", (-3.0, 12.0, 2.5), (0, 5.5, 1.6), size=(640, 400))
    s.render("inside_front", (0.0, 2.2, 1.65), (0, -5, 1.4), lens=16, size=(800, 500))
    s.render("inside_back", (0.0, -4.2, 1.65), (0, 5, 1.3), lens=16, size=(800, 500))
    s.render("bedroom_back", (0.6, 2.9, 1.65), (0, 6, 1.2), lens=16, size=(800, 500))
    s.render("bedroom_door", (0.9, 4.9, 1.6), (-1.2, 3.3, 1.4), lens=18, size=(640, 400))
    s.render("wheel_left", (-4.0, 1.3, 1.0), (-1.0, 1.3, 0.6), lens=28, size=(640, 400))
    s.render("door_open", (-5.5, 1.5, 1.8), (-1.3, -1.1, 1.3), door_open=-100, size=(640, 400))
    bpy.data.objects.remove(lamp2)
s.export()
