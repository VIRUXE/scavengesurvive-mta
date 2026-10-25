# blender -b --python review_heads.py -- <out prefix> <dff> <txd> [txd ...]
# Renders the head of a ped from ten angles, textured and in plain grey studio light (shape), and prints a mesh
# health report for the head: open edges, non-manifold edges, faces facing into the skull.
import math
import os
import sys

import addon_utils
import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
out, dff, txds = argv[0], argv[1], argv[2:]
addon_utils.enable("DragonFF", default_set=False)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
files = [{"name": os.path.basename(dff)}] + [{"name": os.path.basename(t)} for t in txds]
bpy.ops.import_scene.dff(filepath=dff, directory=os.path.dirname(dff), files=files, load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
mesh = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.vertex_groups))
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
head = next(b for b in arm.data.bones if b.name.strip() == "Head")
tb = np.array((arm.matrix_world @ head.matrix_local).inverted() @ mesh.matrix_world)
g = next(v for v in mesh.vertex_groups if v.name.strip() == "Head").index

# --- health: head faces (all corners Head-weighted) ---
bm = bmesh.new()
bm.from_mesh(mesh.data)
dl = bm.verts.layers.deform.active
bone = lambda co: np.array(co) @ tb[:3, :3].T + tb[:3, 3]
headf = [f for f in bm.faces if all(v[dl].get(g, 0) > 0.5 for v in f.verts)]
hs = set(headf)
pos = {}
for v in bm.verts:
    pos.setdefault(tuple(np.round(np.array(v.co), 4)), []).append(v)
# edges by welded position (UV seams split vertices)
ekey = lambda e: tuple(sorted((tuple(np.round(np.array(e.verts[0].co), 4)), tuple(np.round(np.array(e.verts[1].co), 4)))))
count = {}
for f in headf:
    for e in f.edges:
        count[ekey(e)] = count.get(ekey(e), 0) + 1
allcount = {}
for f in bm.faces:
    for e in f.edges:
        allcount[ekey(e)] = allcount.get(ekey(e), 0) + 1
open_above = [k for k, c in allcount.items() if c == 1 and min(bone(np.array(p))[0] for p in k) > 0.0]
nonman = [k for k, c in allcount.items() if c > 2 and min(bone(np.array(p))[0] for p in k) > 0.0]
hv = np.array([bone(v.co) for f in headf for v in f.verts])
centre = hv.mean(0)
inward = 0
for f in headf:
    c = bone(f.calc_center_median())
    n = np.array(f.normal) @ tb[:3, :3].T
    if c[0] > 0.08 and np.dot(n, c - centre) < 0:
        inward += 1
print(f"HEALTH open_edges_above_jaw={len(open_above)} nonmanifold={len(nonman)} inward_faces_upper={inward} head_faces={len(headf)}")
bm.free()

# --- renders ---
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.resolution_x = sc.render.resolution_y = 360
sc.render.film_transparent = False
sh = sc.display.shading
UP, FWD = Vector((1, 0, 0)), Vector((0, 1, 0))
SIDE = UP.cross(FWD)
mw = mesh.matrix_world
hp = [mw @ mesh.data.vertices[i].co for i in range(len(mesh.data.vertices)) if any(gg.group == g and gg.weight > 0.5 for gg in mesh.data.vertices[i].groups)]
hpa = np.array([list(v) for v in hp])
c = Vector(((hpa.min(0) + hpa.max(0)) / 2).tolist()) - UP * 0.01
cd = bpy.data.cameras.new("cam")
cd.lens = 60
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
VIEWS = [("f", 0, 8), ("fl", 45, 8), ("l", 90, 8), ("bl", 135, 12), ("b", 180, 12), ("br", 225, 12), ("r", 270, 8), ("fr", 315, 8), ("top", 0, 78), ("low", 20, -30)]
for mode in ("tex", "grey"):
    if mode == "tex":
        sh.light = "FLAT"
        sh.color_type = "TEXTURE"
    else:
        sh.light = "STUDIO"
        sh.color_type = "SINGLE"
        sh.single_color = (0.75, 0.75, 0.75)
        sh.show_specular_highlight = False
    for name, yaw, el in VIEWS:
        a, e = math.radians(yaw), math.radians(el)
        d = (FWD * math.cos(a) + SIDE * math.sin(a)) * math.cos(e) + UP * math.sin(e)
        z = d.normalized()
        x = (UP if abs(el) < 70 else FWD).cross(z).normalized()
        cam.matrix_world = Matrix((x, z.cross(x), z)).transposed().to_4x4()
        cam.location = c + z * 0.62
        sc.render.filepath = f"{out}-{mode}-{name}.png"
        bpy.ops.render.render(write_still=True)
print("DONE")
