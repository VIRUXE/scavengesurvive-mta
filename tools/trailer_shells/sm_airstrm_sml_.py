"""sm_airstrm_sml_ (model 3174): small riveted Airstream, painted door on -X, one room with a bay at the back end.

    blender -b --python tools/trailer_shells/sm_airstrm_sml_.py [-- --no-render]

The hull is rounded: straight sides x +-1.22 up to z 2.22, then a slanted roof edge up to the flat top at 3.0, and both
ends chamfered in plan and sloping back above z 2.1. The room is a box that fits inside the straight part (x +-1.03,
y -2.00..2.25, z 0.45..2.45, checked against the skin by raycast below, `fits`) with a narrower bay off its back wall
(x +-0.60 out to y -2.62, ceiling 2.30) so the back end's flat window is not at the end of a 0.7 m tunnel.

Openings, all painted on the vanilla skin:
- door: the arched door painted on -X (sm_airstreamside2), cut as a rectangle under its arch, y -1.45..-0.57 up to
  z 2.35 (the arch above stays painted, a transom over the hole). The body's underside is at z 0.41, the ground at
  -0.03: a metal step (trail_wall1, with collision) halves the 0.48 m climb. The leaf hinges on the painted strap
  hinges' side, the viewer's right from outside (y -1.45), and opens outwards.
- +X: three recessed windows side by side (vanilla ring from the skin at 1.20 to a pane at 1.08..1.10, kept; glass
  just behind the pane), each painted with two glazing bars.
- -X: one window behind the door's end; -Y: one window flat on the back end, in the bay.
The axle crosses under the body in a channel open below (up to z 0.64, y -0.44..0.45, the full width): the room's
floor and side walls are carved out of it and a stepped hump covers it from inside (two 0.15 risers each side, over the wheels' tops at 0.74). The tow
bar's A-frame reaches into the body at the front: a plinth along the front wall covers it.
The vanilla collision is a mesh over the whole body (dropped by Shell, which keeps only boxes): the hull is rebuilt
from boxes around the room.
"""
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import RENDERS, SCALE, TRIM, WALL, Shell, args  # noqa: E402
from mathutils import Vector  # noqa: E402


class AirstreamShell(Shell):
    def _glaze(self, o, frame, inset):
        """Frames and glass on a slanted wall follow the skin: built upright, then sheared along the wall normal so
        they keep `inset` behind the skin at every height (as trailer5_01's TravelShell)."""
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
        """The painted door is mirrored on the skin (u runs along +Y, the viewer's left from outside): mirror the
        leaf's door faces to match, strap hinges on the hinge side."""
        leaf = super().build_leaf()
        if leaf is None:
            return None
        (ua, _va), (ub, _vb) = next(o.door for o in self.openings if o.door)["uv"]
        uv = leaf.data.uv_layers.active.data
        for p in leaf.data.polygons:
            if p.material_index == 0:
                for li in p.loop_indices:
                    uv[li].uv.x = ua + ub - uv[li].uv.x
        return leaf

    def fits(self, room, margin=0.02, steps=6):
        """Points of the room's box (walls, floor, ceiling, sampled on a grid) that lie past the vanilla skin, seen by
        raycast from the room's centre: [] when the room is inside the hull everywhere."""
        x0, x1, y0, y1, z0, z1 = room
        c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        bad = []
        for i in range(steps + 1):
            for j in range(steps + 1):
                a, b = i / steps, j / steps
                for p in ((x0, y0 + a * (y1 - y0), z0 + b * (z1 - z0)), (x1, y0 + a * (y1 - y0), z0 + b * (z1 - z0)), (x0 + a * (x1 - x0), y0, z0 + b * (z1 - z0)), (x0 + a * (x1 - x0), y1, z0 + b * (z1 - z0)), (x0 + a * (x1 - x0), y0 + b * (y1 - y0), z1)):
                    d = Vector(p) - c
                    hit = self.ray(c, d, d.length + margin)
                    if hit is not None:
                        bad.append(tuple(round(v, 2) for v in p))
        return bad


s = AirstreamShell("sm_airstrm_sml_")
s.curtain = "ah_curtains1"  # beige, as the net curtains painted in the vanilla windows
X, Y0, Y1, FLOOR, CEIL = 1.03, -1.80, 1.95, 0.46, 2.42
BAY_X, BAY_Y, BAY_FLOOR, BAY_CEIL = 0.60, -2.62, 0.64, 2.30
THREE = [("v", 1 / 3), ("v", 2 / 3)]  # the painted windows' two glazing bars

# hinged on the strap side, y -1.45: 'left' to Shell._door, whose 'right' (z x -normal) is the viewer's left
door = s.opening("door", "x", -1, -1.45, -0.57, FLOOR, 2.35, -X, hinge="left")
s.opening("window", "x", -1, 0.45, 1.44, 1.67, 2.25, -X, frame=THREE)
for u0, u1 in ((-1.556, -0.424), (-0.424, 0.679), (0.679, 1.804)):
    s.opening("window", "x", 1, u0, u1, 1.636, 2.218, X, frame=THREE, glass_inset=0.03)
s.opening("window", "y", -1, -0.54, 0.58, 1.69, 2.235, BAY_Y, frame=THREE)

before = set(s.bm.faces)
room = s.room(-X, X, Y0, Y1, FLOOR, CEIL, open_sides=("-y",))
bay = s.room(-BAY_X, BAY_X, BAY_Y, Y0, BAY_FLOOR, BAY_CEIL, open_sides=("+y",))
# the main room's back wall around the bay's mouth, facing into the room
wall = s.mat(WALL)
for x0, x1, z0, z1 in ((-X, -BAY_X, FLOOR, CEIL), (BAY_X, X, FLOOR, CEIL), (-BAY_X, BAY_X, BAY_CEIL, CEIL)):
    s.face([(x1, Y0, z0), (x0, Y0, z0), (x0, Y0, z1), (x1, Y0, z1)], wall, scale=SCALE[WALL])
# the bay's floor is a window seat: the underside rises towards the ends, to z 0.58 under the back window
s.face([(BAY_X, Y0, FLOOR), (-BAY_X, Y0, FLOOR), (-BAY_X, Y0, BAY_FLOOR), (BAY_X, Y0, BAY_FLOOR)], s.mat(TRIM), scale=SCALE[TRIM])
# the axle channel under the body is open below up to z 0.64 (y -0.44..0.45, the full width): the floor and side
# walls must not run through it, or they show from outside past the wheels
CHANNEL_Y0, CHANNEL_Y1, CHANNEL_TOP = -0.44, 0.45, 0.64
fresh = [f for f in s.bm.faces if f not in before]
s.carve(fresh, (-X - 0.01, CHANNEL_Y0, FLOOR - 0.01), (X + 0.01, CHANNEL_Y1, CHANNEL_TOP))
# a stepped hump over it, the full width of the room, clear of the wheels' tops (z 0.74)
trim = s.mat(TRIM)
HUMP = ((-0.58, 0.59, 0.61), (-0.47, 0.48, 0.76))  # (y0, y1, top) of the lower and the upper tier
for hy0, hy1, top in HUMP:
    s.box((-X, hy0, FLOOR), (X, hy1, top), trim, skip=("-x", "+x", "-z"))
# plinth along the front wall over the tow bar's A-frame, whose arms reach into the body to y 1.68, z 0.60
PLINTH_Y, PLINTH_Z = 1.62, 0.63
s.box((-X, PLINTH_Y, FLOOR), (X, Y1, PLINTH_Z), trim, skip=("+y", "-z", "-x", "+x"))
# metal step under the door: the floor is 0.48 m over the ground
metal = s.mat("trail_wall1")
STEP = ((-1.56, -1.43, -0.10), (-1.216, -0.59, 0.21))
s.box(STEP[0], STEP[1], metal, light="out", skip=("+x", "-z"))

for r in (room, bay):
    bad = [p for p in s.fits(r) if not (CHANNEL_Y0 <= p[1] <= CHANNEL_Y1 and p[2] < CHANNEL_TOP or p[1] > PLINTH_Y and p[2] < PLINTH_Z)]
    if bad:
        with open(os.path.join(RENDERS, "sm_airstrm_sml_fits.txt"), "w") as f:
            f.write("\n".join(map(str, bad)))
        raise RuntimeError(f"sm_airstrm_sml_: room {r} pokes out of the skin at {len(bad)} points, e.g. {bad[:4]}")

# the vanilla body collision is a mesh, dropped: the hull is rebuilt from boxes around the room and the bay
W = 0.12
s.room_cols(room, wall=W, roof=2.95, open_sides=("-y",))
for x0, x1, z0 in ((-X - W, -BAY_X, FLOOR), (BAY_X, X + W, FLOOR), (-BAY_X, BAY_X, BAY_CEIL)):
    s.col_box((x0, Y0 - W, z0), (x1, Y0, CEIL))  # the main room's back wall around the bay
s.col_box((-BAY_X - W, BAY_Y - W, FLOOR - 0.3), (BAY_X + W, Y0, BAY_FLOOR))  # the bay's floor, the seat
s.col_box((-BAY_X - W, BAY_Y - W, BAY_CEIL), (BAY_X + W, Y0 - W, 2.75))  # its roof
s.col_box((-BAY_X - W, BAY_Y - W, BAY_FLOOR), (BAY_X + W, BAY_Y, BAY_CEIL))  # its back wall
for x0, x1 in ((-BAY_X - W, -BAY_X), (BAY_X, BAY_X + W)):
    s.col_box((x0, BAY_Y, BAY_FLOOR), (x1, Y0 - W, BAY_CEIL))
for x0, x1 in ((-1.0, -BAY_X - W), (BAY_X + W, 1.0)):
    s.col_box((x0, -2.45, 0.15), (x1, Y0 - W, 2.3))  # the back corners, between the bay and the skin
s.col_box((-1.1, Y1 + W, 0.15), (1.1, 2.9, 2.6))  # the front end past the room's wall
s.col_box((-1.0, -2.5, CEIL), (1.0, 2.7, 2.95))  # the roof's middle, past the slab over the room
for hy0, hy1, top in HUMP:
    s.col_box((-X, hy0, FLOOR), (X, hy1, top))
s.col_box((-X, PLINTH_Y, FLOOR), (X, Y1, PLINTH_Z))
s.col_box(STEP[0], STEP[1])

if "--no-render" not in args():
    s.render("outside_door", (-6.0, -2.5, 1.6), (0, -0.6, 1.3), lens=28, size=(800, 500))
    s.render("outside_right", (6.0, 1.0, 1.8), (0, 0.2, 1.5), lens=28, size=(800, 500))
    s.render("outside_back", (2.0, -7.0, 2.0), (0, -2.5, 1.7), lens=28, size=(800, 500))
    s.render("inside_back", (0.0, 1.8, 1.65), (0, -3, 1.3), lens=14, size=(800, 500))
    s.render("inside_front", (0.0, -2.4, 1.65), (0, 3, 1.3), lens=14, size=(800, 500))
    s.render("door_open", (-4.5, -3.2, 1.6), (-1.2, -1.0, 1.2), lens=28, size=(800, 500), door_open=-100)
s.export()
