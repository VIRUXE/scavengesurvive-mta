"""sm_airstrm_med_ (model 3175): the medium Airstream, a riveted aluminium travel trailer with rounded ends and roof,
door on -X over the axle's front, tow hitch on +Y.

    blender -b --python tools/trailer_shells/sm_airstrm_med_.py [-- --no-render]

The skin is rounded everywhere: the sides lean in above z 1.3 and curve into the roof from 2.23, both ends taper in
plan (flat only over |x| < 0.7, at y -2.72 and 4.04) and slope back above 2.24. No box fits that, so the inside is a
main room (vertical walls at |x| 1.06 up to 2.30, then a cove up to a flat ceiling at 2.70) with an end section at
each end: a raised platform behind chamfered walls that follow the taper, under a ceiling at 2.30. The vanilla
underbody rises over the ends (to 0.61 at the back, 0.65 at the front, where the tow bar's A-frame also reaches into
the body at 0.60), so the end sections' floors sit higher than the main room's 0.45.

The door is the one painted on the -X side (sm_airstreamside2): its hole runs from the floor to 2.50, where the skin's
curve meets the wall plane (the painted arch above stays), and the cove over it is raised into a dormer so the
doorway keeps its height inside. The floor is 0.33 over the wheels' feet: a metal step (trail_wall1) halves that.
Windows: three painted on each side (two of them on +X recessed in vanilla rings), one recessed in the back end and the
two small panes either side of the front end's air conditioner; the roof's two trail_win3 skylights are raised boxes
on the roof, kept as they are. The wheels rise into the body to z 0.89 beside the main room: a hump covers each.
"""
import os
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import CARPET, CEILING, LINO, SCALE, TRIM, WALL, Shell, args  # noqa: E402


class AirstreamShell(Shell):
    def _glaze(self, o, frame, inset):
        """Frames and glass on the leaning sides follow the skin: built upright, then sheared along the wall normal so
        they keep `inset` behind the skin at every height (as trailer5_01's TravelShell)."""
        n = 0 if o.axis == "x" else 1
        bottom = sum(d for (u, z), d in o.outer.items() if z == o.z0) / 2 - o.side * inset
        top = sum(d for (u, z), d in o.outer.items() if z == o.z1) / 2 - o.side * inset
        d0 = (bottom + top) / 2
        before, glass_before = set(self.bm.faces), len(self._glass_faces)
        super()._glaze(o, frame, inset)
        if abs(top - bottom) < 0.005:
            return
        slope = (top - bottom) / (o.z1 - o.z0)

        def shift(z):
            return bottom + slope * (z - o.z0) - d0

        for v in {v for f in self.bm.faces if f not in before for v in f.verts}:
            v.co[n] += shift(v.co.z)
        for q, _uv, _out in self._glass_faces[glass_before:]:
            for p in q:
                p[n] += shift(p.z)

    def poly(self, pts, material, want, light="in"):
        """A planar polygon wound to face along `want` (the game culls back faces), planar UVs at the material's scale."""
        p = [Vector(v) for v in pts]
        nrm = (p[1] - p[0]).cross(p[2] - p[0])
        if nrm.dot(Vector(want)) < 0:
            p.reverse()
        return self.face(p, material, light=light, scale=SCALE.get(self.texture_of(material), 1.0))

    def half_width(self, y, z):
        """The skin's half-width at (y, z): the nearer of the two sides, by raycast from the centre line."""
        a, b = self.ray((0, y, z), (1, 0, 0)), self.ray((0, y, z), (-1, 0, 0))
        return min(a or 0.0, b or 0.0)


s = AirstreamShell("sm_airstrm_med_")
s.curtain = "ah_blucurtain"
# main room: walls at |x| X from FLOOR to WT, a cove from (X, WT) to (CX, CT), the ceiling at CT; it runs A0..A1
X, FLOOR, WT, CX, CT, A0, A1 = 1.06, 0.45, 2.30, 0.80, 2.70, -1.75, 3.05
# back section: end wall at YR (|x| < RE), floor RF; front section: end wall at YF (|x| < FE), floor FF
YR, RE, RF = -2.56, 0.70, 0.62
YF, FE, FF = 3.95, 0.60, 0.67
PLINTH_Y = 2.74  # the A-frame reaches into the body from here at z 0.60: the front section's platform starts here
DOOR_Y0, DOOR_Y1, DT = 0.52, 1.47, 2.50  # the painted door's width; DT: its head, where the curving skin meets -X
JALOUSIE = [("v", 1 / 3), ("v", 2 / 3)]  # the painted side windows' three lights

door = s.opening("door", "x", -1, DOOR_Y0, DOOR_Y1, FLOOR, DT, -X, hinge="right")
# the skin curves in over the doorway (x -1.215 at the sill, -1.073 at the head): the leaf hangs where it clears the
# head, recessed at the foot
door.door["hinge"][0] = -1.05
# sides: painted windows flush on the skin, and on +X two recessed in vanilla rings (the pane, ~1.09, is the outer face)
s.opening("window", "x", 1, -1.55, -0.47, 1.68, 2.21, X, frame=JALOUSIE)
s.opening("window", "x", 1, 0.40, 1.52, 1.64, 2.22, X, frame=JALOUSIE, glass_inset=0.02)
s.opening("window", "x", 1, 1.76, 2.875, 1.63, 2.22, X, frame=JALOUSIE, glass_inset=0.02)
s.opening("window", "x", -1, -1.49, -0.34, 1.68, 2.22, -X, frame=JALOUSIE)
s.opening("window", "x", -1, 1.62, 2.77, 1.68, 2.22, -X, frame=JALOUSIE)
# back end: the pane recessed 0.1 in its own ring (y -2.617); front end: the two panes beside the air conditioner
s.opening("window", "y", -1, -0.57, 0.61, 1.675, 2.235, YR, frame=JALOUSIE, glass_inset=0.02)
s.opening("window", "y", 1, 0.33, 0.56, 1.62, 2.12, YF, frame="sash")
s.opening("window", "y", 1, -0.55, -0.32, 1.62, 2.12, YF, frame="sash")

before_rooms = set(s.bm.faces)
wall, ceiling, trim, carpet = s.mat(WALL), s.mat(CEILING), s.mat(TRIM), s.mat(CARPET)
main = s.room(-X, X, A0, A1, FLOOR, WT, floor=LINO, open_sides=("-y", "+y"))
# the main room's ceiling is the cove's: drop the flat one room() put at WT
flat = [f for f in s.bm.faces if f not in before_rooms and f.material_index == ceiling]
bmesh.ops.delete(s.bm, geom=flat, context="FACES")
s.poly([(-CX, A0, CT), (CX, A0, CT), (CX, A1, CT), (-CX, A1, CT)], ceiling, (0, 0, -1))
s.poly([(X, A0, WT), (X, A1, WT), (CX, A1, CT), (CX, A0, CT)], ceiling, (-1, 0, -1))
# -X: the cove rises into a dormer over the doorway, from the door's head
for y0, y1, z in ((A0, DOOR_Y0, WT), (DOOR_Y0, DOOR_Y1, DT), (DOOR_Y1, A1, WT)):
    s.poly([(-X, y0, z), (-X, y1, z), (-CX, y1, CT), (-CX, y0, CT)], ceiling, (1, 0, -1))
for y, sign in ((DOOR_Y0, 1), (DOOR_Y1, -1)):
    s.poly([(-X, y, WT), (-X, y, DT), (-CX, y, CT)], ceiling, (0, sign, 0))
# gables over the end sections' ceilings, facing into the main room
for y, sign in ((A0, 1), (A1, -1)):
    s.poly([(-X, y, WT), (X, y, WT), (CX, y, CT), (-CX, y, CT)], wall, (0, sign, 0))

# the end sections: a room() for the end wall (and its window), chamfered walls back to the main room's corners
rear = s.room(-RE, RE, YR, A0, RF, WT, floor=CARPET, open_sides=("-x", "+x", "+y"))
front = s.room(-FE, FE, A1, YF, FF, WT, floor=CARPET, open_sides=("-x", "+x", "-y"))
for side in (-1, 1):
    for e, yend, ymain, fz in ((RE, YR, A0, RF), (FE, YF, A1, FF)):
        inward = (-side, 1 if yend < ymain else -1, 0)
        s.poly([(side * e, yend, fz), (side * X, ymain, fz), (side * e, ymain, fz)], carpet, (0, 0, 1))
        s.poly([(side * e, yend, WT), (side * X, ymain, WT), (side * e, ymain, WT)], ceiling, (0, 0, -1))
        s.poly([(side * e, yend, fz), (side * X, ymain, fz), (side * X, ymain, WT), (side * e, yend, WT)], wall, inward)
# the back section's riser, and the front platform over the A-frame, flush with the front section's floor
s.poly([(-X, A0, FLOOR), (X, A0, FLOOR), (X, A0, RF), (-X, A0, RF)], trim, (0, 1, 0))
s.box((-X, PLINTH_Y, FLOOR), (X, A1, FF), carpet, skip=("+y", "-z", "-x", "+x"))
# humps over the wheels (x 0.92..1.21, y -0.37..0.40, up to z 0.89)
HUMP = (0.86, -0.43, 0.46, 0.95)
s.box((HUMP[0], HUMP[1], FLOOR), (X, HUMP[2], HUMP[3]), trim, skip=("+x", "-z"))
s.box((-X, HUMP[1], FLOOR), (-HUMP[0], HUMP[2], HUMP[3]), trim, skip=("-x", "-z"))
room_faces = [f for f in s.bm.faces if f not in before_rooms]
# metal step under the door: the floor is 0.33 m over the wheels' feet (z 0.12)
STEP = ((-1.58, DOOR_Y0 + 0.04, 0.0), (-1.215, DOOR_Y1 - 0.04, 0.29))
s.box(STEP[0], STEP[1], s.mat("trail_wall1"), light="out", skip=("+x", "-z"))

# collision: the vanilla COL holds only the fittings (air conditioner, skylights, chimney, hitch, wheels): the body is
# built here, the walls' slabs between the rooms and the skin
W = 0.12
SKIN = 1.22
s.col_box((-SKIN, A0, 0.30), (SKIN, A1, FLOOR))  # main floor
s.col_box((X, A0, FLOOR), (SKIN, A1, 2.50))  # +X wall
s.col_box((-SKIN, A0, FLOOR), (-X, DOOR_Y0, 2.50))  # -X wall, either side of the door
s.col_box((-SKIN, DOOR_Y1, FLOOR), (-X, A1, 2.50))
s.col_box((0.93, A0, 2.50), (1.20, A1, CT))  # under the coves, clear of the doorway's head
s.col_box((-1.20, A0, 2.50), (-0.93, A1, CT))
s.col_box((-1.10, A0, CT), (1.10, A1, 3.05))  # roof
s.col_box((-X, PLINTH_Y, FLOOR), (X, A1, FF))
s.col_box((HUMP[0], HUMP[1], FLOOR), (X, HUMP[2], HUMP[3]))
s.col_box((-X, HUMP[1], FLOOR), (-HUMP[0], HUMP[2], HUMP[3]))
s.col_box(STEP[0], STEP[1])


def end_cols(yend, ymain, e, fz, cap):
    """An end section's collision in slices along y: floor, chamfered sides out to the skin, ceiling; then the cap
    between its end wall and the skin's end (`cap`)."""
    n = 4
    for i in range(n):
        ya, yb = yend + (ymain - yend) * i / n, yend + (ymain - yend) * (i + 1) / n
        lo, hi = min(ya, yb), max(ya, yb)
        inner = e + (X - e) * (i + 1) / n  # the chamfer's widest point in the slice
        outer = max(max(s.half_width(y, 1.3) for y in (lo, hi)), inner + W)
        s.col_box((-outer, lo, 0.30), (outer, hi, fz))
        s.col_box((inner, lo, fz), (outer, hi, WT))
        s.col_box((-outer, lo, fz), (-inner, hi, WT))
        s.col_box((-outer, lo, WT), (outer, hi, 2.95))
    lo, hi = min(yend, cap), max(yend, cap)
    half = max(s.half_width(y, 1.3) for y in (lo + 0.01, hi - 0.01))
    s.col_box((-half, lo, 0.30), (half, hi, 2.40))


end_cols(YR, A0, RE, RF, -2.72)
end_cols(YF, A1, FE, FF, 4.04)


def check(faces, path):
    """Debug: every room vertex must lie inside the vanilla skin (rays out every way hit it) and clear of it."""
    lines = []
    for f in faces:
        if not f.is_valid:
            continue
        for v in f.verts:
            p = v.co
            missing = [d for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1)) if s.ray(p, d) is None]
            near = s.bvh.find_nearest(p)
            gap = (near[0] - p).length if near[0] is not None else 9.9
            if missing or gap < 0.02:
                lines.append("(%.3f %.3f %.3f) mat %d gap %.3f out %s" % (p.x, p.y, p.z, f.material_index, gap, missing))
    with open(path, "w") as fh:
        fh.write("\n".join(sorted(set(lines))) + "\n")


if "--check" in args():
    check(room_faces, os.path.join(os.environ.get("TEMP", "."), "sm_airstrm_med_check.txt"))
if "--no-render" not in args():
    s.render("outside_door", (-6.5, 2.5, 1.8), (0, 0.5, 1.3), size=(800, 500))
    s.render("outside_right", (6.5, -1.0, 1.8), (0, 0.5, 1.4), size=(800, 500))
    s.render("outside_back", (-2.5, -8.0, 2.2), (0, -2.0, 1.5), size=(800, 500))
    s.render("outside_front", (2.5, 9.5, 2.2), (0, 3.0, 1.5), size=(800, 500))
    s.render("inside_front", (0.0, -1.5, 1.65), (0, 4, 1.5), lens=16, size=(800, 500))
    s.render("inside_back", (0.0, 2.6, 1.65), (0, -3, 1.5), lens=16, size=(800, 500))
    s.render("inside_door", (0.7, 1.0, 1.6), (-1.2, 1.0, 1.6), lens=16, size=(800, 500))
    s.render("door_open", (-4.5, 3.0, 1.8), (-1.2, 1.0, 1.4), door_open=-100, size=(800, 500))
    s.render("front_window_out", (0.6, 6.3, 1.9), (0, 4.0, 1.85), lens=35, size=(800, 500))
    s.render("wheel_right", (4.0, 0.6, 0.55), (0.0, 0.0, 0.5), lens=28, size=(800, 500))
s.export()
