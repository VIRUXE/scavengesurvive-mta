"""Rebuild GTA's green dumpster (model 1227, dump1: a solid box) as a hollow body with a hinged lid and a mound of
bin bags inside, for the `dumpsters` resource.

    blender --factory-startup -b -t 4 --python tools/build_dumpster.py

GTA Scout found the model (output/dumpster-20261107). Inputs, from its ignored output directory: Metal4_256.png (the
dump1 paint, from dynbuket.txd) and Gen_Bin_Bag.png (the bin bag paint, from box_models' wbox_binbag.txd). Outputs:
dumpster_body.{dff,txd,col} and dumpster_lid.{dff,txd,col} in resources/[scavengesurvive]/dumpsters/files/, plus a
.blend and open/closed previews in Scout's output directory. Body origin: middle of the floor, front facing -Y, 2.32 x
1.33 x 1.50 m (the 1227 footprint). Lid origin: the hinge, on the back wall's top edge; it opens by rotating about X.
"""

import math
import os
import random
import shutil
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SCOUT = Path(os.environ.get("GTA_SCOUT_PATH", str(ROOT.parents[3] / "gta-scout")))
WORK = SCOUT / "output/dumpster-20261107"
OUT = WORK / "build"
OUT.mkdir(parents=True, exist_ok=True)
RESOURCE = ROOT / "resources/[scavengesurvive]/dumpsters"
(RESOURCE / "files").mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(SCOUT / "references"))
import DragonFF  # noqa: E402

DragonFF.register()

METAL_PNG = next((WORK / "b2/sources").glob("*/textures/Metal4_256.png"))
BAG_PNG = WORK / "tex/Gen_Bin_Bag.png"

W, D, H = 2.32, 1.33, 1.50  # outside size of the body
T = 0.06  # wall thickness

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, png, rough=0.6, metal=0.1):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    im = bpy.data.images.load(str(png))
    im.name = name
    node = m.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = im
    m.node_tree.links.new(node.outputs["Color"], p.inputs["Base Color"])
    return m


paint = material("Metal4_256", METAL_PNG)
bagmat = material("Gen_Bin_Bag", BAG_PNG, 0.35, 0.0)


def planar_uv(o, scale):
    """world-scale box mapping: each face is projected along its dominant normal axis"""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [i for i in range(3) if i != ax]
        for lp in f.loops:
            c = lp.vert.co
            lp[uv].uv = (c[a] / scale, c[b] / scale)
    bm.to_mesh(me)
    bm.free()


def box(name, centre, size, mat=paint, bevel=0.0, uvscale=1.4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("b", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    planar_uv(o, uvscale)
    o.data.materials.append(mat)
    return o


def join(objs, name, origin):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return o


# --- body: floor, four walls, front posts that make the three panels, a rim, the lock hasp -------------------------
parts = [
    box("floor", (0, 0, T / 2), (W, D, T)),
    box("wall_front", (0, -D / 2 + T / 2, H / 2), (W, T, H)),
    box("wall_back", (0, D / 2 - T / 2, H / 2), (W, T, H)),
    box("wall_l", (-W / 2 + T / 2, 0, H / 2), (T, D - 2 * T, H)),
    box("wall_r", (W / 2 - T / 2, 0, H / 2), (T, D - 2 * T, H)),
]
for x in (-0.39, 0.39):  # the posts between the three front panels
    parts.append(box("post", (x, -D / 2 - 0.012, H / 2), (0.07, 0.03, H - 0.06), bevel=0.01))
for x in (-W / 2 + 0.03, W / 2 - 0.03):
    parts.append(box("post_end", (x, -D / 2 - 0.012, H / 2), (0.07, 0.03, H - 0.06), bevel=0.01))
for z in (0.04, H - 0.05):  # base and top rails
    parts.append(box("rail", (0, -D / 2 - 0.012, z), (W, 0.03, 0.09), bevel=0.01))
parts.append(box("rim_back", (0, D / 2 + 0.012, H - 0.04), (W, 0.03, 0.08), bevel=0.01))
parts.append(box("hasp", (0, -D / 2 - 0.035, H - 0.14), (0.1, 0.02, 0.13), bevel=0.004))
parts.append(box("lock", (0, -D / 2 - 0.055, H - 0.17), (0.05, 0.03, 0.06), bevel=0.008))

# --- the mound of bin bags: squashed lumpy spheres with a tie knot, three layers, the top one well in view ---------
rng = random.Random(1227)


def bag(name, loc, rot):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(0, 0, 0))
    o = bpy.context.object
    o.name = name
    sx, sy, sz = rng.uniform(0.26, 0.33), rng.uniform(0.28, 0.35), rng.uniform(0.22, 0.28)
    for v in o.data.vertices:
        j = 1 + rng.uniform(-0.1, 0.1)
        v.co = Vector((v.co.x * sx * j, v.co.y * sy * j, v.co.z * sz * j))
        if v.co.z > sz * 0.85:  # the gathered neck of the bag
            v.co.x *= 0.45
            v.co.y *= 0.45
            v.co.z += 0.05
    o.rotation_euler = (0, 0, rot)
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    planar_uv(o, 0.8)
    o.data.materials.append(bagmat)
    return o


inner_x, inner_y = W / 2 - T - 0.3, D / 2 - T - 0.27
bags = []
for layer, (z0, nx, ny) in enumerate([(T + 0.25, 5, 2), (T + 0.55, 4, 2), (T + 0.84, 3, 2)]):
    for ix in range(nx):
        for iy in range(ny):
            fx = (ix + 0.5) / nx * 2 - 1
            fy = (iy + 0.5) / ny * 2 - 1
            loc = (
                fx * inner_x + rng.uniform(-0.07, 0.07),
                fy * inner_y + rng.uniform(-0.05, 0.05),
                z0 + rng.uniform(-0.03, 0.06),
            )
            bags.append(bag(f"bag{layer}{ix}{iy}", loc, rng.uniform(0, math.tau)))

body = join(parts + bags, "dumpster_body", (0, 0, 0))

# --- lid: origin at the hinge (top of the back wall); slab, edge lips, three raised panels, a handle -------------
LW, LD = W + 0.04, D + 0.08
lp = [
    box("slab", (0, -LD / 2 + 0.02, 0.025), (LW, LD, 0.05), bevel=0.012),
    box("lip_front", (0, -LD + 0.02, -0.03), (LW, 0.04, 0.12), bevel=0.01),
    box("lip_l", (-LW / 2 + 0.02, -LD / 2 + 0.02, -0.03), (0.04, LD, 0.12), bevel=0.01),
    box("lip_r", (LW / 2 - 0.02, -LD / 2 + 0.02, -0.03), (0.04, LD, 0.12), bevel=0.01),
    box("hinge_barrel", (0, 0.0, 0.02), (LW - 0.1, 0.06, 0.07), bevel=0.02),
    box("handle", (0, -LD + 0.07, 0.085), (0.5, 0.05, 0.06), bevel=0.015),
]
for x in (-0.39, 0.39):
    lp.append(box("seam", (x, -LD / 2 + 0.02, 0.06), (0.06, LD - 0.12, 0.03), bevel=0.008))
lid = join(lp, "dumpster_lid", (0, 0, 0))
lid.location = (0, D / 2, H)
bpy.context.view_layer.update()

# --- collision: the body is a solid block (nobody climbs in), the lid carries a token box and is made non-solid ----
cbody = bpy.data.collections.new("COL_BODY")
clid = bpy.data.collections.new("COL_LID")
for c in (cbody, clid):
    bpy.context.scene.collection.children.link(c)


def colbox(name, loc, half, coll):
    bpy.ops.object.empty_add(type="CUBE", location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = half
    o.dff.type = "COL"
    o.dff.col_material = 52
    for old in list(o.users_collection):
        old.objects.unlink(o)
    coll.objects.link(o)


colbox("dumpster_body", (0, 0, H / 2), (W / 2, D / 2, H / 2), cbody)
colbox("dumpster_lid", (0, -0.7, 0.03), (0.02, 0.02, 0.02), clid)

# --- export -------------------------------------------------------------------------------------------------------
from DragonFF.ops.col_exporter import export_col  # noqa: E402
from DragonFF.ops.dff_exporter import export_dff  # noqa: E402
from DragonFF.ops.txd_exporter import export_txd  # noqa: E402


def export(obj, name, coll):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    keep = obj.location.copy()
    obj.location = (0, 0, 0)  # the exported frame sits at the model origin (the hinge for the lid)
    bpy.context.view_layer.update()
    export_dff(
        dict(
            selected=True,
            export_frame_names=True,
            exclude_geo_faces=False,
            mass_export=False,
            preserve_positions=True,
            preserve_rotations=True,
            directory=str(OUT),
            version=0x36003,
            export_coll=False,
            coll_ext_type=0,
            apply_coll_trans=True,
            from_outliner=False,
            file_name=str(OUT / (name + ".dff")),
        )
    )
    export_txd(dict(directory=str(OUT), file_name=str(OUT / (name + ".txd")), only_used_textures=True, version=0x36003))
    export_col(
        dict(
            version=3,
            collection=coll,
            apply_transformations=True,
            only_selected=False,
            clean_mesh=True,
            export_face_groups=False,
            file_name=str(OUT / (name + ".col")),
        )
    )
    obj.location = keep


export(body, "dumpster_body", cbody)
export(lid, "dumpster_lid", clid)
for stem in ("dumpster_body", "dumpster_lid"):
    for ext in ("dff", "txd", "col"):
        shutil.copyfile(OUT / f"{stem}.{ext}", RESOURCE / "files" / f"{stem}.{ext}")

tris = sum(sum(len(f.vertices) - 2 for f in o.data.polygons) for o in (body, lid))
print("DUMPSTER OK", "triangles", tris, "body bounds", [tuple(round(c, 3) for c in v) for v in (body.bound_box[0], body.bound_box[6])])

# --- previews (Cycles, small): closed and open ---------------------------------------------------------------------
for c in (cbody, clid):
    c.hide_render = True
    c.hide_viewport = True
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 24
bpy.context.scene.render.resolution_x = 900
bpy.context.scene.render.resolution_y = 650
bpy.context.scene.world = bpy.data.worlds.new("w")
bpy.context.scene.world.use_nodes = True
bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 4
so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(50), 0, math.radians(30))
bpy.context.scene.collection.objects.link(so)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam
cam.location = (2.6, -3.2, 4.6)
cam.rotation_euler = (math.radians(48), 0, math.radians(39))
for state, angle in (("closed", 0), ("open", -110)):
    lid.rotation_euler = (math.radians(angle), 0, 0)
    bpy.context.scene.render.filepath = str(OUT / f"preview_{state}.png")
    bpy.ops.render.render(write_still=True)
lid.rotation_euler = (0, 0, 0)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "dumpster.blend"))
