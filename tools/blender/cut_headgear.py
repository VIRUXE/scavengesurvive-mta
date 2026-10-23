"""Runs inside Blender (headless):

    blender -b --python cut_headgear.py -- <in.dff> <out.dff> <texture> <blocks|auto> <above>

Imports a GTA:SA ped with DragonFF, deletes the headgear faces and exports the skinned mesh again with the texture
name set, so MTA finds it in the ped's own TXD. A GTA ped's vertical axis is X; the Head bone sits at the chin.

A face is headgear when its centroid is more than <above> metres over the Head bone and its UV centroid falls in
one of the 8x8 texture blocks listed as "u,v;u,v;..." (block column and row, row 0 at the top of the image). With
"auto" the blocks are the ones whose faces above the bone reach further from the head axis than a bare skull
(0.135 m) or higher than one (0.21 m), which is what the GTA hats, helmets and caps do; the choice is printed.
"""
import sys
from collections import defaultdict

import addon_utils
import bmesh
import bpy

SKULL_REACH, SKULL_TOP = 0.135, 0.21

argv = sys.argv[sys.argv.index("--") + 1 :]
src, out, texture, blocks_arg, above = argv[0], argv[1], argv[2], argv[3], float(argv[4])

addon_utils.enable("DragonFF", default_set=False)
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.import_scene.dff(filepath=src, load_images=False, remove_doubles=False)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
head = next(b for o in bpy.data.objects if o.type == "ARMATURE" for b in o.data.bones if b.name.strip() == "Head")
hx, hy, hz = head.head_local
floor = hx + above


def block_of(f, uvl):
    cu = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
    cv = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
    return min(7, max(0, int(cu * 8))), min(7, max(0, int((1 - cv) * 8)))


def centroid_x(f):
    return sum(v.co.x for v in f.verts) / len(f.verts)


bms = []
for ob in meshes:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bms.append((ob, bm))

if blocks_arg == "auto":
    reach, peak = defaultdict(float), defaultdict(float)
    for _, bm in bms:
        uvl = bm.loops.layers.uv.active
        for f in bm.faces:
            if centroid_x(f) < hx + 0.05:
                continue
            k = block_of(f, uvl)
            r = max(((v.co.y - hy) ** 2 + (v.co.z - hz) ** 2) ** 0.5 for v in f.verts)
            reach[k] = max(reach[k], r)
            peak[k] = max(peak[k], max(v.co.x for v in f.verts) - hx)
    blocks = {k for k in reach if reach[k] > SKULL_REACH or peak[k] > SKULL_TOP}
    print("cut_headgear: auto blocks " + " ".join("%d,%d(r%.2f x%.2f)" % (k[0], k[1], reach[k], peak[k]) for k in sorted(blocks)))
else:
    blocks = {tuple(int(v) for v in b.split(",")) for b in blocks_arg.split(";")}

removed, total = 0, 0
for ob, bm in bms:
    me = ob.data
    uvl = bm.loops.layers.uv.active
    doomed = [f for f in bm.faces if centroid_x(f) >= floor and block_of(f, uvl) in blocks]
    total += len(bm.faces)
    removed += len(doomed)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    img = bpy.data.images.get(texture) or bpy.data.images.new(texture, 4, 4)
    for mat in me.materials:
        mat.dff.tex_name = texture
        mat.use_nodes = True
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_dff.scene(filepath=out, export_coll=False, only_selected=False, export_version="0x36003")
print(f"cut_headgear: removed {removed} of {total} faces -> {out}")
