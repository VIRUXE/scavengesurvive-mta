"""des_nmot_02 (model 16673): the Fort Carson motel, two two-storey blocks of rooms in an L (the west block along y,
its doors facing east; the north block along x, its doors facing south), each with an outside gallery and two stairs,
and a small office by the sign. Every block is six bays of 4 m on each floor, 6 m deep: each bay becomes a room behind
its own door, 24 rooms in all, and the office a 25th.

    blender -b --python tools/house_shells/des_nmot_02.py [-- --no-render]

Run tools/house_shells/prep_nmot.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: single faces.
The doors and windows are painted on the walls: a front bay wears des_motelwall2 (256 x 128: a four-light window and
a door), mirrored bay by bay so the doors stand in pairs either side of every other partition; a back bay wears
des_motelwall1 (two small two-light windows). The upper front bays wear the texture a little larger than the lower
ones; they are mapped again here at the lower bays' scale, so one leaf fits all 24 doorways. Ground floor at -4.0
(the paving), the gallery and upper floor at -1.6, the roof a single pitch from 0.79 at the back to 1.14 at the front.
The office's door (des_door2, a glazed shop door on a quad of its own) takes the same leaf; its corner window stays
painted. The COL's three solid boxes (the blocks, the office) are replaced by slabs and walls; its triangle mesh
(roofs, stairs, rails) is kept. Writes house_shell/files/des_nmot_02.dff/.col and des_nmot_02_door.dff/.col,
build/des_nmot_02.json and build/des_nmot_02_doors.json (every leaf's hinge and heading).
"""
import json
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
from bighus import BED_FLOOR, BED_WALL, CEILING, LIVING_FLOOR, LIVING_WALL, drop_cols, stretch_walls  # noqa: E402

common.CURTAINS["des_nmot_02"] = "ah_curtains1"
from common import BUILD, args  # noqa: E402

FRONT, BACK, PLASTER = "des_motelwall2", "des_motelwall1", "des_motelwall3"
WALL = 0.2  # every wall and partition
BAY = 4.0
# floor lines of the painted walls, and the rooms on them: floor a little over the paving and the gallery
GROUND, UPPER = -3.999, -1.599
FLOORS = ((GROUND, -3.97, -1.80), (UPPER, -1.57, 0.66))  # painted floor line, room floor, ceiling
ROOF = 0.78  # under the roof's low edge
# des_motelwall2 on a lower front bay: u 1 at the bay's door end, falling U_PER_M a metre; v -1 at the floor line
U_PER_M, V_PER_M = 0.20725, 0.4009
DOOR = (0.265, 1.225)  # the painted door, metres from the bay's door end
DOOR_TOP = 2.143  # over the floor line
WINDOW = (1.751, 3.637, 1.013, 2.143)  # the painted front window: along from the door end, then over the floor line
MULLIONS = [("v", 0.25, 0.04), ("v", 0.5, 0.075), ("v", 0.75, 0.04)]
SASH = (FRONT, (0.80, 0.08, 0.90, 0.30))  # a patch of the painted door, stretched over every bar of the frames
# des_motelwall1 on a back bay: two windows, metres from the bay's start; their height over each floor line
BACK_WINDOWS = ((0.660, 1.458), (1.912, 2.694))
BACK_Z = {GROUND: (0.947, 1.953), UPPER: (0.846, 1.852)}
BACK_FRAME = [("v", 0.5, 0.06)]
PAPERS = ((BED_WALL, BED_FLOOR), (LIVING_WALL, BED_FLOOR))  # the rooms' wallpaper, bay by bay; carpet throughout

# the blocks: the front wall's normal (axis, side), the outer skin's front and back, the first bay's start
BLOCKS = (
    ("x", 1, -12.73, -18.73, -0.23),  # west block: bays along y
    ("y", -1, 21.052, 27.052, -2.564),  # north block: bays along x
)


class Motel(common.Shell):
    def _room_of(self, o):
        """The room behind opening `o`: the one on its floor (both floors share their walls' planes)."""
        for r in self.rooms:
            walls, span = (r[0:2], r[2:4]) if o.axis == "x" else (r[2:4], r[0:2])
            if any(abs(w - o.inner) < 0.02 for w in walls) and o.u0 < span[1] and o.u1 > span[0] and r[4] - 0.01 <= o.z0 and o.z1 <= r[5] + 0.01:
                return r
        return None

    def cut(self, o, back=0.02, front=0.25):
        """A bay's wall is two triangles 4 m wide: Shell.cut only splits the faces centred near the hole, which
        leaves the far triangle's half of it standing. Every skin face reaching into the hole is split here first."""
        n, a = common._axes(o.axis)
        skin = sum(o.outer.values()) / 4
        box = {a: (o.u0, o.u1), 2: (o.z0, o.z1)}
        for co, no in ((o.u0, a), (o.u1, a), (o.z0, 2), (o.z1, 2)):
            faces = []
            for f in self.bm.faces:
                if abs(f.calc_center_median()[n] - skin) > 0.05 or abs(f.normal[n]) < 0.9:
                    continue
                lo = {i: min(v.co[i] for v in f.verts) for i in (a, 2)}
                hi = {i: max(v.co[i] for v in f.verts) for i in (a, 2)}
                if lo[no] < co - 1e-4 and hi[no] > co + 1e-4 and all(lo[i] < box[i][1] and hi[i] > box[i][0] for i in (a, 2)):
                    faces.append(f)
            if faces:
                geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
                pn, pc = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
                pn[no], pc[no] = 1.0, co
                bmesh.ops.bisect_plane(self.bm, geom=geom, plane_co=pc, plane_no=pn, dist=1e-4)
        return super().cut(o, back, front)

    def _curtains(self):
        """Curtains at the front windows only: the 48 small back windows stay bare."""
        every = self.openings
        self.openings = [o for o in every if not getattr(o, "bare", False)]
        super()._curtains()
        self.openings = every


def span(axis, d0, d1, a0, a1):
    """(x0, x1, y0, y1) of the rectangle d0..d1 across a wall facing `axis`, a0..a1 along it."""
    d0, d1 = min(d0, d1), max(d0, d1)
    return (d0, d1, a0, a1) if axis == "x" else (a0, a1, d0, d1)


def col(s, axis, d0, d1, a0, a1, z0, z1):
    x0, x1, y0, y1 = span(axis, d0, d1, a0, a1)
    s.col_box((x0, y0, z0), (x1, y1, z1))


def remap_upper(s, axis, side, front, start):
    """The upper front bays, mapped like the lower ones (see the module docstring). The strip the texture no longer
    reaches at the top of the wall wears its top row of plaster."""
    n, a = (0, 1) if axis == "x" else (1, 0)
    mat = s.mat(FRONT)
    top = UPPER + 1.0 / V_PER_M  # where v passes the texture's top edge

    def faces():
        out = []
        for f in s.bm.faces:
            f.normal_update()
            c = f.calc_center_median()
            if f.material_index == mat and abs(c[n] - front) < 0.02 and f.normal[n] * side > 0.9 and UPPER - 0.01 < c.z < 0.95:
                out.append(f)
        return out

    fs = faces()
    geom = list({v for f in fs for v in f.verts}) + list({e for f in fs for e in f.edges}) + fs
    bmesh.ops.bisect_plane(s.bm, geom=geom, plane_co=(0, 0, top), plane_no=(0, 0, 1), dist=1e-4)
    for f in faces():
        strip = f.calc_center_median().z > top
        for loop in f.loops:
            co = loop.vert.co
            bay = min(5, max(0, int((f.calc_center_median()[a] - start) // BAY)))
            end = start + BAY * (bay + 1 if bay % 2 == 0 else bay)  # the bay's door end
            loop[s.uv].uv = (1.0 - abs(co[a] - end) * U_PER_M, -0.004 if strip else -1.0 + (co.z - UPPER) * V_PER_M)
    return len(fs)


s = Motel("des_nmot_02")
for axis, side, front, _back, start in BLOCKS:
    remap_upper(s, axis, side, front, start)

# ---- openings: the doors first (the first one is the leaf's pattern), ground floor before upper ------------------
plans = []  # (axis, side, front inner, back inner, [(a0, a1) per bay])
for axis, side, front, back, start in BLOCKS:
    fin, bin_ = front - side * WALL, back + side * WALL
    bays = []
    for i in range(6):
        a0 = start + BAY * i + (WALL if i == 0 else WALL / 2)
        a1 = start + BAY * (i + 1) - (WALL if i == 5 else WALL / 2)
        bays.append((a0, a1))
    plans.append((axis, side, fin, bin_, bays))
    for line, floor, _ceil in FLOORS:
        for i in range(6):
            lo = start + BAY * i
            end, way = (lo + BAY, -1) if i % 2 == 0 else (lo, 1)  # the door end, and which way the bay runs from it
            u0, u1 = sorted((end + way * DOOR[0], end + way * DOOR[1]))
            # the hinge at the door end, the painted handle at the far edge
            o = s.opening("door", axis, side, u0, u1, floor, line + DOOR_TOP, fin, hinge="left" if way < 0 else "right", reveal=PLASTER)
            (ua, va), (ub, vb) = o.door["uv"]
            o.door["uv"] = [[ub, va], [ua, vb]]
    for line, _floor, _ceil in FLOORS:
        for i in range(6):
            lo = start + BAY * i
            end, way = (lo + BAY, -1) if i % 2 == 0 else (lo, 1)
            u0, u1 = sorted((end + way * WINDOW[0], end + way * WINDOW[1]))
            s.opening("window", axis, side, u0, u1, line + WINDOW[2], line + WINDOW[3], fin, frame=MULLIONS, reveal=PLASTER, frame_skin=SASH)
            for w0, w1 in BACK_WINDOWS:
                z0, z1 = BACK_Z[line]
                o = s.opening("window", axis, -side, lo + w0, lo + w1, line + z0, line + z1, bin_, frame=BACK_FRAME, reveal=PLASTER, frame_skin=SASH)
                o.bare = True

# the office: its glazed shop door (a quad standing 0.02 off the east wall) makes way for the same leaf
OX0, OX1, OY0, OY1, OFLOOR, OCEIL = -6.62, -3.76, -1.93, 1.9, -3.97, -1.80
s.opening("door", "x", 1, 0.37, 1.33, OFLOOR, GROUND + DOOR_TOP, OX1, hinge="left", reveal=PLASTER)

# ---- rooms ----------------------------------------------------------------------------------------------------
before = set(s.bm.faces)
for axis, side, fin, bin_, bays in plans:
    for _line, floor, ceil in FLOORS:
        for i, (a0, a1) in enumerate(bays):
            paper, carpet = PAPERS[i % 2]
            x0, x1, y0, y1 = span(axis, fin, bin_, a0, a1)
            s.room(x0, x1, y0, y1, floor, ceil, floor=carpet, walls=paper, ceiling=CEILING)
        stretch_walls(s, set(s.bm.faces) - before, floor, ceil)
        before = set(s.bm.faces)
office = s.room(OX0, OX1, OY0, OY1, OFLOOR, OCEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING)
stretch_walls(s, set(s.bm.faces) - before, OFLOOR, OCEIL)

# ---- collision ------------------------------------------------------------------------------------------------
drop_cols(
    s,
    (-18.73, -0.23, -4.02, -12.73, 23.77, 0.81),
    (-2.56, 21.05, -4.06, 21.44, 27.05, 0.81),
    (-6.82, -2.13, -4.0, -3.56, 2.1, -1.52),
)
s.keep_col_mesh()  # the roofs, stairs and rails
for (axis, side, front, back, start), (_axis, _side, fin, bin_, bays) in zip(BLOCKS, plans):
    a0, a1 = start, start + 6 * BAY
    bottom, top = FLOORS[0][1], FLOORS[1][2]
    col(s, axis, front, back, a0, a1, bottom - 0.3, bottom)  # ground slab
    col(s, axis, front, back, a0, a1, FLOORS[0][2], FLOORS[1][1])  # the floor between
    col(s, axis, front, back, a0, a1, top, ROOF)  # ceiling slab under the roof
    col(s, axis, back, bin_, a0, a1, bottom, top)  # back wall
    col(s, axis, front, back, a0, a0 + WALL, bottom, top)  # end walls
    col(s, axis, front, back, a1 - WALL, a1, bottom, top)
    for i in range(1, 6):
        col(s, axis, front, back, start + BAY * i - WALL / 2, start + BAY * i + WALL / 2, bottom, top)  # partitions
    doors = sorted({(o.u0, o.u1) for o in s.openings if o.door and o.axis == axis and abs(o.inner - fin) < 0.02})
    for line, floor, ceil in FLOORS:
        u = a0
        for g0, g1 in doors:
            col(s, axis, front, fin, u, g0, floor, ceil)
            col(s, axis, front, fin, g0, g1, line + DOOR_TOP, ceil)  # over the door
            u = g1
        col(s, axis, front, fin, u, a1, floor, ceil)
s.room_cols(office, wall=WALL, roof=-1.56)

if "--no-render" not in args():
    only = [a for a in args() if not a.startswith("--")]
    views = (
        ("outside_west_block", (2.0, -6.0, 1.5), (-12.7, 9.0, -1.8), 24, 0),
        ("outside_north_block", (-9.0, 6.0, 1.0), (10.0, 21.0, -1.8), 24, 0),
        ("outside_back", (-32.0, 34.0, 4.0), (-12.0, 22.0, -2.0), 28, 0),
        ("doors_pair_ground", (-8.5, 2.2, -2.4), (-12.9, 3.8, -2.9), 24, 70),
        ("gallery_upper", (-11.6, -0.6, 0.1), (-12.8, 12.0, -0.6), 20, 70),
        ("window_front", (-9.6, 1.2, -2.5), (-12.8, 1.2, -2.5), 30, 0),
        ("inside_ground", (-13.2, 0.3, -2.4), (-18.5, 3.2, -3.2), 14, 0),
        ("inside_ground_out", (-18.2, 0.4, -2.4), (-12.9, 3.0, -3.0), 14, 70),
        ("inside_upper", (-13.2, 0.3, 0.0), (-18.5, 3.2, -0.9), 14, 0),
        ("inside_north_upper", (-2.0, 21.6, 0.0), (1.0, 26.8, -0.9), 14, 0),
        ("office", (0.5, 3.5, -2.6), (-3.6, 0.6, -3.0), 28, 80),
        ("inside_office", (-6.3, -1.6, -2.5), (-3.8, 1.5, -3.1), 14, 80),
        ("v_top", (1.0, 12.0, 70.0), (1.0, 12.1, 0.0), 35, 0),
    )
    lamps = {
        "lamp_g": (-15.7, 1.8, -2.2), "lamp_u": (-15.7, 1.8, 0.2), "lamp_n": (-0.5, 24.0, 0.2), "lamp_o": (-5.2, 0.0, -2.2),
    }
    first = True
    for view, eye, target, lens, swing in views:
        if only and view not in only:
            continue
        s.render(view, eye, target, lens=lens, size=(960, 600), door_open=swing)
        if first:  # render() makes the set on its first call: the ground under the paving, a lamp in the rooms seen
            first = False
            bpy.data.objects["ground"].location.z = -4.02
            for name, at in lamps.items():
                lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
                lamp.data.energy = 120
                lamp.location = at
                bpy.context.scene.collection.objects.link(lamp)
            s.render(view, eye, target, lens=lens, size=(960, 600), door_open=swing)
    for name in lamps:
        if bpy.data.objects.get(name):
            bpy.data.objects.remove(bpy.data.objects[name])
s.export()
with open(os.path.join(BUILD, "des_nmot_02_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
