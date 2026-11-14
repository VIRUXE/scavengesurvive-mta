"""des_byoffice (model 16326): the Verdant Meadows airstrip office. Its gabled ground floor (the "bottom house" in
front of the office on stilts) gets the game's own interior: in the vanilla game its door is an entry marker (DESHOUS)
into airfieldhus1 + airfieldhus2, a copy of this house built 6.17 m under it, furnished with stock props. That
interior is moved up into the house and fitted inside its walls; the white door (Gen_doorEXT03, model 1498, a locked
door in object.dat) becomes the leaf that swings.

    blender -b --python tools/house_shells/des_byoffice.py [-- --no-render]

Run tools/house_shells/prep_byoffice.py first (headless Linux renders: SHELL_ENGINE=CYCLES).

The vanilla interior is the house's plan a little larger: its south windows and its doorway line up with the house's
to the centimetre, but its bedroom wing stands 1.2 m out of the west wall and 0.6 m out of the north one, its kitchen
is in the space under the office on stilts and its ceilings run 0.2 m into the roofs. Each axis is remapped piecewise
(KX, KY, KZ: vanilla interior -> house, in the frame below) so every wall lands 0.12 m inside the house's skin, the
windows and door staying where they are; the kitchen is moved in whole, not stretched. A small loose part (a rafter,
a photo, the light switch) is moved, not squeezed, along an axis it is thin in; the tiling textures are mapped again
from the faces' planes so they keep the game's texel density.

The terrain (ne_bit_08) has a hole under the main room, whose floor the game sinks to -0.38, level with the sunken
porch and the doorway; the wing (the bedroom end) is over ground at 0.0, so its floor is raised to WING_FLOOR with
a step between them, and the furniture standing in it goes up with it. The furniture is the vanilla interior's, the
same stock models in the same layout through the same remap: it is not in the DFF but hung by the house_shell
resource as objects (build/des_byoffice_doors.json "props"), as is the door leaf; the vanilla door at the doorway is
removed ("remove").

Frame: the scripts work in "plan" coordinates, the world axes with the origin at the house's placement
(419.38, 2538.5, 15.54); the house is placed turned 90 degrees, so model x = plan y and model y = -plan x.
"""
import json
import math
import os
import shutil
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
import common  # noqa: E402
from common import BUILD, VANILLA, args  # noqa: E402

NAME = "des_byoffice"
HOUSE = Vector((419.38, 2538.5, 15.54))  # the house's only placement (rz 90)
LIFT = 6.166  # the vanilla interior's door sill (8.984) up to the house's (15.150)
INTERIOR = (("airfieldhus1", (419.383, 2540.508, 9.391)), ("airfieldhus2", (418.227, 2538.852, 11.43)))
# the furniture of the vanilla interior (model, name, world x, y, z, rz), from countn2.ipl
PROPS = (
    (2074, "cj_mlight8", 419.328, 2538.539, 12.523, 0.0),
    (1810, "cj_foldchair", 418.734, 2538.758, 8.984, 140.5),
    (2518, "cj_b_sink2", 414.844, 2535.117, 9.148, 180.0),
    (2147, "cj_kitch1_fridge", 413.969, 2538.219, 8.984, 5.0),
    (1748, "low_tv_3", 418.273, 2541.062, 9.789, 76.5),
    (1810, "cj_foldchair", 417.633, 2542.5, 8.984, 5.0),
    (1812, "low_bed_5", 416.242, 2540.336, 8.977, 0.0),
    (2115, "low_dinning_1", 418.688, 2539.594, 8.992, 90.0),
    (1810, "cj_foldchair", 418.203, 2539.906, 8.984, 88.5),
    (1738, "cj_radiator_old", 420.133, 2542.875, 9.633, 180.0),
    (1763, "low_couch_1", 421.078, 2540.812, 8.984, -85.0),
)
DOOR = (1498, 422.823, 2535.734, 15.141, 90.0)  # the house's vanilla door (Gen_doorEXT03), the leaf's model

# plan-frame remap, vanilla interior (lifted) -> house: (from, to) knots, linear between, slope 1 past the ends
KX = ((-6.31, -5.27), (-3.71, -2.37), (-1.57, -1.57), (3.47, 3.47), (3.84, 3.51))
KY = ((-3.89, -3.87), (-2.75, -2.75), (-1.25, -1.25), (0.33, -0.11), (4.57, 3.89))
KZ = ((-0.38, -0.38), (2.13, 2.13), (2.62, 2.38), (4.44, 4.20))
# the wood stove and its flue: many small loose parts across the KX knot at -3.71, moved as one block with the
# kitchen (the stove stands by the corner of the kitchen's opening, as in the game) and left at the game's height
# (the flue rises from it, runs diagonally east, turns and goes up through the ceiling; its top, above this
# house's lower roof, is cut off at FLUE_TOP, inside the roof space, as the game hides it above its ceiling)
STOVE = ((-3.75, -1.95), (-3.85, -2.80))  # x, y range of the stove's and the flue's faces (lifted plan frame)
STOVE_TEX = "banding3c_64hv"
FLUE_TOP = 3.2
# the house's two windows (model frame: wall plane x, (y0, y1), (z0, z1)): des_ntwnwin5, a painted window whose
# upper part is a 6 x 3 pane sash; that part is cut out of the house's skin and the interior's copy and glazed
WINDOWS = ((-4.01, (-1.49, -0.11), (0.91, 1.98)), (-4.01, (0.18, 1.56), (0.91, 1.98)))
INNER_WINDOW = -3.97  # the interior's window face; its room wall is at -3.87
GLASS_UV = ((0.07, 0.93), (0.40, 0.945))  # the sash's glass in des_ntwnwin5 (u, v as Blender reads them)
NICHE = (-6.31, (-2.47, -0.97), (-0.38, 2.12))  # the blank doorway in the vanilla kitchen's west wall: wall plane x, y, z
CLAMP_Y = (-3.95, 3.97)  # rafter ends stay inside the skin (y -3.99 and 4.01)
RIGID = 0.8  # a loose part thinner than this along an axis (a rafter, a photo, the wood stove) is moved, not squeezed
TILING = {"burglry_wall1", "boardwalk_la", "grge_corug1", "compound_roof1", "banding3c_64hv", "des_ghotwood1"}

# the rooms as they come out (plan frame): the main room with the kitchen west of it, the wing north of the main room
KITCHEN = (-5.27, -2.37, -3.87, -0.11)
MAIN = (-2.37, 3.47, -3.87, -0.11)
WING = (-2.37, 2.37, -0.11, 3.89)
FLOOR, WING_FLOOR, STEP_Z, STEP_D = -0.38, 0.08, -0.15, 0.30
CEIL = 2.38


def remap(v, knots):
    for (a0, b0), (a1, b1) in zip(knots, knots[1:]):
        if v <= a1 or (a1, b1) == knots[-1]:
            if v <= a0 and (a0, b0) == knots[0]:
                return b0 + (v - a0)
            if v >= a1:
                return b1 + (v - a1)
            return b0 + (v - a0) * (b1 - b0) / (a1 - a0)
    return v


def warp(p):
    y = min(max(remap(p[1], KY), CLAMP_Y[0]), CLAMP_Y[1])
    return Vector((remap(p[0], KX), y, remap(p[2], KZ)))


def plan_to_model(p):
    return Vector((p[1], -p[0], p[2]))


# windows: the Fort Carson houses' see-through pane and curtains; reveals in the interior's rafter wood; the glazing
# bars in the colour of the vanilla window's painted frame
common.CURTAINS[NAME] = "ah_curtains1"
common.TRIM = "des_ghotwood1"
common.SCALE[common.TRIM] = 1.4
common.FRAME_RGB = (150, 124, 95)
common.STACK = 0.04  # the curtains stack tight to the windows: the stove's flue rises just west of them
s = common.Shell(NAME)


def import_dff(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.dff(filepath=os.path.join(VANILLA, name + ".dff"), read_mat_split=True, remove_doubles=False, load_images=False)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH" and not o.name.startswith("2dfx")]
    for o in new:
        if o not in meshes:
            bpy.data.objects.remove(o)
    return meshes


def texture_name(mat):
    for node in mat.node_tree.nodes if mat and mat.node_tree else ():
        if node.type == "TEX_IMAGE":
            return (node.image.name if node.image else node.label or node.name).split(".")[0].lower()
    return None


def loose_parts(bm):
    """Index of the loose part (faces joined by shared vertices) of each face."""
    part, n = {}, 0
    for f in bm.faces:
        if f in part:
            continue
        stack = [f]
        part[f] = n
        while stack:
            g = stack.pop()
            for v in g.verts:
                for h in v.link_faces:
                    if h not in part:
                        part[h] = n
                        stack.append(h)
        n += 1
    return part


def add_interior(name, where):
    """The vanilla interior part `name`, placed at `where` in the world and lifted, remapped into the house's plan
    frame and appended to the shell's mesh in its model frame, textures, UVs and prelight as they are."""
    obj = import_dff(name)[0]
    to_plan = Matrix.Translation(Vector(where) + Vector((0, 0, LIFT)) - HOUSE) @ obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(to_plan)
    bm.normal_update()
    uv = bm.loops.layers.uv.active
    attrs = list(obj.data.color_attributes)
    layers = bm.loops.layers.float_color if attrs and attrs[0].data_type == "FLOAT_COLOR" else bm.loops.layers.color
    cols = [layers[a.name] for a in attrs[:2]]
    if name == "airfieldhus1":
        wall_in_blank_doorway(bm, uv, cols)
    part = loose_parts(bm)
    # where each loose part's vertices go: per axis, warped, or moved by its centre's warp when thin along it
    groups = {}
    for f in bm.faces:
        groups.setdefault(part[f], set()).update(f.verts)
    moved = {}
    for verts in groups.values():
        lo = Vector([min(v.co[i] for v in verts) for i in range(3)])
        hi = Vector([max(v.co[i] for v in verts) for i in range(3)])
        centre = (lo + hi) / 2
        shift = warp(centre) - centre
        for v in verts:
            w = warp(v.co)
            moved[v] = Vector([v.co[i] + shift[i] if hi[i] - lo[i] < RIGID else w[i] for i in range(3)])
    stove = Vector((KX[1][1] - KX[1][0], 0.0, 0.0))
    (sx0, sx1), (sy0, sy1) = STOVE
    for f in bm.faces:
        c = f.calc_center_median()
        if sx0 < c.x < sx1 and sy0 < c.y < sy1 and texture_name(obj.data.materials[f.material_index]) == STOVE_TEX:
            for v in f.verts:
                p = v.co + stove
                p.z = min(p.z, FLUE_TOP)
                moved[v] = p
    added = 0
    for f in bm.faces:
        tex = texture_name(obj.data.materials[f.material_index])
        if tex is None or tex == "black32":
            continue  # black32: the dark passage out of the vanilla interior's door, which the house's door replaces
        old = [v.co.copy() for v in f.verts]
        new = [moved[v] for v in f.verts]
        uvs = [l[uv].uv.copy() for l in f.loops]
        if tex in TILING:
            uvs = refit(old, new, uvs, f.normal)
        face = s.bm.faces.new([s.bm.verts.new(plan_to_model(p)) for p in new])
        face.material_index = s.mat(tex)
        for loop, src, c in zip(face.loops, f.loops, uvs):
            loop[s.uv].uv = c
            day = src[cols[0]] if cols else common.IN_DAY
            night = src[cols[1]] if len(cols) > 1 else day
            loop[s.day], loop[s.night] = tuple(day), tuple(night)
        added += 1
    bm.free()
    bpy.data.objects.remove(obj)
    print(f"interior: {name} {added} faces")


def wall_in_blank_doorway(bm, uv, cols):
    """The vanilla kitchen's west wall has a blank doorway (NICHE: a door-sized recess 0.3 deep, no door, nothing
    behind it). Its faces go and the wall runs on flush over it, mapped and lit like the wall face beside it."""
    x_wall, (y0, y1), (z0, z1) = NICHE
    dead = [f for f in bm.faces if all(v.co.x < x_wall + 0.01 for v in f.verts) and all(y0 - 0.01 < v.co.y < y1 + 0.01 for v in f.verts)]
    ref = next(
        f for f in bm.faces
        if f not in dead and f.normal.x > 0.9 and abs(f.calc_center_median().x - x_wall) < 0.01 and f.calc_center_median().z < z1
    )
    rows = [(l.vert.co.y, l.vert.co.z, 1.0) for l in ref.loops]
    inv = Matrix([[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)]).inverted()
    coef = [inv @ Vector([sum(r[i] * l[uv].uv[k] for r, l in zip(rows, ref.loops)) for i in range(3)]) for k in range(2)]
    colours = [tuple(ref.loops[0][c]) for c in cols]
    mat = ref.material_index
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    f = bm.faces.new([bm.verts.new(v) for v in ((x_wall, y1, z0), (x_wall, y0, z0), (x_wall, y0, z1), (x_wall, y1, z1))])
    f.material_index = mat
    f.normal_update()
    for loop in f.loops:
        co = loop.vert.co
        loop[uv].uv = (coef[0][0] * co.y + coef[0][1] * co.z + coef[0][2], coef[1][0] * co.y + coef[1][1] * co.z + coef[1][2])
        for c, value in zip(cols, colours):
            loop[c] = value
    print(f"blank doorway: {len(dead)} faces walled over")


def refit(old, new, uvs, normal):
    """UVs of a planar face moved from `old` to `new`, keeping the texture's scale: the affine map from the face's
    plane to its UVs is fitted on the old corners and applied to the new ones."""
    drop = max(range(3), key=lambda i: abs(normal[i]))
    a, b = [i for i in range(3) if i != drop]
    rows = [(p[a], p[b], 1.0) for p in old]
    # least squares for u and v over the corners (3x3 normal equations)
    ata = Matrix([[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)])
    if abs(ata.determinant()) < 1e-9:
        return uvs
    inv = ata.inverted()
    out = []
    coef = []
    for k in range(2):
        atb = Vector([sum(r[i] * c[k] for r, c in zip(rows, uvs)) for i in range(3)])
        coef.append(inv @ atb)
    for p in new:
        out.append(Vector((coef[0][0] * p[a] + coef[0][1] * p[b] + coef[0][2], coef[1][0] * p[a] + coef[1][1] * p[b] + coef[1][2])))
    return out


# the vanilla house's fake vestibule: a dark box (ventc64) 3 m deep behind the doorway, where the game showed only
# the door and the entry marker
vent = s.mat("ventc64")
fake = [f for f in s.bm.faces if f.material_index == vent and -0.1 > f.calc_center_median().x > -3.9 and f.calc_center_median().z < 2.2]
bmesh.ops.delete(s.bm, geom=fake, context="FACES")
print(f"vestibule: {len(fake)} faces removed")

for name, where in INTERIOR:
    add_interior(name, where)


def plan_face(verts, tex, uv_scale=None, uvs=None):
    """A face given in plan coordinates, inside light, planar UVs at `uv_scale` metres per repeat."""
    s.face([plan_to_model(v) for v in verts], s.mat(tex), uvs=uvs, scale=uv_scale)


# glazed windows with curtains: the sash part of each painted window is cut through the house's skin and the
# interior's window face, found from the face's own UVs
win_mat = s.mat("des_ntwnwin5")
for x_wall, (y0w, y1w), (z0w, z1w) in WINDOWS:
    face = next(
        f for f in s.bm.faces
        if f.material_index == win_mat and abs(f.calc_center_median().x - x_wall) < 0.02 and y0w < f.calc_center_median().y < y1w
    )
    loops = list(face.loops)

    def fit(axis, k):
        """Coordinate `axis` (1: y, 2: z) as a linear function of UV component k over the face's corners."""
        pts = [(l[s.uv].uv[k], l.vert.co[axis]) for l in loops]
        a = max(pts)
        b = min(pts)
        return lambda t: b[1] + (t - b[0]) * (a[1] - b[1]) / (a[0] - b[0])

    ys = sorted(fit(1, 0)(t) for t in GLASS_UV[0])
    zs = sorted(fit(2, 1)(t) for t in GLASS_UV[1])
    frame = [("v", k / 6) for k in range(1, 6)] + [("h", 1 / 3), ("h", 2 / 3)]
    o = s.opening("window", "x", -1, ys[0], ys[1], zs[0], zs[1], INNER_WINDOW, outer=x_wall, frame=frame, reveal=common.TRIM)
    # the curtains hang from the room's wall across the whole painted window
    o.inner, o.u0, o.u1, o.z0, o.z1 = -3.87, y0w, y1w, z0w, z1w
    print(f"window: glass y {ys[0]:.2f}..{ys[1]:.2f} z {zs[0]:.2f}..{zs[1]:.2f}")

# the wing's raised floor and the step down into the main room, in the vanilla floor's boards
s.bm.faces.ensure_lookup_table()
floor_mat = s.mat("boardwalk_la")
dead = []
for f in s.bm.faces:
    c = f.calc_center_median()
    # model frame: plan y = -x... (plan x = -model y, plan y = model x)
    if f.material_index == floor_mat and abs(c.z - FLOOR) < 0.02 and c.x > WING[2] + 0.01:
        dead.append(f)
# the vanilla floor's board mapping (model x, y -> UV), so the new floor's boards run the same way
ref = dead[0]
FLOOR_UV = refit([l.vert.co for l in ref.loops], [l.vert.co for l in ref.loops], [l[s.uv].uv.copy() for l in ref.loops], ref.normal)
coef_rows = [(l.vert.co.x, l.vert.co.y, 1.0) for l in ref.loops]
ata = Matrix([[sum(r[i] * r[j] for r in coef_rows) for j in range(3)] for i in range(3)]).inverted()
BOARDS = [ata @ Vector([sum(r[i] * l[s.uv].uv[k] for r, l in zip(coef_rows, ref.loops)) for i in range(3)]) for k in range(2)]


def board_uvs(verts):
    """UVs of plan-frame floor corners on the vanilla floor's boards."""
    out = []
    for v in verts:
        m = plan_to_model(v)
        out.append(Vector([BOARDS[k][0] * m.x + BOARDS[k][1] * m.y + BOARDS[k][2] for k in range(2)]))
    return out


bmesh.ops.delete(s.bm, geom=dead, context="FACES")
x0, x1, y0, y1 = WING
B = 2.0  # metres per repeat of boardwalk_la, as the vanilla floor
for q in ([(x0, y0, WING_FLOOR), (x1, y0, WING_FLOOR), (x1, y1, WING_FLOOR), (x0, y1, WING_FLOOR)], [(x0, y0 - STEP_D, STEP_Z), (x1, y0 - STEP_D, STEP_Z), (x1, y0, STEP_Z), (x0, y0, STEP_Z)]):
    plan_face(q, "boardwalk_la", uvs=board_uvs(q))
plan_face([(x0, y0, STEP_Z), (x1, y0, STEP_Z), (x1, y0, WING_FLOOR), (x0, y0, WING_FLOOR)], "boardwalk_la", B)  # risers face -y
plan_face([(x0, y0 - STEP_D, FLOOR), (x1, y0 - STEP_D, FLOOR), (x1, y0 - STEP_D, STEP_Z), (x0, y0 - STEP_D, STEP_Z)], "boardwalk_la", B)
for x, d in ((x0, -1), (x1, 1)):  # the step's ends, seen from the kitchen and the doorway end
    q = [(x, y0 - STEP_D, FLOOR), (x, y0, FLOOR), (x, y0, WING_FLOOR), (x, y0 - STEP_D, WING_FLOOR)]
    plan_face(list(reversed(q)) if d < 0 else q, "burglry_wall1", 2.0)
# the lintel over the doorway, between the interior's reveal and the house's
plan_face([(3.47, -2.75, 2.12), (3.47, -1.25, 2.12), (3.61, -1.25, 2.12), (3.61, -2.75, 2.12)], "burglry_wall1", 2.0)

# collision: the vanilla ground floor was solid; it becomes floors, walls between the rooms and the skin, a ceiling
common_drop = (
    (0.01, -2.51, 0.01, 4.01, 2.49, 2.61),
    (-3.99, -3.61, 2.11, 0.01, 2.49, 2.61),
    (-1.25, -3.61, -0.39, 0.01, 0.77, 2.11),
    (-3.99, -3.61, -0.39, -2.75, 0.81, 2.11),
    (-3.99, 0.57, -0.01, 0.01, 7.49, 2.59),
)
s.cols = [b for b in s.cols if not any(all(abs(b[i] - k[i]) < 0.02 for i in range(6)) for k in common_drop)]
s.keep_col_mesh()  # roofs, porch, steps and stairs; inside the rooms it holds only the doorway's floor


def plan_box(lo, hi):
    a, b = plan_to_model(lo), plan_to_model(hi)
    s.col_box([min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)])


plan_box((-7.49, -3.99, FLOOR - 0.3), (3.61, -0.11, FLOOR))  # main room and kitchen floor
plan_box((-2.49, -0.11, FLOOR - 0.3), (2.51, 4.01, WING_FLOOR))  # wing floor
plan_box((x0, y0 - STEP_D, FLOOR), (x1, y0, STEP_Z))  # step
plan_box((-7.49, -3.99, FLOOR), (3.61, -3.87, CEIL))  # south wall
plan_box((-7.49, -0.11, FLOOR), (-2.37, 0.01, CEIL))  # kitchen north wall
plan_box((2.37, -0.11, FLOOR), (3.61, 0.01, CEIL))  # main room north wall, east of the wing
plan_box((-2.49, -0.11, WING_FLOOR), (-2.37, 4.01, CEIL))  # wing west wall
plan_box((2.37, -0.11, WING_FLOOR), (2.51, 4.01, CEIL))  # wing east wall
plan_box((-2.49, 3.89, WING_FLOOR), (2.51, 4.01, CEIL))  # wing north wall
plan_box((-7.49, -3.99, FLOOR), (KITCHEN[0], 0.01, CEIL))  # kitchen west wall and the dead space behind it
plan_box((3.47, -3.99, FLOOR), (3.61, -2.75, CEIL))  # door wall, either side of the doorway
plan_box((3.47, -1.25, FLOOR), (3.61, 0.01, CEIL))
plan_box((3.47, -2.75, 2.12), (3.61, -1.25, CEIL))
plan_box((-7.49, -3.99, CEIL), (3.61, 0.01, 2.61))  # ceilings, up to the eaves and the floor above
plan_box((-2.49, 0.01, CEIL), (2.51, 4.01, 2.61))
s.rooms = [
    [round(v, 4) for v in (KITCHEN[0], MAIN[1], -3.87, -0.11, FLOOR, CEIL)],
    [round(v, 4) for v in (WING[0], WING[1], WING[2], WING[3], WING_FLOOR, CEIL)],
]
# rooms in the model frame for tools/shell_rooms.json (loot points)
s.rooms = [[r[2], r[3], -r[1], -r[0], r[4], r[5]] for r in s.rooms]


# props. The kitchen's and the main room's stand where the remap puts them. The wing's keep the game's layout scaled
# to the narrower wing (WING_SRC -> WING, by their footprint's centre), the dining set (table, TV and the chairs at
# it) moved as one so its chairs stay at the table; the set stands clear of the step. Then each footprint is pushed
# inside its room.
WING_SRC = (-3.71, 2.37, 0.33, 4.57)
DINING = {"low_dinning_1", "low_tv_3"}
DINING_CHAIRS = ((418.734, 2538.758), (418.203, 2539.906))  # the two chairs the game sets at the table


def footprint(name, rz):
    """Bounding box of prop `name` turned `rz` about its pivot, and its imported objects."""
    obj = import_dff(name)
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    rot = Matrix.Rotation(math.radians(rz), 4, "Z")
    for o in obj:
        for c in o.bound_box:
            w = rot @ (o.matrix_world @ Vector(c))
            lo = Vector([min(lo[i], w[i]) for i in range(3)])
            hi = Vector([max(hi[i], w[i]) for i in range(3)])
    return obj, lo, hi


def wing_map(p):
    return Vector((
        WING[0] + (p.x - WING_SRC[0]) * (WING[1] - WING[0]) / (WING_SRC[1] - WING_SRC[0]),
        WING[2] + (p.y - WING_SRC[2]) * (WING[3] - WING[2]) / (WING_SRC[3] - WING_SRC[2]),
        p.z + WING_FLOOR - FLOOR,
    ))


def push_inside(q, lo, hi, room):
    for i, (a, b) in enumerate(((room[0], room[1]), (room[2], room[3]))):
        if q[i] + lo[i] < a + 0.03:
            q[i] = a + 0.03 - lo[i]
        if q[i] + hi[i] > b - 0.03:
            q[i] = b - 0.03 - hi[i]


items = []
for model, name, x, y, z, rz in PROPS:
    obj, lo, hi = footprint(name, rz)
    src = Vector((x, y, z)) + Vector((0, 0, LIFT)) - HOUSE
    centre = src + (lo + hi) / 2
    dining = name in DINING or any(abs(x - cx) < 0.01 and abs(y - cy) < 0.01 for cx, cy in DINING_CHAIRS)
    wing = dining or centre.y > WING_SRC[2]
    items.append({"model": model, "name": name, "src": src, "centre": centre, "lo": lo, "hi": hi, "rz": rz, "objects": obj, "dining": dining, "wing": wing})

table = next(i for i in items if i["name"] == "low_dinning_1")
shift = wing_map(table["centre"]) - table["centre"]
group_lo = min(i["src"].y + shift.y + i["lo"].y for i in items if i["dining"])
if group_lo < WING[2] + 0.08:
    shift.y += WING[2] + 0.08 - group_lo  # the chair at the table's end stays on the wing's floor, off the step
for i in items:
    if i["dining"]:
        q = i["src"] + shift
        room = WING
    elif i["wing"]:
        q = wing_map(i["centre"]) - (i["lo"] + i["hi"]) / 2
        room = WING
    else:
        q = warp(i["src"])
        q.x = remap(i["src"].x, KX)
        room = KITCHEN if q.x < KITCHEN[1] else MAIN
    push_inside(q, i["lo"], i["hi"], room)
    i["q"] = q

# the narrower wing brings the free-standing pieces closer: one that comes nearer another than the game had them
# (the chair by the foot of the bed) keeps the game's gap, moved off along x away from the other
CLEAR = 0.35
for i in items:
    if not i["wing"] or i["dining"]:
        continue
    for j in items:
        if j is i or not j["wing"]:
            continue
        a0, a1 = i["q"].x + i["lo"].x, i["q"].x + i["hi"].x
        b0, b1 = j["q"].x + j["lo"].x, j["q"].x + j["hi"].x
        ya = (i["q"].y + i["lo"].y, i["q"].y + i["hi"].y)
        yb = (j["q"].y + j["lo"].y, j["q"].y + j["hi"].y)
        if ya[1] < yb[0] or yb[1] < ya[0] or a0 > b1 + CLEAR or b0 > a1 + CLEAR:
            continue
        if i["q"].x >= j["q"].x:
            i["q"].x += b1 + CLEAR - a0
        else:
            i["q"].x -= a1 + CLEAR - b0
        push_inside(i["q"], i["lo"], i["hi"], WING)

props = []
for i in items:
    q, rz = i["q"], i["rz"]
    for o in i["objects"]:
        o.matrix_world = Matrix.Translation(plan_to_model(q)) @ Matrix.Rotation(math.radians(rz - 90), 4, "Z") @ o.matrix_world
        o.name = "prop_" + i["name"]
    props.append({"model": i["model"], "pos": [round(v, 3) for v in plan_to_model(q)], "rz": round((rz - 90) % 360, 1), "objects": i["objects"]})
    print(f"prop: {i['name']} plan {tuple(round(v, 2) for v in q)} rz {rz}")

# the leaf: the vanilla door, hinged where the game hangs it
door_world = Vector(DOOR[1:4]) - HOUSE
hinge = plan_to_model(door_world)
door_rz = (DOOR[4] - 90) % 360
leaf = import_dff("gen_doorext03")
for o in leaf:
    o.name = "leaf"
    print("leaf bbox", [tuple(round(v, 2) for v in o.matrix_world @ Vector(c)) for c in (o.bound_box[0], o.bound_box[6])])

if "--no-render" not in args():
    s._finish_mesh()
    for p in props:
        for o in p["objects"]:
            for m in o.data.materials:
                s._hook_texture(m)
    for o in leaf:
        for m in o.data.materials:
            s._hook_texture(m)
    for i, at in enumerate(((0.5, -2.0, 1.9), (0.0, 2.0, 2.2), (-3.8, -2.0, 1.9))):
        lamp = bpy.data.objects.new(f"room_lamp{i}", bpy.data.lights.new(f"room_lamp{i}", "POINT"))
        lamp.data.energy = 120
        lamp.location = plan_to_model(at)
        bpy.context.scene.collection.objects.link(lamp)

    def set_leaf(angle):
        for o in leaf:
            o.matrix_world = Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(door_rz + angle), 4, "Z")

    set_leaf(0)
    # a first tiny render makes the scene's sun, sky and ground; the ground then goes under the sunken floor
    s.render("_setup", (0, 0, 10), (0, 0.01, 0), size=(16, 10))
    bpy.data.objects["ground"].location.z = FLOOR - 0.05
    for name, eye, at, lens, ang in (
        ("outside_player", (12.0, -15.5, 2.6), (1.0, -1.0, 1.4), 24, 0),  # where the screenshot was taken
        ("door_open", (8.0, -4.5, 1.4), (3.5, -2.0, 0.6), 24, 100),
        ("inside_from_door", (3.2, -2.0, 1.3), (-3.0, 1.5, 0.5), 16, 100),
        ("inside_wing", (1.9, 3.6, 1.7), (-2.0, -2.0, 0.4), 16, 100),
        ("inside_kitchen", (0.5, -1.0, 1.4), (-5.0, -2.5, 0.6), 16, 100),
        ("inside_bed", (2.0, 0.5, 1.7), (-2.3, 2.5, 0.4), 16, 100),
        ("windows_outside", (0.6, -8.0, 1.7), (0.0, -4.0, 1.3), 24, 0),
        ("windows_inside", (0.3, -0.6, 1.5), (-0.6, -4.0, 1.1), 18, 100),
        ("stove", (-0.3, -1.6, 1.5), (-2.4, -3.6, 1.0), 20, 100),
    ):  # plan frame
        if os.environ.get("SHELL_VIEWS") and name not in os.environ["SHELL_VIEWS"].split(","):
            continue
        set_leaf(ang)
        bpy.context.scene.render.engine = os.environ.get("SHELL_ENGINE", "CYCLES")
        s.render(name, plan_to_model(eye), plan_to_model(at), lens=lens, size=(1280, 800))

for p in props:
    for o in p["objects"]:
        bpy.data.objects.remove(o)
for o in leaf:
    bpy.data.objects.remove(o)
s.export()
for ext in ("dff", "col"):  # the leaf is the vanilla door itself
    shutil.copyfile(os.path.join(VANILLA, f"gen_doorext03.{ext}"), os.path.join(common.OUT, f"{NAME}_door.{ext}"))
with open(os.path.join(BUILD, NAME + "_doors.json"), "w") as f:
    json.dump(
        {
            "doors": [{"hinge": [round(v, 4) for v in hinge], "rz": round(door_rz, 1)}],
            "remove": [{"model": DOOR[0], "pos": [round(v, 4) for v in hinge], "radius": 0.5}],
            "props": [{"model": p["model"], "pos": p["pos"], "rz": p["rz"]} for p in props],
        },
        f,
        indent=2,
    )
