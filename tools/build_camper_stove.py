"""Build the compact camper stove and its four independently controlled gas burners.
blender --factory-startup -b -t 4 --python tools/build_camper_stove.py
Outputs are local GTA Scout output plus the stove resource's DFF/TXD/COL.
"""
import bpy, math, sys, random, json, shutil, os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
SCOUT=Path(os.environ.get('GTA_SCOUT_PATH',str(ROOT.parents[3]/'gta-scout')))
OUT=SCOUT/'output/stove-camper-20261102';OUT.mkdir(parents=True,exist_ok=True)
RESOURCE=ROOT/'resources/[scavengesurvive]/stove'
sys.path.insert(0,str(SCOUT/'references'));import DragonFF
DragonFF.register()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
asset=bpy.data.collections.new('STOVE_ASSET');bpy.context.scene.collection.children.link(asset)
parts=[]
def relocate(o,c):
 for old in list(o.users_collection):old.objects.unlink(o)
 c.objects.link(o)
def material(name,color,metal=0,rough=.45,texture=True):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if texture:
  size=128 if name=='rv_steel' else 32
  im=bpy.data.images.new(name,width=size,height=size);rng=random.Random(name);pix=[]
  for y in range(size):
   stripe=rng.uniform(-.04,.04) if name=='rv_steel' else rng.uniform(-.003,.003)
   for x in range(size):
    noise=stripe+rng.uniform(-.006,.006);pix.extend([max(0,min(1,c+noise)) for c in color]+[1])
  im.pixels.foreach_set(pix);im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save();im.pack()
  node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;m.node_tree.links.new(node.outputs['Color'],p.inputs['Base Color']);m.diffuse_color=(1,1,1,1)
 return m
cream=material('rv_cream',(.79,.755,.65),.15,.35)
steel=material('rv_steel',(.54,.57,.59),.78,.36)
black=material('rv_enamel',(.026,.032,.038),.35,.32)
iron=material('rv_iron',(.038,.043,.048),.6,.72)
glass=material('rv_smokedglass',(.018,.034,.044),.45,.18)
white=material('rv_markings',(.86,.87,.82),.1,.5)

def finish(o,name,mat,bevel=0,collection=None):
 o.name=name;relocate(o,collection or asset);o.data.materials.append(mat)
 bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Soft manufactured edge','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
 if collection is None:parts.append(o)
 return o

def box(name,loc,size,mat,bevel=0,collection=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size;return finish(o,name,mat,bevel,collection)
def cyl(name,loc,radius,depth,mat,rotation=(0,0,0)):
 bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=radius,depth=depth,location=loc,rotation=rotation);return finish(bpy.context.object,name,mat,.001)
def bar(name,a,b,r,mat):
 a,b=Vector(a),Vector(b);o=cyl(name,(a+b)/2,r,(b-a).length,mat);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
# Built-in 21-inch style range, bottom at Z=0; front faces -Y.
box('Cream_enamel_shell',(0,0,.276),(.524,.464,.552),cream,.012)
box('Flush_front_surround',(0,-.238,.274),(.514,.018,.531),steel,.008)
box('Control_fascia',(0,-.253,.493),(.504,.022,.090),steel,.006)
box('Black_inset_cooktop',(0,-.003,.558),(.494,.438,.018),black,.009)
# Bright rolled lip around the recessed black pan.
for x in [-.256,.256]:box('Rolled_side_lip',(x,-.002,.568),(.013,.47,.018),steel,.005)
for y in [-.234,.23]:box('Rolled_end_lip',(0,y,.568),(.52,.012,.018),steel,.004)
box('Short_rear_splash',(0,.236,.594),(.524,.015,.071),steel,.006)
# Door is one compact oven, with a smoked rectangular window.
box('Oven_door_gasket',(0,-.255,.260),(.465,.014,.350),black,.012)
box('Oven_door_brushed_frame',(0,-.268,.260),(.449,.021,.333),steel,.011)
box('Black_oven_door',(0,-.283,.257),(.417,.014,.285),black,.012)
box('Smoked_oven_window',(0,-.292,.247),(.341,.008,.191),glass,.011)
# Restrained reflections/rack lines in the opaque smoked window, stable in GTA.
for z in [.196,.225,.254]:box('Oven_rack_through_tint',(0,-.2965,z),(.286,.0015,.0014),steel,.0004)
for x in [-.185,.185]:cyl('Handle_mount',(x,-.294,.408),.012,.021,black,(math.pi/2,0,0))
bar('Chrome_oven_handle',(-.191,-.324,.408),(.191,-.324,.408),.009,steel)
box('Bottom_vent_panel',(0,-.251,.043),(.492,.016,.062),cream,.004)
for z in [.029,.041,.053]:box('Vent_slot',(0,-.260,z),(.393,.002,.004),black,.001)
# Four tactile black burner knobs plus a small oven thermostat.
for i,x in enumerate([-.19,-.095,0,.095,.19]):
 cyl('Knob_chrome_bezel_'+str(i),(x,-.270,.493),.021,.005,steel,(math.pi/2,0,0))
 cyl('Control_knob_'+str(i),(x,-.287,.493),.016,.026,black,(math.pi/2,0,0))
 box('Knob_indicator_'+str(i),(x,-.301,.502),(.0028,.001,.008),white,.0005)
 for j in range(3):
  a=(j-1)*.55;box('Dial_tick',(x+math.sin(a)*.025,-.266,.493+math.cos(a)*.025),(.002,.001,.003),black)
# Two continuous cast-iron pan grids secure pots in the compact camper galley.
burners=[(-.128,-.116,.055),(.128,-.116,.050),(-.128,.102,.050),(.128,.102,.055)]
for i,(x,y,r) in enumerate(burners,1):
 cyl(f'Burner_{i}_recess',(x,y,.571),r*1.18,.006,steel)
 cyl(f'Burner_{i}_black_cap',(x,y,.580),r*.61,.014,iron)
 bpy.ops.mesh.primitive_torus_add(major_segments=20,minor_segments=5,major_radius=r*.82,minor_radius=.0035,location=(x,y,.576));finish(bpy.context.object,f'Burner_{i}_gas_ring',iron)
 for angle in [0,math.pi/2,math.pi,math.pi*1.5]:
  a=(x+math.cos(angle)*r*.68,y+math.sin(angle)*r*.68,.593);b=(x+math.cos(angle)*r*1.6,y+math.sin(angle)*r*1.6,.593);bar(f'Burner_{i}_pot_support',a,b,.004,iron)
for x in [-.225,.225]:
 bar('Secured_grate_side',(x,-.206,.593),(x,.196,.593),.004,iron)
for y in [-.206,-.009,.196]:bar('Secured_grate_cross',(-.225,y,.593),(.225,y,.593),.004,iron)
# Export static stove before adding flames or galley scenery.
for o in parts:
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project();bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'stove.glb'),use_selection=True)
from DragonFF.ops.dff_exporter import export_dff
export_dff(dict(selected=True,export_frame_names=True,exclude_geo_faces=False,mass_export=False,preserve_positions=True,preserve_rotations=True,directory=str(OUT),version=0x36003,export_coll=False,coll_ext_type=0,apply_coll_trans=True,from_outliner=False,file_name=str(OUT/'stove.dff')))
from DragonFF.ops.txd_exporter import export_txd
export_txd(dict(directory=str(OUT),file_name=str(OUT/'stove.txd'),only_used_textures=True,version=0x36003))
# One simple body box, deliberately excluding tiny handles and pan-grid wire.
coll=bpy.data.collections.new('STOVE_COLLISION');bpy.context.scene.collection.children.link(coll)
bpy.ops.object.empty_add(type='CUBE',location=(0,-.014,.285));collision=bpy.context.object;collision.name='stove';collision.scale=(.264,.251,.285);collision.dff.type='COL';collision.dff.col_material=52;relocate(collision,coll)
from DragonFF.ops.col_exporter import export_col
export_col(dict(version=3,collection=coll,apply_transformations=True,only_selected=False,clean_mesh=True,export_face_groups=False,file_name=str(OUT/'stove.col')))
coll.hide_render=True;coll.hide_viewport=True
# Add the same four individually controllable burners to the Blender preview.
sys.path.insert(0,str(ROOT/"tools"))
from camper_stove_flames import add_flames
add_flames(OUT,burners)
# Preview galley: walnut cabinetry, pale counter and a rounded aluminium inner wall.
studio=bpy.data.collections.new('PREVIEW_GALLEY');bpy.context.scene.collection.children.link(studio)
wood=material('Preview_Walnut',(.18,.09,.045),0,.5,False)
counter=material('Preview_Ivory_Counter',(.66,.65,.58),0,.48,False)
wall=material('Preview_Aluminium',(.43,.46,.48),.6,.5,False)
floor=material('Preview_Floor',(.11,.085,.058),0,.75,False)
# Procedural wood grain stays in preview; game stove has only the packed surface textures.
p=next(n for n in wood.node_tree.nodes if n.type=='BSDF_PRINCIPLED');noise=wood.node_tree.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=4;noise.inputs['Detail'].default_value=2
tex=wood.node_tree.nodes.new('ShaderNodeTexCoord');mapping=wood.node_tree.nodes.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(5,5,.13);wood.node_tree.links.new(tex.outputs['Generated'],mapping.inputs[0]);wood.node_tree.links.new(mapping.outputs[0],noise.inputs['Vector']);ramp=wood.node_tree.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.045,.018,.008,1);ramp.color_ramp.elements[1].color=(.24,.12,.05,1);wood.node_tree.links.new(noise.outputs['Fac'],ramp.inputs[0]);wood.node_tree.links.new(ramp.outputs[0],p.inputs['Base Color'])
box('Galley_floor',(0,0,-.335),(4,4,.04),floor,collection=studio)
box('Galley_lower_plinth',(0,.02,-.155),(1.55,.48,.30),wood,.006,studio)
for x in [-.53,.53]:
 box('Galley_cabinet',(x,.015,.278),(.50,.47,.56),wood,.008,studio)
 box('Galley_counter',(x,.005,.573),(.515,.52,.035),counter,.010,studio)
 box('Cabinet_front',(x,-.234,.245),(.456,.018,.43),wood,.005,studio)
 box('Cabinet_chrome_pull',(x,-.252,.42),(.12,.012,.008),steel,.003,studio)
# Curved upper wall profile echoes the trailer's rounded shell.
verts=[];faces=[]
profile=[(.295,-.32),(.295,.9),(.30,1.03),(.34,1.18),(.42,1.33),(.55,1.45)]
for y,z in profile:verts.extend([(-1.5,y,z),(1.5,y,z)])
for i in range(len(profile)-1):faces.append((i*2,i*2+1,i*2+3,i*2+2))
mesh=bpy.data.meshes.new('Curved_inner_skin');mesh.from_pydata(verts,[],faces);o=bpy.data.objects.new('Curved_aluminium_camper_wall',mesh);studio.objects.link(o);mesh.materials.append(wall)
for x in [-1,-.5,0,.5,1]:
 box('Panel_seam',(x,.290,.9),(.002,.002,.43),steel,collection=studio)
# Long horizontal window and frame behind the range.
box('Window_rubber_seal',(0,.283,1.005),(1.18,.016,.30),black,.035,studio)
box('Window_aluminium_frame',(0,.272,1.005),(1.155,.014,.276),steel,.029,studio)
view=material('Preview_Window',(.16,.26,.29),.1,.23,False)
box('Window_pane',(0,.261,1.005),(1.115,.012,.237),view,.025,studio)
box('Window_centre_mullion',(0,.25,1.005),(.012,.012,.24),steel,.003,studio)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1100;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.use_nodes=True;bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.26,.3,.35,1);bg.inputs[1].default_value=.35
for loc,energy,size in [((1,-2,2.4),160,2),((-1,-.8,1.6),80,1.5),((0,.05,1.8),50,.8)]:
 bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=energy;light.data.size=size;light.rotation_euler=(Vector((0,0,.3))-light.location).to_track_quat('-Z','Y').to_euler();relocate(light,studio)
bpy.ops.object.camera_add(location=(1.05,-1.65,1.25));camera=bpy.context.object;camera.rotation_euler=(Vector((0,-.02,.40))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.14;scene.camera=camera;relocate(camera,studio)
# Camera and controls are ready when the editable file is opened.
bpy.ops.object.select_all(action='DESELECT');control=bpy.data.objects['Stove_Control'];control.select_set(True);bpy.context.view_layer.objects.active=control
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
scene.frame_start=1;scene.frame_end=120;scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0;scene.render.filepath=str(OUT/'stove-camper-preview.png');bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'stove-camper.blend'))
# Verify all four rigs still respond after relocating them.
ns={};exec(bpy.data.texts['stove_controls.py'].as_string(),ns)
for i in range(1,5):
 ns['set_burner'](i,0);scene.frame_set(2);jet=bpy.data.objects[f'Flame_Burner_{i}_Jet_01_Outer'].evaluated_get(bpy.context.evaluated_depsgraph_get());assert jet.hide_render and jet.scale.z==0
 ns['set_burner'](i,.5);scene.frame_set(3);jet=bpy.data.objects[f'Flame_Burner_{i}_Jet_01_Outer'].evaluated_get(bpy.context.evaluated_depsgraph_get());assert not jet.hide_render and .44<jet.scale.z<.56
 ns['set_burner'](i,1)
scene.frame_set(1)
points=[o.matrix_world@Vector(v) for o in parts for v in o.bound_box];report=dict(design='Compact built-in camper range',burners=burners,flameBaseZ=.581,boundsMin=[min(p[i] for p in points) for i in range(3)],boundsMax=[max(p[i] for p in points) for i in range(3)],triangles=sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in parts),flameControls='Four independent 0..1 properties',collision='COL3 body box')
(OUT/'asset-report.json').write_text(json.dumps(report,indent=2))
for ext in ['dff','txd','col']:shutil.copyfile(OUT/('stove.'+ext),RESOURCE/'files'/('stove.'+ext))
print('CAMPER_STOVE_VERIFIED',json.dumps(report),flush=True)
bpy.ops.render.render(write_still=True)
