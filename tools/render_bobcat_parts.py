"""Render comparisons; pass Bobcat and shared-vehicle Scout manifests after --."""
import bpy,json,math,sys
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'docs/bobcat_parts.blend'))
textures={}
for path in sys.argv[sys.argv.index('--')+1:]:
 textures.update(json.load(open(path))['assets'][0]['textures'])
# Mirror RenderWare: texture RGB times material RGBA; UV and texture alpha preserved.
# Do not replace unresolved inputs with a neutral material: missing textures fail.
for mat in bpy.data.materials:
 if not mat.use_nodes or mat.users == 0: continue
 rgba=tuple(mat.diffuse_color)
 references=[n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
 key=references[0].name.lower().split('.png')[0] if references else None
 mat.node_tree.nodes.clear()
 nodes=mat.node_tree.nodes;links=mat.node_tree.links
 bsdf=nodes.new('ShaderNodeBsdfPrincipled')
 bsdf.inputs['Base Color'].default_value=rgba
 bsdf.inputs['Alpha'].default_value=rgba[3]
 bsdf.inputs['Roughness'].default_value=.38 if 'primary' in mat.name or 'secondary' in mat.name else .58
 output=nodes.new('ShaderNodeOutputMaterial');links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
 if key:
  if key not in textures: raise RuntimeError('Missing original texture: '+key)
  tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(textures[key],check_existing=True)
  tint=nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1;tint.inputs[2].default_value=rgba
  links.new(tex.outputs['Color'],tint.inputs[1]);links.new(tint.outputs[0],bsdf.inputs['Base Color'])
  alpha=nodes.new('ShaderNodeMath');alpha.operation='MULTIPLY';alpha.inputs[1].default_value=rgba[3]
  links.new(tex.outputs['Alpha'],alpha.inputs[0]);links.new(alpha.outputs[0],bsdf.inputs['Alpha'])
for mat in list(bpy.data.materials):
 if mat.users==0: bpy.data.materials.remove(mat)
# Remove unused placeholder images so Cycles never tries to load the import paths.
for im in list(bpy.data.images):
 if im.users==0: bpy.data.images.remove(im)
for image in bpy.data.images:
 if image.source=='FILE': image.pack()
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=1400;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new("Studio")
scene.world.color=(0.3,0.3,0.3)
parts=sorted([o for o in bpy.data.objects if o.type=='MESH'],key=lambda o:o.name)
# Render three comparisons per image, from the exterior side of the parts.
for batch in range(2):
 chosen=['boot','door_lf','door_rf'] if batch==0 else ['bonnet','bump_front','bump_rear']
 for o in parts: o.hide_render=True
 for i,mesh in enumerate(chosen):
  for j,state in enumerate(['ok','dam']):
   o=bpy.data.objects['bobcat_'+mesh+'_'+state];o.hide_render=False
   o.location=(i*3.2,j*3.2,0)
   o.rotation_euler.z=0
   if mesh=='bump_rear':o.rotation_euler.z=math.pi
   if mesh=='door_lf':o.rotation_euler.z=math.pi/2
   if mesh=='door_rf':o.rotation_euler.z=-math.pi/2
   # Labels underneath each part.
   c=bpy.data.curves.new('label','FONT');c.body=mesh.replace('_',' ').replace('boot','tailgate').replace('bonnet','hood')+' / '+('GOOD' if j==0 else 'BAD');c.size=.20;c.align_x='CENTER'
   text=bpy.data.objects.new('label',c);scene.collection.objects.link(text);text.location=(i*3.2,j*3.2-1,0)
 target=Vector((3.2,1.6,0))
 bpy.ops.object.camera_add(location=(9,-10,15));camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=12;scene.camera=camera
 bpy.ops.object.light_add(type='AREA',location=(3,-3,10));bpy.context.object.data.energy=2200;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=8
 scene.render.filepath=str(root/f'docs/images/bobcat_parts_{batch+1}.png');bpy.ops.render.render(write_still=True)
 for o in list(bpy.data.objects):
  if o.type in ('FONT','CAMERA','LIGHT'):bpy.data.objects.remove(o,do_unlink=True)
# Save textured editable comparison without render helpers.
for o in parts:o.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(root/'docs/bobcat_parts.blend'))
