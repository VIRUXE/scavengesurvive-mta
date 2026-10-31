"""Renders the saved fort_scene.blend from named camera poses (workbench, natives grey, custom models orange).

    blender -b .cache/fort_scene.blend --python tools/fort_scene_render.py -- OUT_DIR name:cx,cy,cz:tx,ty,tz [...]
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    out = Path(args[0])
    out.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 1100, 760
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_cavity = True
    for ob in bpy.data.objects:
        ob.color = (1.0, 0.45, 0.1, 1.0) if ob.name.startswith("fort_") else (0.72, 0.72, 0.7, 1.0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.clip_start, cam.data.clip_end, cam.data.lens = 0.1, 400, 28
    for spec in args[1:]:
        name, eye, target = spec.split(":")
        cam.location = Vector([float(v) for v in eye.split(",")])
        direction = Vector([float(v) for v in target.split(",")]) - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out / f"{name}.png")
        bpy.ops.render.render(write_still=True)


main()
