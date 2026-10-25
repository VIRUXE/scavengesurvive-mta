"""Textured renders of a ped's head from four sides, headless: run inside Blender with the DragonFF add-on.

    blender -b --python tools/blender/render_head.py -- <out prefix> <dff> <txd> [txd ...]   (TXDs beside the DFF)

Writes <out prefix>-front.png, -three.png, -side.png and -back.png (512x512, flat-lit Workbench, orthographic, framed
on the vertices weighted to the Head bone). Compare an original skin, its hatless twin (`models/files/<name>_nohat.dff`
with the base skin's TXD and, for a rebuilt head, its own) and the reference images in docs/images/hatless-refs without the game or the studio (#89).
"""
import math
import os
import sys

import addon_utils
import bpy
from mathutils import Matrix, Vector

UP = Vector((1, 0, 0))  # DragonFF imports a GTA ped X-up, facing +Y
FWD = Vector((0, 1, 0))
SIDE = UP.cross(FWD)
VIEWS = {"front": 0, "three": 35, "side": 90, "back": 180}


def render(out, dff, txds):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    files = [{"name": os.path.basename(dff)}] + [{"name": os.path.basename(t)} for t in txds]
    bpy.ops.import_scene.dff(filepath=dff, directory=os.path.dirname(dff), files=files, load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
    mesh = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.vertex_groups))
    group = next(g for g in mesh.vertex_groups if g.name.strip() == "Head")
    pts = [mesh.matrix_world @ v.co for v in mesh.data.vertices if any(g.group == group.index and g.weight > 0.5 for g in v.groups)]
    centre = sum(pts, Vector()) / len(pts)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    cam_data = bpy.data.cameras.new("head")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.42
    cam = bpy.data.objects.new("head", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, yaw in VIEWS.items():
        a = math.radians(yaw)
        z = (FWD * math.cos(a) + SIDE * math.sin(a) + UP * 0.12).normalized()
        x = UP.cross(z).normalized()
        cam.matrix_world = Matrix((x, z.cross(x), z)).transposed().to_4x4()
        cam.location = centre + z * 2.0
        scene.render.filepath = f"{out}-{name}.png"
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :]
    addon_utils.enable("DragonFF", default_set=False)
    render(argv[0], argv[1], argv[2:])
