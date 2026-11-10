"""The Marquis (vehicle 484) with a cabin a ped can walk into: run after tools/marquis_cabin/prep.py,

    blender -b --python tools/marquis_cabin/cabin.py

Vanilla, the companionway at the back of the deckhouse is a painted door 0.66 m wide and 1.75 m tall (z 0.27..2.02)
with a sliding hatch closed over it and two collision spheres (r 0.70) filling the doorway, and there is nothing
below deck. This build keeps the exterior and:
- lifts the coachroof (the deckhouse above z 1.35, with the mast and boom on it) by LIFT, for headroom over a sole
  that sits above the waterline (the vehicle's origin floats ~0.2 m over the sea: a sole below z 0.2 had the ped
  swimming in the cabin);
- cuts the doorway to the recess's full width (x +-0.41) and opens it to the sky: the painted leaf, its frame and the
  fascia above it go, the hatch slides 0.85 m forward on the roof and the roof is cut away under where it was;
- rebuilds the entrance: two treads from the cockpit floor to the landing at the sole, a framed doorway with a sill
  and a lintel, and a real door leaf, a frame of its own (cabin_door / cabin_door_ok, not the standard door_lf: the game
  resets that one on a boat every frame), hinged on the starboard post and swung into the cabin by marquis_cabin's client, with its collision as an object of its own (files/marquis_door.dff/.col);
- builds the saloon below the deckhouse from the aft bulkhead (y 0) to the V-berth's head (y 6.5): mahogany linings
  to the side decks, riveted ship panels on the deckhouse walls and headlining, a port dinette (settee, table), a
  starboard galley (worktop, cooker) and settee, lockers under the side decks and a V-berth on a striped mattress;
- rebuilds the ped collision: the cabin's floor, walls and furniture as boxes, a ramp from the cockpit floor down
  the entrance to the sole, the roof with the hatch's slot, and the spheres that stood in the cabin replaced
  by smaller ones in the hull's skin, under the sole and over the roof (the game carries a vehicle on its spheres).

Coordinates are the vehicle root's (the `boat` frame sits 0.46 m above it), metres, +y forward, +z up.
Writes resources/[scavengesurvive]/marquis_cabin/files/marquis.dff, marquis.txd (the vanilla dictionary plus
build/vanilla/cabin.txd), marquis_door.dff/.col and cabin.lua (the door's hinge for the client).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
VANILLA = os.path.join(BUILD, "vanilla")
TEX = os.path.join(BUILD, "tex")
RENDERS = os.path.join(BUILD, "renders")
FILES = os.path.join(ROOT, "resources", "[scavengesurvive]", "marquis_cabin", "files")
sys.path.insert(0, ROOT)
from tools.extract_samp_models import merge_txd  # noqa: E402

S = 0.35  # cabin sole: the boat floats with its origin ~0.2 m over the sea, so feet stay dry and clear of waves
LIFT = 0.30  # the coachroof's rise
DECK_UNDER = 1.10  # underside of the side decks: top of the hull linings
CEIL = 2.36  # headlining under the deckhouse roof (2.19 + LIFT at its crown, 2.10 + LIFT at its edges)
ROOF = 2.19 + LIFT
DOOR_TOP = 2.22  # the leaf's top; the head sits over it, under the coachroof soffit (z 2.315)
DOOR_X = 0.41  # half-width of the companionway recess, now the doorway's
DOOR_Y = -0.03  # the painted door's plane: aft face of the cabin
SLOT_Y = 0.80  # the roof is open from the door to here (the hatch slid forward)
HATCH_SLIDE = 1.05  # clear of the companionway slot, so the opening is sky rather than the hatch's underside
FWD = 6.5  # the V-berth's head bulkhead (the coachroof's lift fades out past it)
# half-widths along y: the hull linings (sole to the side decks) and the deckhouse walls (side decks to the roof)
LINING = ((0.0, 1.55), (4.5, 1.55), (5.5, 1.40), (6.5, 1.15))
HOUSE = ((0.0, 1.33), (3.0, 1.33), (4.0, 1.28), (5.0, 1.16), (6.0, 1.02), (6.5, 0.93))
# companionway. The recess cheeks are the hull's own plane at x ±CHEEK. Its aft edge, which the wood replaces,
# runs (y -1.373, z 1.247) — (y -0.947, z 2.091) — (y -0.073, z 2.391), down to the sole at z 0.271.
CHEEK = 0.409
LANDING_Y = -0.46
HEAD_Z = 2.30  # top of the door head, under the soffit
CASE_Y0, CASE_Y1 = -0.12, -0.06  # casing proud of the leaf, toward the cockpit
# the collision ramp: from the cockpit floor's edge down the treads to the landing
RAMP = ((-0.94, 0.71), (LANDING_Y, S))
# the door leaf: hinged on the starboard post, 0.80 m wide, extending to port when shut; the game swings a left door
# clockwise, so it opens into the cabin
HINGE = (0.40, DOOR_Y, S + 0.02)
LEAF_W, LEAF_T = 0.80, 0.04
# metres per texture repeat
WOOD, SOLE, WHITE, SHEET, STOVE, ATLAS = "bdup2_wood", "strip_wood", "sf_ship_ceiling", "cj_matress2", "stove_1", "marquis92interior128"
SCALE = {WOOD: 1.0, SOLE: 1.2, WHITE: 1.5, SHEET: 1.1}
CUSHION = (0.0, 64.0, 64.0, 82.0)  # the blue cushion in the Marquis's own atlas (pixels x0, y0, x1, y1 of 128)


def interp(table, y):
    y = min(max(y, table[0][0]), table[-1][0])
    for (y0, a), (y1, b) in zip(table, table[1:]):
        if y0 <= y <= y1:
            return a + (b - a) * (y - y0) / (y1 - y0) if y1 > y0 else a
    return table[-1][1]


def lining(y):
    return interp(LINING, y)


def house(y):
    return interp(HOUSE, y)


BREAKS = sorted({y for y, _ in LINING} | {y for y, _ in HOUSE} | {SLOT_Y})

# --- the vanilla model ---------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module="DragonFF")
bpy.ops.import_scene.dff(filepath=os.path.join(VANILLA, "marquis.dff"), read_mat_split=True, remove_doubles=False, load_images=False)


def image(name):
    """The texture `name` as a Blender image named exactly that (the exporter writes the image's name)."""
    img = bpy.data.images.get(name)
    if img is None:
        path = os.path.join(TEX, name.lower() + ".png")
        img = bpy.data.images.load(path) if os.path.exists(path) else bpy.data.images.new(name, 4, 4)
        img.name = name
    return img


for mat in bpy.data.materials:
    for node in mat.node_tree.nodes if mat.node_tree else ():
        if node.type == "TEX_IMAGE":
            node.image = image((node.image.name if node.image else (node.label or node.name)).split(".")[0])

boat = bpy.data.objects["boat"]
col = next(o for o in bpy.data.objects if o.type == "MESH" and o.dff.type == "COL")
col_coll = col.users_collection[0]
to_boat = boat.matrix_world.inverted()


def tex_of(mat):
    return next((n.image.name for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), "") if mat and mat.node_tree else ""


mats = list(boat.data.materials)
atlas_mat = next(m for m in mats if m.name == "interior")  # untinted, the atlas
MAT = {ATLAS: mats.index(atlas_mat)}
for name in (WOOD, SOLE, WHITE, SHEET, STOVE):
    m = atlas_mat.copy()
    m.name = "cabin_" + name
    for node in m.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            node.image = image(name)
    boat.data.materials.append(m)
    MAT[name] = len(boat.data.materials) - 1
MAT["glass"] = next(i for i, m in enumerate(boat.data.materials) if m.name == "glass")

bm = bmesh.new()
bm.from_mesh(boat.data)
bm.transform(boat.matrix_world)  # work in root coordinates, back at the end
uv = bm.loops.layers.uv.active
colours = list(bm.loops.layers.color.values()) + list(bm.loops.layers.float_color.values())
# new faces take the vanilla interior's mean vertex colour (vehicles light themselves; this is the paint's tint)
prelight = []
for layer in colours:
    vals = [loop[layer] for f in bm.faces if f.material_index == MAT[ATLAS] for loop in f.loops]
    prelight.append(tuple(sum(v[i] for v in vals) / len(vals) for i in range(4)) if vals else (1, 1, 1, 1))


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lift(x, y, z):
    """The coachroof's rise at a point: everything above the side decks (z 1.35..2.0 blends in) within the deckhouse's
    width (past x 1.65 the rails and gunwales stay), from the cockpit's bulkhead forward, fading out over the
    foredeck (y 6.5..9.5)."""
    w = smooth((z - 1.35) / 0.65) * (1 - smooth((abs(x) - 1.65) / 0.25)) * smooth((y + 0.55) / 0.1) * (1 - smooth((y - 6.5) / 3.0))
    return z + LIFT * w


for v in bm.verts:
    v.co.z = lift(*v.co)
vlo = bpy.data.objects.get("boat_vlo")
if vlo:  # the distant model rises with it
    for v in vlo.data.vertices:
        w = vlo.matrix_world @ v.co
        v.co.z += lift(w.x, w.y, w.z) - w.z
    vlo.data.update()


def faces_where(pred):
    return [f for f in bm.faces if pred(f, [v.co for v in f.verts])]


# the painted door, its frame and reveals, and the fascia over it: every face in the door's plane band
door = faces_where(lambda f, vs: all(abs(v.x) <= DOOR_X + 0.001 and -0.08 <= v.y <= -0.02 and v.z >= 0.26 for v in vs))
bmesh.ops.delete(bm, geom=door, context="FACES")
# the vanilla recess's treads and risers (z 0.27..0.63 between y -0.94 and the door), rebuilt below; the riser at the
# cockpit floor's edge (y -0.94) stays
steps = faces_where(lambda f, vs: all(abs(v.x) <= DOOR_X + 0.001 and -0.95 <= v.y <= -0.02 and v.z <= 0.65 for v in vs) and (abs(f.normal.z) > 0.9 or abs(f.normal.y) > 0.9) and not all(v.y < -0.93 for v in vs))
bmesh.ops.delete(bm, geom=steps, context="FACES")

# the sliding hatch (on the roof over the door, z 2.14..2.28) slides forward
hatch = faces_where(lambda f, vs: tex_of(boat.data.materials[f.material_index]) == ATLAS and all(abs(v.x) <= DOOR_X + 0.001 and -0.08 <= v.y <= 1.0 and v.z >= 2.13 for v in vs))
hatch_verts = {v for f in hatch for v in f.verts}
for v in hatch_verts:
    v.co.y += HATCH_SLIDE
# the hatch is a single skin: its underside is a backface, which the game draws black. Give it the same paint, facing down.
for f in list(hatch):
    if f.normal.z < 0.5:
        continue
    pts = [v.co - Vector((0.0, 0.0, 0.02)) for v in f.verts]
    uvs = [loop[uv].uv[:] for loop in f.loops]
    pts.reverse()
    uvs.reverse()
    nf = bm.faces.new([bm.verts.new(p) for p in pts])
    nf.material_index = f.material_index
    for i, loop in enumerate(nf.loops):
        loop[uv].uv = uvs[i]
        for layer, c in zip(colours, prelight):
            loop[layer] = c

# the roof under the hatch's old place: cut along the slot's edges, then the slot's faces go
def roof_faces():
    return [f for f in bm.faces if f.normal.z > 0.9 and all(2.05 + LIFT <= v.co.z <= 2.22 + LIFT for v in f.verts) and f not in hatch]


for co, no in (((DOOR_X, 0, 0), (1, 0, 0)), ((-DOOR_X, 0, 0), (1, 0, 0)), ((0, SLOT_Y, 0), (0, 1, 0))):
    rf = roof_faces()
    geom = list({e for f in rf for e in f.edges}) + rf + list({v for f in rf for v in f.verts})
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
slot = [f for f in roof_faces() if abs((c := f.calc_center_median()).x) < DOOR_X and DOOR_Y - 0.1 < c.y < SLOT_Y]
# anything still standing in the opening (the roof's dark underside, the old fascia) reads as a black slab
slot += [f for f in bm.faces if f not in hatch and (c := f.calc_center_median()) and abs(c.x) < DOOR_X - 0.02 and -0.05 < c.y < SLOT_Y - 0.02 and c.z > 2.05 + LIFT]
slot = list({f for f in slot if f.is_valid})
bmesh.ops.delete(bm, geom=slot, context="FACES")
# the grey the cockpit sees is hull paint on the recess cheeks, one plane at x ±0.41 from the coaming to the door.
# Only that paint goes: the coachroof's inner skin shares the plane and stays.
def _mat0(f):
    return boat.data.materials[f.material_index].name.split(".")[0]


recess = faces_where(lambda f, vs: _mat0(f) == "primary" and abs(f.normal.x) > 0.7 and all(0.38 <= abs(v.x) <= 0.45 and -1.50 <= v.y <= 0.05 and v.z >= 0.20 for v in vs))
bmesh.ops.delete(bm, geom=recess, context="FACES")


# --- the cabin's faces ---------------------------------------------------------------------------------------------
def face(pts, mat, facing, uvs=None, panel=False):
    """A face through `pts` (root coordinates) turned to `facing`; planar UVs at the material's scale, or `uvs`.
    `panel` maps the face once onto the upper half of the wood, above that texture's midline seam."""
    pts = [Vector(p) for p in pts]
    n = (pts[1] - pts[0]).cross(pts[2] - pts[1])
    if n.dot(Vector(facing)) < 0:
        pts.reverse()
        uvs = list(reversed(uvs)) if uvs else None
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    f.material_index = MAT[mat]
    axes = [i for i in range(3) if abs(facing[i]) < 0.5] or [0, 1]
    if len(axes) == 3:  # facing not along an axis: drop its largest component
        axes.remove(max(range(3), key=lambda i: abs(facing[i])))
    if axes == [0, 1] and abs(facing[2]) < 0.5:
        axes = [1, 2]
    s = SCALE.get(mat, 1.0)
    if panel and uvs is None:
        lo_a, hi_a = min(p[axes[0]] for p in pts), max(p[axes[0]] for p in pts)
        lo_b, hi_b = min(p[axes[1]] for p in pts), max(p[axes[1]] for p in pts)
    tint = (1.0, 1.0, 1.0, 1.0) if mat == "pane" else None
    for i, loop in enumerate(f.loops):
        if uvs:
            loop[uv].uv = uvs[i]
        elif panel:
            u = (loop.vert.co[axes[0]] - lo_a) / ((hi_a - lo_a) or 1)
            w = (loop.vert.co[axes[1]] - lo_b) / ((hi_b - lo_b) or 1)
            loop[uv].uv = (0.08 + u * 0.84, 0.54 + w * 0.40)
        else:
            # the wood's midline is a hard seam; phase it onto the repeat boundary so a face shorter than a metre misses it
            phase = 0.5 if mat == WOOD else 0.0
            loop[uv].uv = (loop.vert.co[axes[0]] / s + phase, loop.vert.co[axes[1]] / s + phase)
        for layer, c in zip(colours, prelight):
            loop[layer] = tint or c
    return f


def region(rect, pts, a, b):
    """UVs mapping the atlas rectangle `rect` (pixels) over the face's extent along axes a, b."""
    x0, y0, x1, y1 = rect
    lo_a, hi_a = min(p[a] for p in pts), max(p[a] for p in pts)
    lo_b, hi_b = min(p[b] for p in pts), max(p[b] for p in pts)
    out = []
    for p in pts:
        u = (p[a] - lo_a) / ((hi_a - lo_a) or 1)
        w = (p[b] - lo_b) / ((hi_b - lo_b) or 1)
        out.append(((x0 + u * (x1 - x0)) / 128, 1 - (y1 - w * (y1 - y0)) / 128))
    return out


def box(lo, hi, mat, top=None, skip=(), atlas_top=None, atlas_sides=None, panel=False):
    """An axis-aligned box, outward faces; `top` a material for the top face, `skip` faces ('-x', '+z', ...)."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    quads = {
        "+z": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
        "-z": ([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1)),
        "-x": ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0)),
        "+x": ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
        "-y": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        "+y": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
    }
    for key, (pts, facing) in quads.items():
        if key in skip:
            continue
        if key == "+z" and atlas_top:
            face(pts, ATLAS, facing, region(atlas_top, pts, 1, 0))
        elif key != "-z" and key != "+z" and atlas_sides:
            a = 1 if key in ("-x", "+x") else 0
            face(pts, ATLAS, facing, region(atlas_sides, pts, a, 2))
        else:
            face(pts, top if key == "+z" and top else mat, facing, panel=panel)


def plan_prism(y0, y1, half, z0, z1, mat, top_mat=None, inset=0.0, steps=6):
    """A block across the hull from y0 to y1, its sides following `half(y)` less `inset`: top and side faces."""
    ys = [y0 + (y1 - y0) * i / steps for i in range(steps + 1)]
    for a, b in zip(ys, ys[1:]):
        ha, hb = half(a) - inset, half(b) - inset
        face([(-ha, a, z1), (ha, a, z1), (hb, b, z1), (-hb, b, z1)], top_mat or mat, (0, 0, 1))
        for s in (1, -1):
            face([(s * ha, a, z0), (s * hb, b, z0), (s * hb, b, z1), (s * ha, a, z1)], mat, (s, 0, 0))
    h = half(y0) - inset
    face([(-h, y0, z0), (h, y0, z0), (h, y0, z1), (-h, y0, z1)], mat, (0, -1, 0))


# sole, linings, side-deck undersides, deckhouse walls and the headlining, segment by segment
for a, b in zip(BREAKS, BREAKS[1:]):
    la, lb, ha, hb = lining(a), lining(b), house(a), house(b)
    face([(-la, a, S), (la, a, S), (lb, b, S), (-lb, b, S)], SOLE, (0, 0, 1))
    for s in (1, -1):
        face([(s * la, a, S), (s * lb, b, S), (s * lb, b, DECK_UNDER), (s * la, a, DECK_UNDER)], WOOD, (-s, 0, 0))
        face([(s * la, a, DECK_UNDER), (s * lb, b, DECK_UNDER), (s * hb, b, DECK_UNDER), (s * ha, a, DECK_UNDER)], WHITE, (0, 0, -1))
        face([(s * ha, a, DECK_UNDER), (s * hb, b, DECK_UNDER), (s * hb, b, CEIL), (s * ha, a, CEIL)], WHITE, (-s, 0, 0))
    if b <= SLOT_Y:  # beside the open hatch
        for s in (1, -1):
            face([(s * DOOR_X, a, CEIL), (s * ha, a, CEIL), (s * hb, b, CEIL), (s * DOOR_X, b, CEIL)], WHITE, (0, 0, -1))
    else:
        face([(-ha, a, CEIL), (ha, a, CEIL), (hb, b, CEIL), (-hb, b, CEIL)], WHITE, (0, 0, -1))

# the hatch slot's sides and front, headlining to roof
for s in (1, -1):
    face([(s * DOOR_X, 0.0, CEIL), (s * DOOR_X, SLOT_Y, CEIL), (s * DOOR_X, SLOT_Y, ROOF), (s * DOOR_X, 0.0, ROOF)], WOOD, (-s, 0, 0))
face([(-DOOR_X, SLOT_Y, CEIL), (DOOR_X, SLOT_Y, CEIL), (DOOR_X, SLOT_Y, ROOF), (-DOOR_X, SLOT_Y, ROOF)], WOOD, (0, -1, 0))

# aft bulkhead (y 0) either side of the doorway, and the head of the doorway's sides up to the roof
L0, H0 = lining(0.0), house(0.0)
for s in (1, -1):
    face([(s * DOOR_X, 0.0, S), (s * L0, 0.0, S), (s * L0, 0.0, DECK_UNDER), (s * DOOR_X, 0.0, DECK_UNDER)], WOOD, (0, 1, 0))
    face([(s * DOOR_X, 0.0, DECK_UNDER), (s * H0, 0.0, DECK_UNDER), (s * H0, 0.0, CEIL), (s * DOOR_X, 0.0, CEIL)], WOOD, (0, 1, 0))
# forward bulkhead (y 6.5), behind the V-berth
LF, HF = lining(FWD), house(FWD)
face([(-LF, FWD, S), (LF, FWD, S), (LF, FWD, DECK_UNDER), (-LF, FWD, DECK_UNDER)], WOOD, (0, -1, 0))
face([(-HF, FWD, DECK_UNDER), (HF, FWD, DECK_UNDER), (HF, FWD, CEIL), (-HF, FWD, CEIL)], WOOD, (0, -1, 0))

# the companionway from the cockpit: a cheek on the hull's own outline (so the cut has no dark rim), three
# risers, and a casing proud of the leaf. The head stops under the soffit; a short fascia meets the roof edge.
for s in (1, -1):
    x = s * CHEEK
    face(
        [(x, -1.373, 0.271), (x, -0.073, 0.271), (x, -0.073, 2.391), (x, -0.947, 2.091), (x, -1.373, 1.247)],
        WOOD, (-s, 0, 0), panel=True,
    )
# cockpit floor z 0.71 at y -0.94, then two treads, then the sole. Each riser faces the cockpit.
prev_y, prev_z = -0.94, 0.71
for y1, z1 in ((-0.70, 0.59), (-0.46, 0.47), (CASE_Y0, S)):
    face([(-CHEEK, prev_y, z1), (CHEEK, prev_y, z1), (CHEEK, prev_y, prev_z), (-CHEEK, prev_y, prev_z)], WOOD, (0, -1, 0), panel=True)
    nose = prev_y - 0.03  # the tread lip, so each step reads from the cockpit
    face([(-CHEEK, nose, z1), (CHEEK, nose, z1), (CHEEK, y1, z1), (-CHEEK, y1, z1)], SOLE, (0, 0, 1))
    face([(-CHEEK, nose, z1 - 0.02), (CHEEK, nose, z1 - 0.02), (CHEEK, nose, z1), (-CHEEK, nose, z1)], WOOD, (0, -1, 0), panel=True)
    prev_y, prev_z = y1, z1
box((-0.40, CASE_Y0, S - 0.02), (0.40, -0.02, S + 0.015), WOOD, panel=True, skip=("-z",))  # sill
for s in (1, -1):
    x0, x1 = sorted((s * 0.34, s * 0.40))
    box((x0, CASE_Y0, S + 0.015), (x1, CASE_Y1, HEAD_Z - 0.08), WOOD, panel=True)  # jamb, inside the opening
box((-0.40, CASE_Y0, HEAD_Z - 0.10), (0.40, CASE_Y1, HEAD_Z), WOOD, panel=True)  # head
# closes the crack between the door head and the coachroof's aft edge. Taller than this and it comes through the roof.
face([(-CHEEK, -0.08, HEAD_Z), (CHEEK, -0.08, HEAD_Z), (CHEEK, -0.08, 2.39), (-CHEEK, -0.08, 2.39)], WOOD, (0, -1, 0), panel=True)

FURNITURE = []  # (lo, hi): each piece's collision box


def piece(lo, hi, *args, **kw):
    box(lo, hi, *args, **kw)
    FURNITURE.append((lo, hi))


SEAT, CUSH, BACK = S + 0.30, S + 0.42, S + 0.95
# port dinette: settee along the lining, table on a pedestal
piece((-1.50, 1.00, S), (-0.95, 4.40, SEAT), WOOD, skip=("-z",))
box((-1.50, 1.00, SEAT), (-0.95, 4.40, CUSH), WOOD, atlas_top=CUSHION, atlas_sides=CUSHION, skip=("-z",))
piece((-1.55, 1.00, CUSH), (-1.38, 4.40, BACK), WOOD, atlas_sides=CUSHION, atlas_top=CUSHION, skip=("-z",))
piece((-0.90, 1.80, S + 0.68), (-0.30, 3.60, S + 0.73), WOOD)
box((-0.72, 2.52, S), (-0.48, 2.88, S + 0.06), WOOD, skip=("-z",))  # foot, so the top doesn't read as floating
box((-0.64, 2.62, S + 0.06), (-0.56, 2.78, S + 0.68), WOOD, skip=("-z", "+z"))
# starboard galley: worktop over cupboards, the cooker in its aisle face
piece((0.95, 0.55, S), (1.55, 2.60, S + 0.88), WOOD, top=WHITE, skip=("-z",))
face([(0.949, 1.15, S + 0.05), (0.949, 1.75, S + 0.05), (0.949, 1.75, S + 0.85), (0.949, 1.15, S + 0.85)], STOVE, (-1, 0, 0), [(1, 0), (0, 0), (0, 1), (1, 1)])
# starboard settee
piece((0.95, 2.90, S), (1.50, 4.40, SEAT), WOOD, skip=("-z",))
box((0.95, 2.90, SEAT), (1.50, 4.40, CUSH), WOOD, atlas_top=CUSHION, atlas_sides=CUSHION, skip=("-z",))
piece((1.38, 2.90, CUSH), (1.55, 4.40, BACK), WOOD, atlas_sides=CUSHION, atlas_top=CUSHION, skip=("-z",))
# lockers under the side decks, both sides
for s in (1, -1):
    lo, hi = sorted((s * 1.28, s * 1.55))
    piece((lo, 0.40, 0.80), (hi, 4.50, DECK_UNDER), WOOD, skip=("+z",))
# V-berth: a platform across the bow, mattress on top
BERTH_Y, BERTH_TOP = 4.6, S + 0.55
plan_prism(BERTH_Y, FWD, lining, S, BERTH_TOP, WOOD)
plan_prism(BERTH_Y + 0.04, FWD, lining, BERTH_TOP, BERTH_TOP + 0.15, SHEET, inset=0.04)
FURNITURE.append(((-1.40, BERTH_Y, S), (1.40, FWD, BERTH_TOP + 0.15)))

bm.normal_update()
bm.transform(to_boat)
bm.to_mesh(boat.data)
bm.free()

# the door leaf, in the hinge's own frame (origin at the hinge's bottom, extending to port): a mahogany slab with a
# glazed pane in its upper half, both faces, and a handle
leaf_mesh = boat.data.copy()
leaf_mesh.name = "cabin_door_ok"
bm = bmesh.new()
bm.from_mesh(leaf_mesh)
bm.clear()
uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
colours = list(bm.loops.layers.color.values()) + list(bm.loops.layers.float_color.values())
LEAF_H = DOOR_TOP - HINGE[2]
# a frame, not a slab with a plate stuck on it: stiles the full height, rails between them, the boat's own glass in the hole
STILE = 0.12
x_latch0, x_latch1 = -LEAF_W, -LEAF_W + STILE
x_hinge0 = -STILE
z_win0, z_win1 = LEAF_H * 0.46, LEAF_H * 0.84
box((x_hinge0, -LEAF_T / 2, 0.0), (0.0, LEAF_T / 2, LEAF_H), WOOD, panel=True)
box((x_latch0, -LEAF_T / 2, 0.0), (x_latch1, LEAF_T / 2, LEAF_H), WOOD, panel=True)
box((x_latch1, -LEAF_T / 2, 0.0), (x_hinge0, LEAF_T / 2, z_win0), WOOD, panel=True, skip=("+x", "-x"))
box((x_latch1, -LEAF_T / 2, z_win1), (x_hinge0, LEAF_T / 2, LEAF_H), WOOD, panel=True, skip=("+x", "-x"))
for sy in (-1, 1):
    y = sy * 0.004
    pts = [(x_latch1, y, z_win0), (x_hinge0, y, z_win0), (x_hinge0, y, z_win1), (x_latch1, y, z_win1)]
    face(pts, "glass", (0, sy, 0))
for y0, y1 in ((-LEAF_T / 2 - 0.03, -LEAF_T / 2), (LEAF_T / 2, LEAF_T / 2 + 0.03)):
    box((-0.72, y0, 0.95), (-0.68, y1, 1.05), WOOD)
bm.normal_update()
bm.to_mesh(leaf_mesh)
bm.free()

# --- collision -----------------------------------------------------------------------------------------------------
cm = bmesh.new()
cm.from_mesh(col.data)
for v in cm.verts:
    v.co.z = lift(*v.co)
dead = [f for f in cm.faces if (c := f.calc_center_median()) and ((abs(c.z - ROOF) < 0.03 and c.y < 2.3 and abs(c.x) < 1.5) or (-0.8 < c.y < -0.3 and 0.1 < c.z < 0.6))]
cm_mat = dead[0].material_index if dead else 0
bmesh.ops.delete(cm, geom=dead, context="FACES")


def tri_quad(pts):
    vs = [cm.verts.new(p) for p in pts]
    for tri in ((vs[0], vs[1], vs[2]), (vs[0], vs[2], vs[3])):
        f = cm.faces.new(tri)
        f.material_index = cm_mat
        if f.normal.z < 0:
            f.normal_flip()


(ry0, rz0), (ry1, rz1) = RAMP
tri_quad([(-DOOR_X, ry0, rz0), (DOOR_X, ry0, rz0), (DOOR_X, ry1, rz1), (-DOOR_X, ry1, rz1)])
tri_quad([(0.4, -1.28, ROOF), (1.45, -1.28, ROOF), (1.45, 2.26, ROOF), (0.4, 2.26, ROOF)])
tri_quad([(-1.45, -1.28, ROOF), (-0.4, -1.28, ROOF), (-0.4, 2.26, ROOF), (-1.45, 2.26, ROOF)])
tri_quad([(-0.4, SLOT_Y, ROOF), (0.4, SLOT_Y, ROOF), (0.4, 2.26, ROOF), (-0.4, 2.26, ROOF)])
cm.to_mesh(col.data)
cm.free()


def in_cabin_distance(p):
    """Distance from p to the space a ped uses: the cabin below the deckhouse and the companionway."""
    best = 1e9
    for (y0, y1), (z0, z1), half in (((0.0, FWD), (S, DECK_UNDER), lining), ((0.0, FWD), (DECK_UNDER, CEIL), house), ((-1.3, 0.0), (0.2, 2.7), lambda y: DOOR_X)):
        cy = min(max(p.y, y0), y1)
        cz = min(max(p.z, z0), z1)
        h = half(cy)
        cx = min(max(p.x, -h), h)
        best = min(best, (Vector((cx, cy, cz)) - p).length)
    return best


spheres_out = 0
for o in list(bpy.data.objects):
    if o.type == "EMPTY" and o.dff.type == "COL" and o.empty_display_type == "SPHERE":
        r = o.matrix_world.to_scale().x
        if in_cabin_distance(o.matrix_world.translation) < r - 0.03:
            sphere_mat = o.dff.col_material
            bpy.data.objects.remove(o)
            spheres_out += 1


def empty(kind, loc, scale, name, material):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = 1.0
    e.location, e.scale = loc, scale
    e.dff.type = "COL"
    e.dff.col_material = material
    col_coll.objects.link(e)


n = 0
for i in range(7):  # the hull's skin either side, outside the linings
    y = 0.5 + i
    for s in (1, -1):
        empty("SPHERE", (s * (lining(y) + 0.32), y, 0.45), (0.30,) * 3, f"cabin_sph{n}", sphere_mat)
        empty("SPHERE", (s * (house(y) + 0.25), y, 1.65), (0.10,) * 3, f"cabin_sph{n + 1}", sphere_mat)
        n += 2
for y in (1.5, 3.0, 4.5, 6.0):  # over the roof
    for x in (-0.85, 0.0, 0.85):
        if abs(x) <= house(y) - 0.2:
            empty("SPHERE", (x, y, CEIL + 0.27), (0.22,) * 3, f"cabin_sph{n}", sphere_mat)
            n += 1

BOX_MAT = sphere_mat
boxes = [((-1.6, 0.0, S - 0.15), (1.6, FWD, S)), ((-DOOR_X, LANDING_Y, S - 0.15), (DOOR_X, 0.0, S))]  # the sole and the landing
for i in range(13):  # linings and deckhouse walls in 0.5 m bins, at their narrower end
    y0, y1 = i * 0.5, i * 0.5 + 0.5
    lm, hm = min(lining(y0), lining(y1)), min(house(y0), house(y1))
    for s in (1, -1):
        boxes.append(((min(s * lm, s * (lm + 0.15)), y0, S), (max(s * lm, s * (lm + 0.15)), y1, DECK_UNDER)))
        boxes.append(((min(s * hm, s * (hm + 0.15)), y0, DECK_UNDER), (max(s * hm, s * (hm + 0.15)), y1, CEIL)))
for s in (1, -1):
    boxes.append(((min(s * DOOR_X, s * 1.7), -0.15, S), (max(s * DOOR_X, s * 1.7), 0.0, CEIL)))  # aft bulkhead
    boxes.append(((min(s * DOOR_X, s * 0.8), -1.3, 0.2), (max(s * DOOR_X, s * 0.8), 0.0, 2.7)))  # companionway sides
boxes.append(((-1.2, FWD, S), (1.2, FWD + 0.15, CEIL)))  # forward bulkhead
boxes += FURNITURE
for i, (lo, hi) in enumerate(boxes):
    c = [(a + b) / 2 for a, b in zip(lo, hi)]
    h = [(b - a) / 2 for a, b in zip(lo, hi)]
    empty("CUBE", c, h, f"cabin_box{i}", BOX_MAT)
col_coll.dff.auto_bounds = True
bpy.context.view_layer.update()

# --- the door as the vehicle's front-left door, and export ----------------------------------------------------------
root = bpy.data.objects["marquis"]
clump = root.users_collection[0]
dummy = bpy.data.objects.new("cabin_door", None)
dummy.dff.type = "OBJ"
clump.objects.link(dummy)
dummy.parent = root
dummy.matrix_world = Matrix.Translation(HINGE)
leaf = bpy.data.objects.new("cabin_door_ok", leaf_mesh)
leaf.dff.type = "OBJ"
leaf.dff.is_frame = True  # its own frame (cabin_door_ok), not an atomic on the dummy
clump.objects.link(leaf)
leaf.parent = dummy
leaf.matrix_world = Matrix.Translation(HINGE)
bpy.context.view_layer.update()

for o in bpy.data.objects:
    o.select_set(False)
os.makedirs(FILES, exist_ok=True)
out = os.path.join(FILES, "marquis.dff")
bpy.ops.export_dff.scene(filepath=out, export_coll=True, only_selected=False, export_version="0x36003")
with open(os.path.join(VANILLA, "marquis.txd"), "rb") as a, open(os.path.join(VANILLA, "cabin.txd"), "rb") as b:
    txd = merge_txd([a.read(), b.read()])
with open(os.path.join(FILES, "marquis.txd"), "wb") as f:
    f.write(txd)

# the leaf as an object of its own (a vehicle's door has no collision, so the client hangs this one, unseen, in the
# doorway while the door is shut): the mesh in the hinge's frame, one collision box
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)
coll = bpy.data.collections.new("marquis_door")
bpy.context.scene.collection.children.link(coll)
obj = bpy.data.objects.new("marquis_door", leaf_mesh)
obj.dff.type = "OBJ"
obj.dff.day_cols = True
obj.dff.night_cols = True
coll.objects.link(obj)
box_e = bpy.data.objects.new("marquis_door_col", None)
box_e.empty_display_type = "CUBE"
box_e.location = (-LEAF_W / 2, 0.0, LEAF_H / 2)
box_e.scale = (LEAF_W / 2, LEAF_T / 2 + 0.01, LEAF_H / 2)
box_e.dff.type = "COL"
coll.objects.link(box_e)
bpy.context.view_layer.update()
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_dff.scene(filepath=os.path.join(FILES, "marquis_door.dff"), export_coll=False, only_selected=True, export_version="0x36003")
obj.select_set(False)
box_e.select_set(True)
bpy.ops.export_col.scene(filepath=os.path.join(FILES, "marquis_door.col"), export_version="3", only_selected=True)

with open(os.path.join(os.path.dirname(FILES), "cabin.lua"), "w", newline="\n") as f:
    f.write("-- Generated by tools/marquis_cabin/cabin.py; do not edit. The Marquis's walk-in door: the model it replaces, its\n")
    f.write("-- files in files/ and its door leaf as an object (files/<door>.dff/.col), hinged at x, y, z in the vehicle's frame.\n")
    f.write(f'return {{\n    model = 484,\n    component = "cabin_door",\n    door = {{ dff = "marquis_door", x = {HINGE[0]:.3f}, y = {HINGE[1]:.3f}, z = {HINGE[2]:.3f}, rz = 0.0 }},\n}}\n')
print(f"marquis_cabin: {out} ({len(door)} door faces cut, {len(steps)} step faces cut, {len(hatch)} hatch faces slid, {len(slot)} roof faces cut, {spheres_out} spheres out, {n} in, {len(boxes)} boxes)")
