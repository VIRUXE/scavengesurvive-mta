"""Close-up of the original tailgate logo on good and damaged panels."""
import bpy
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'docs/bobcat_parts.blend'))
for o in bpy.data.objects:o.hide_render=True
for i,state in enumerate(['ok','dam']):
 o=bpy.data.objects['bobcat_boot_'+state];o.hide_render=False;o.location=(i*2.4,0,0);o.rotation_euler=(0,0,0)
 c=bpy.data.curves.new('label','FONT');c.body='GOOD' if i==0 else 'BAD';c.size=.16;c.align_x='CENTER'
 t=bpy.data.objects.new('label',c);bpy.context.scene.collection.objects.link(t);t.location=(i*2.4,0,-.25);t.rotation_euler=(1.5708,0,0)
bpy.ops.object.camera_add(location=(1.2,-7,1.1));cam=bpy.context.object;cam.rotation_euler=(Vector((1.2,0,.12))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=4.8
s=bpy.context.scene;s.camera=cam;s.render.resolution_x=1500;s.render.resolution_y=500;s.cycles.samples=16
bpy.ops.object.light_add(type='AREA',location=(1,-4,4));bpy.context.object.data.energy=500;bpy.context.object.data.size=5
s.render.filepath=str(root/'docs/images/bobcat_tailgate_logo.png');bpy.ops.render.render(write_still=True)
