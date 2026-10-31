"""The towable Airstream: the medium Airstream shell (sm_airstrm_med_.py's output) as a trailer vehicle replacing the
unused farm trailer, model 610. The utility trailer (utiltr1, model 611, extracted by prep.py) gives the frame
hierarchy the game wants of a trailer (chassis, four wheel dummies, hookup, misc_a); the shell is the body, its door
leaf the vehicle's front-left door, its step a frame of its own (the vehicles client hides it while towed), a
jockey leg the game lowers by itself when unhitched, and its collision boxes (for peds inside) plus underbody spheres
the collision.

    blender -b --python tools/trailer_shells/towable.py

Run it after the shell's own script whenever the shell changes. Writes into the vehicles resource: files/airstream_tow.dff,
its textures (files/airstream_tow.txd, the ones it uses out of house_shell's trailers.txd), its door leaf as an object
of its own (files/airstream_tow_door.dff/.col, the shell's leaf: a vehicle's door has no collision, so the client hangs
this one, unseen, in the doorway while the door is shut) and towable.lua (model, files, wheel size and the door's
hinge for the client).

What the game does with a trailer vehicle, learned in game (2026-10-31):
- the hookup dummy is where the trailer meets the towing car's ball, which the game hangs 0.44 m behind the car's
  body; it sits 0.35 m behind the tow bar's tip, so the bar reaches the car's bumper;
- front and rear wheel pairs must not share a spot: a zero wheelbase turns the trailer to heading 0 and drops it the
  moment it is hitched (the rear pair is 0.10 m behind and hidden on the client);
- the wheel is drawn 10 % wider than its mesh: the wheel sits inboard (WHEEL_X) so the skin hides its top;
- vehicles are drawn double-sided: downward faces under the floor show inside the room (the axle trough is cut);
- misc_a moves straight along z, never above its frame's own height: towed it stays there, standing it drops to the
  ground under it over ~10 s, so its origin is the jockey wheel's bottom in the stowed position;
- the game tests a vehicle's spheres, not its boxes, against buildings: the boxes are for peds, the spheres carry it.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BUILD, OUT, ROOT, VANILLA  # noqa: E402

sys.path.insert(0, ROOT)
from tools.extract_samp_models import trim_txd  # noqa: E402

SHELL = "sm_airstrm_med_"
NAME = "airstream_tow"
MODEL = 610  # farmtr1: a trailer the game never places and the port never spawns as itself
Z0 = 0.90  # shell z that becomes the vehicle origin's height
HITCH_REACH = -0.35  # hookup this far past the tow bar's tip (behind it): the bar reaches the towing car's bumper
WHEEL_X = 0.98  # wheel centres: inboard of the painted hubs, so the game's 10 % wider wheel stays behind the skin
WHEEL_WIDTH, WHEEL_SIDES = 0.24, 16
VEHICLES = os.path.join(ROOT, "resources", "[scavengesurvive]", "vehicles")
FILES = os.path.join(VEHICLES, "files")
LUA = os.path.join(VEHICLES, "towable.lua")

meta = json.load(open(os.path.join(BUILD, SHELL + ".json")))
down = Matrix.Translation((0, 0, -Z0))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module="DragonFF")


def fix_textures(mesh):
    """load_images=False leaves texture nodes empty; the exporter takes the texture name from the node's image."""
    for mat in mesh.materials:
        for node in mat.node_tree.nodes if mat and mat.node_tree else ():
            if node.type == "TEX_IMAGE" and node.image is None:
                name = (node.label or node.name).split(".")[0]
                node.image = bpy.data.images.get(name) or bpy.data.images.new(name, 4, 4)


def texture(mesh, index):
    mat = mesh.materials[index]
    return next((n.image.name for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), "") if mat and mat.node_tree else ""


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def load_mesh(path, transform):
    bpy.ops.import_scene.dff(filepath=path, read_mat_split=True, remove_doubles=False, load_images=False)
    obj = next(o for o in bpy.data.objects if o.type == "MESH")
    fix_textures(obj.data)
    mesh = obj.data.copy()
    mesh.transform(transform @ obj.matrix_world)
    clear()
    return mesh


def split(mesh, keep, name):
    """Moves the faces `keep(face, mesh)` picks out of `mesh` into a new mesh of their own."""
    part = mesh.copy()
    part.name = name
    for m, want in ((mesh, False), (part, True)):
        bm = bmesh.new()
        bm.from_mesh(m)
        dead = [f for f in bm.faces if bool(keep(f, mesh)) != want]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.to_mesh(m)
        bm.free()
    return part


body = load_mesh(os.path.join(OUT, SHELL + ".dff"), down)
tip = [v.co for v in body.vertices if v.co.y > 4.6]
hook = Vector((0.0, max(v.y for v in tip) + HITCH_REACH, (min(v.z for v in tip) + max(v.z for v in tip)) / 2))

# the painted wheels come off the body; their +X hub and size give a round wheel of our own (the paint's hexagon fans
# its texture from a rim vertex, so the hub image tore across the middle up close)
wheels = split(body, lambda f, m: texture(m, f.material_index) == "trail_wheel", "wheels")
right = [v.co for v in wheels.vertices if v.co.x > 0]
lo = Vector([min(v[i] for v in right) for i in range(3)])
hi = Vector([max(v[i] for v in right) for i in range(3)])
hub = (lo + hi) / 2
diameter = hi.z - lo.z


def round_wheel(radius, width, sides, material):
    """A closed cylinder along X: both faces show the whole texture (the wheel image) centred, the tread a thin
    strip of its dark tyre edge."""
    me = bpy.data.meshes.new("wheel")
    me.materials.append(material)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    ring = [(math.cos(2 * math.pi * i / sides), math.sin(2 * math.pi * i / sides)) for i in range(sides)]
    for x, rev in ((width / 2, False), (-width / 2, True)):
        vs = [bm.verts.new((x, radius * c, radius * s)) for c, s in ring]
        f = bm.faces.new(list(reversed(vs)) if rev else vs)
        for loop in f.loops:
            c, s = loop.vert.co.y / radius, loop.vert.co.z / radius
            loop[uv].uv = (0.5 + 0.49 * c, -(0.5 - 0.49 * s))
    for i in range(sides):
        j = (i + 1) % sides
        (ci, si), (cj, sj) = ring[i], ring[j]
        vs = [bm.verts.new((width / 2, radius * ci, radius * si)), bm.verts.new((-width / 2, radius * ci, radius * si)), bm.verts.new((-width / 2, radius * cj, radius * sj)), bm.verts.new((width / 2, radius * cj, radius * sj))]
        f = bm.faces.new(vs)
        for loop, c in zip(f.loops, [(0.45, -0.02), (0.45, -0.05), (0.55, -0.05), (0.55, -0.02)]):
            loop[uv].uv = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return me


wheel_mat = next(m for m in wheels.materials if m and "trail_wheel" in [n.image.name for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image])
wheel = round_wheel(diameter / 2, WHEEL_WIDTH, WHEEL_SIDES, wheel_mat)

# the jockey leg: misc_a is the moving part (the jockey wheel, its fork and the inner tube), its origin the wheel's
# bottom at the stowed height; the sleeve, its clamp and the crank stay on the body. Side-mounted beside the tongue (it
# ends x 0.08..0.12 here) so the stowed wheel sits level with the tongue: hitched behind a Bobcat the ground is only
# ~0.25 m below the tongue. The paint's post comes off the body (its wheel went with the painted wheels above).
JOCKEY = Vector((0.19, 4.64, -0.46))  # misc_a origin: wheel bottom stowed, level with the tongue's underside (-0.44)
SLEEVE_HALF, SLEEVE_BOT, SLEEVE_TOP = 0.035, -0.25, 0.18  # the tongue is z -0.44..-0.30; the tanks end y 4.53
JW_R, JW_W, TUBE_HALF, TUBE_LEN = 0.08, 0.05, 0.025, 0.42
post = split(body, lambda f, m: texture(m, f.material_index) == "trail_wall1" and (c := f.calc_center_median()).y > 4.55 and abs(c.x) < 0.12, "post")
post_mat = post.materials[post.polygons[0].material_index]


def add_box(bm, lo, hi, mat_index, rgba=None):
    """An axis-aligned box into `bm`, outward faces, planar UVs (0.6 m a tile), optional vertex colour."""
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    cols = list(bm.loops.layers.color.values()) + list(bm.loops.layers.float_color.values())
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    quads = (
        ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
        ([(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], (0, 0, -1)),
        ([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0)),
        ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
        ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        ([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], (0, 1, 0)),
    )
    for vs, want in quads:
        vs = [Vector(v) for v in vs]
        if (vs[1] - vs[0]).cross(vs[2] - vs[1]).dot(Vector(want)) < 0:
            vs.reverse()
        f = bm.faces.new([bm.verts.new(v) for v in vs])
        f.material_index = mat_index
        axes = [i for i in range(3) if want[i] == 0]
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co[axes[0]] / 0.6, loop.vert.co[axes[1]] / 0.6)
            for c in cols:
                loop[c] = rgba or (0.60, 0.56, 0.50, 1.0)


# the sleeve through the tongue and the crank on top, on the body
bm = bmesh.new()
bm.from_mesh(body)
pm = list(body.materials).index(post_mat)
jx, jy = JOCKEY.x, JOCKEY.y
add_box(bm, (jx - SLEEVE_HALF, jy - SLEEVE_HALF, SLEEVE_BOT), (jx + SLEEVE_HALF, jy + SLEEVE_HALF, SLEEVE_TOP), pm)
add_box(bm, (0.09, jy - 0.045, -0.43), (jx - SLEEVE_HALF, jy + 0.045, -0.31), pm)  # clamp to the tongue
add_box(bm, (jx - 0.045, jy - 0.045, -0.31), (jx + 0.045, jy + 0.045, -0.25), pm)  # clamp collar, sleeve foot
add_box(bm, (jx - 0.045, jy - 0.045, SLEEVE_TOP), (jx + 0.045, jy + 0.045, SLEEVE_TOP + 0.03), pm)
add_box(bm, (jx - 0.012, jy - 0.012, SLEEVE_TOP + 0.03), (jx + 0.012, jy + 0.012, SLEEVE_TOP + 0.06), pm)
add_box(bm, (jx - 0.012, jy - 0.012, SLEEVE_TOP + 0.06), (jx + 0.012, jy + 0.15, SLEEVE_TOP + 0.08), pm)  # crank arm, forward
add_box(bm, (jx - 0.015, jy + 0.13, SLEEVE_TOP + 0.08), (jx + 0.015, jy + 0.16, SLEEVE_TOP + 0.15), pm)  # handle
bm.normal_update()
bm.to_mesh(body)
bm.free()

# misc_a: the jockey wheel (axle along x), its fork and the inner tube, origin at the wheel's bottom
leg = bpy.data.meshes.new("misc_a")
leg.materials.append(wheel_mat)
leg.materials.append(post_mat)
bm = bmesh.new()
bm.from_mesh(round_wheel(JW_R, JW_W, 12, wheel_mat))
bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, JW_R))
fork_top = 2 * JW_R + 0.03
for sx in (-1, 1):
    add_box(bm, (sx * (JW_W / 2 + 0.005) - 0.006, -0.025, JW_R - 0.01), (sx * (JW_W / 2 + 0.005) + 0.006, 0.025, fork_top), 1)
add_box(bm, (-JW_W / 2 - 0.011, -0.03, 2 * JW_R + 0.005), (JW_W / 2 + 0.011, 0.03, fork_top), 1)
add_box(bm, (-0.006 - JW_W / 2, -0.008, JW_R - 0.008), (JW_W / 2 + 0.006, 0.008, JW_R + 0.008), 1)
add_box(bm, (-TUBE_HALF, -TUBE_HALF, fork_top), (TUBE_HALF, TUBE_HALF, fork_top + TUBE_LEN), 1)
bm.normal_update()
bm.to_mesh(leg)
bm.free()

# the step under the door: a frame of its own, which the client hides while the trailer is towed
d0, d1 = meta["openings"][0]["u"]
step = split(body, lambda f, m: (c := f.calc_center_median()).x < -1.2 and d0 - 0.1 < c.y < d1 + 0.1 and c.z < 0.3 - Z0, "step")

# the wheel wells: the shell's humps (x 0.86..1.06, up to z 0.95) fit the painted wheels; the game's wheel is 10 %
# wider and rides up on its springs, so it came through them: bigger humps over the old ones, in the same trim
HUMP = ((0.78, -0.47, 0.45 - Z0), (1.06, 0.50, 1.10 - Z0))


def add_humps(mesh, lo, hi):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # the material of the old hump's top (a lookup by texture name found a material the game drew pale)
    trim = next(f.material_index for f in bm.faces if f.normal.z > 0.9 and 0.87 < f.calc_center_median().x < 1.05 and abs(f.calc_center_median().z - (0.95 - Z0)) < 0.02)
    uv = bm.loops.layers.uv.active
    cols = list(bm.loops.layers.color.values()) + list(bm.loops.layers.float_color.values())
    for side in (1, -1):
        x0, x1 = side * lo[0], side * hi[0]
        (y0, z0), (y1, z1) = (lo[1], lo[2]), (hi[1], hi[2])
        quads = [
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-side, 0, 0)),
            ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
            ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
        ]
        for vs, want in quads:
            vs = [Vector(v) for v in vs]
            if (vs[1] - vs[0]).cross(vs[2] - vs[1]).dot(Vector(want)) < 0:
                vs.reverse()
            f = bm.faces.new([bm.verts.new(v) for v in vs])
            f.material_index = trim
            axes = [i for i in range(3) if abs(want[i]) < 0.5]
            for loop in f.loops:
                loop[uv].uv = (loop.vert.co[axes[0]] / 0.6, loop.vert.co[axes[1]] / 0.6)
                for c in cols:
                    loop[c] = (0.60, 0.56, 0.50, 1.0)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()


add_humps(body, *HUMP)

# the vanilla underside's trough over the axle rises through the floor (z 0.49..0.65): a building culls its downward
# faces from inside, but the game draws vehicles double-sided, so it stood in the room
split(body, lambda f, m: texture(m, f.material_index) == "trail_wall1" and abs((c := f.calc_center_median()).x) < 0.7 and abs(c.y) < 0.6 and -0.46 < c.z < -0.2, "trough")

# the door leaf: in its frame at the hinge, turned as house_shell places it
door = meta["door"]
hinge = Vector(door["hinge"]) - Vector((0, 0, Z0))
leaf = load_mesh(os.path.join(OUT, SHELL + "_door.dff"), Matrix.Rotation(math.radians(door["rz"]), 4, "Z"))

# the shell's collision boxes (peds only: the game never tests a vehicle's boxes against the world), less the vanilla
# wheels' (the wheels moved), plus the bigger humps'
bpy.ops.import_scene.dff(filepath=os.path.join(OUT, SHELL + ".col"))
boxes = []
for o in list(bpy.data.objects):
    if o.type == "EMPTY" and o.empty_display_type == "CUBE":
        c, s = o.matrix_world.translation, o.matrix_world.to_scale()
        cz = c.z - Z0
        if abs(c.x) > 1.0 and abs(c.y - hub.y) < 0.3 and -0.65 < cz < -0.3:
            continue
        boxes.append((c.x, c.y, cz, s.x, s.y, s.z))
(hx0, hy0, hz0), (hx1, hy1, hz1) = HUMP
for side in (1, -1):
    boxes.append((side * (hx0 + hx1) / 2, (hy0 + hy1) / 2, (hz0 + hz1) / 2, (hx1 - hx0) / 2, (hy1 - hy0) / 2, (hz1 - hz0) / 2))
clear()

# the template: utiltr1's frames with the parts above
bpy.ops.import_scene.dff(filepath=os.path.join(VANILLA, "utiltr1.dff"), read_mat_split=True, remove_doubles=False, load_images=False)
objs = {o.name: o for o in bpy.data.objects}
col_coll = None
for o in list(bpy.data.objects):
    if o.dff.type in ("COL", "SHA"):
        col_coll = o.users_collection[0]
        bpy.data.objects.remove(o)
clump = objs["chassis"].users_collection[0]
for name in ("chassis", "chassis_vlo"):
    objs[name].data = body
objs["wheel"].data = wheel
objs["misc_a"].data = leg  # the frame the game moves up and down (and wants of a trailer to hitch it)
objs["misc_a"].matrix_world = Matrix.Translation(JOCKEY)
step_obj = bpy.data.objects.new("step", step)
step_obj.dff.type = "OBJ"
step_obj.dff.is_frame = True
clump.objects.link(step_obj)
step_obj.parent = objs["chassis_dummy"]
step_obj.matrix_world = Matrix.Identity(4)
# the rear pair 0.10 m behind the front pair (the client hides it): a zero wheelbase drops the trailer when hitched
for name, sx, dy in (("wheel_rf_dummy", 1, 0.05), ("wheel_lf_dummy", -1, 0.05), ("wheel_rb_dummy", 1, -0.05), ("wheel_lb_dummy", -1, -0.05)):
    objs[name].matrix_world = Matrix.Translation((sx * WHEEL_X, hub.y + dy, hub.z))
objs["wheel"].matrix_world = Matrix.Translation((WHEEL_X, hub.y + 0.05, hub.z))
objs["hookup"].matrix_world = Matrix.Translation(hook)

dummy = bpy.data.objects.new("door_lf_dummy", None)
dummy.dff.type = "OBJ"
clump.objects.link(dummy)
dummy.parent = objs["chassis_dummy"]
dummy.matrix_world = Matrix.Translation(hinge)
atomic = bpy.data.objects.new("door_lf_ok", leaf)
atomic.dff.type = "OBJ"
atomic.dff.is_frame = True  # its own frame (door_lf_ok), not an atomic on the dummy
clump.objects.link(atomic)
atomic.parent = dummy
atomic.matrix_world = Matrix.Translation(hinge)
bpy.context.view_layer.update()

col_coll.dff.auto_bounds = True


def empty(kind, loc, scale, name):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = 1.0
    e.location, e.scale = loc, scale
    e.dff.type = "COL"
    e.dff.col_material = 64
    col_coll.objects.link(e)


for i, (cx, cy, cz, sx, sy, sz) in enumerate(boxes):
    empty("CUBE", (cx, cy, cz), (sx, sy, sz), f"box{i}")
# underbody spheres, clear of the floor's top, and roof spheres above the ceiling
n = 0
for yy in (-2.3, -1.4, -0.5, 0.5, 1.4, 2.3, 3.2):
    for xx in (-0.75, 0.0, 0.75):
        empty("SPHERE", (xx, yy, 0.36 - Z0), (0.12, 0.12, 0.12), f"sph{n}")
        n += 1
for yy in (-1.2, 0.3, 1.8):
    empty("SPHERE", (0.0, yy, 2.85 - Z0), (0.18, 0.18, 0.18), f"sph{n}")
    n += 1

for o in bpy.data.objects:
    o.select_set(False)
os.makedirs(FILES, exist_ok=True)
out = os.path.join(FILES, NAME + ".dff")
bpy.ops.export_dff.scene(filepath=out, export_coll=True, only_selected=False, export_version="0x36003")

# the door leaf as an object (the shell's leaf and its collision box), and the textures the towable draws with
for ext in (".dff", ".col"):
    with open(os.path.join(OUT, SHELL + "_door" + ext), "rb") as src, open(os.path.join(FILES, NAME + "_door" + ext), "wb") as dst:
        dst.write(src.read())
used = {n.image.name.lower() for o in bpy.data.objects if o.type == "MESH" for m in o.data.materials if m and m.node_tree for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
used |= {n.image.name.lower() for m in leaf.materials if m and m.node_tree for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
with open(os.path.join(OUT, "trailers.txd"), "rb") as src, open(os.path.join(FILES, NAME + ".txd"), "wb") as dst:
    dst.write(trim_txd(src.read(), used))

with open(LUA, "w", newline="\n") as f:
    f.write("-- Generated by tools/trailer_shells/towable.py; do not edit. The towable Airstream: the vehicle model it\n")
    f.write("-- replaces, its files in files/ (<dff>.dff, <dff>.txd), its wheel size (diameter, metres) and its door\n")
    f.write("-- leaf as an object (files/<door>.dff/.col), hinged at x, y, z, rz in the vehicle's frame.\n")
    f.write(f'return {{\n    model = {MODEL},\n    dff = "{NAME}",\n    wheelSize = {diameter:.3f},\n')
    f.write(f'    door = {{ dff = "{NAME}_door", x = {hinge.x:.3f}, y = {hinge.y:.3f}, z = {hinge.z:.3f}, rz = {door["rz"]:.1f} }},\n}}\n')
print(f"towable: {out} (hookup {tuple(round(v, 3) for v in hook)}, wheel {diameter:.3f} m, {len(boxes)} boxes, {n} spheres)")
