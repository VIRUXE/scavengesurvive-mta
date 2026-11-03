"""Extract Bobcat panels with DragonFF, preserving UVs and original damage geometry.
Usage: blender -b -t 2 --python tools/build_bobcat_parts.py -- /path/to/scout/input.json /path/to/GTA
"""
import sys, json, re
from pathlib import Path
import bpy
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.bobcat_parts import PARTS
from tools.extract_samp_models import merge_txd
out = ROOT / 'resources/[scavengesurvive]/prop_models/files'
source = json.loads(Path(sys.argv[sys.argv.index('--')+1]).read_text())['assets'][0]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module='DragonFF')
bpy.ops.import_scene.dff(filepath=source['dff'])
originals = {p['mesh']: bpy.data.objects[p['mesh']] for p in PARTS}
# Common vehicle textures are a parent dictionary of every SA vehicle.
game = Path(sys.argv[sys.argv.index('--')+2])
txd = merge_txd([Path(source['sourceFiles'][0]).read_bytes(), (game/'models/generic/vehicle.txd').read_bytes()])
collection = bpy.data.collections.new('Bobcat parts')
bpy.context.scene.collection.children.link(collection)
assets=[]
for p in PARTS:
    src = originals[p['mesh']]
    obj = bpy.data.objects.new(p['asset'], src.data.copy())
    collection.objects.link(obj)
    obj.data.transform(src.matrix_world)
    points=[v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(v[k] for v in points) for k in range(3)))
    hi=Vector(tuple(max(v[k] for v in points) for k in range(3)))
    shift=(lo+hi)/2  # origin at the middle of the part: carrying and lying flat both turn it about its centre
    for v in obj.data.vertices: v.co-=shift
    obj.dff.type='OBJ'
    # Paint ids 96/25: the first stock Bobcat pairing in carcols.dat.
    # Replace the SA vehicle-only paint markers with fixed object colours.
    for slot in obj.material_slots:
        if not slot.material: continue
        mat=slot.material.copy(); slot.material=mat
        rgba=tuple(mat.diffuse_color)
        marker=tuple(round(c*255) for c in rgba[:3])
        if marker == (60,255,0): rgba=(155/255,159/255,157/255,rgba[3])
        elif marker == (255,0,175): rgba=(63/255,62/255,69/255,rgba[3])
        mat.diffuse_color=rgba
        node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        node.inputs['Base Color'].default_value=rgba
        # These plugins depend on the vehicle renderer; loose objects use ordinary materials.
        mat.dff.export_env_map=False
        mat.dff.export_specular=False
        for tex in mat.node_tree.nodes:
            if tex.type=='TEX_IMAGE' and tex.image:
                key=re.split(r'\.png',tex.image.name,flags=re.I)[0].lower()
                # One canonical image per texture prevents Blender's .001 suffixes
                # from becoming exported RenderWare texture names.
                image=bpy.data.images.get(key+'.png')
                if image is None: image=bpy.data.images.new(key+'.png',8,8)
                tex.image=image
    col=bpy.data.objects.new(p['asset']+'_col',None)
    col.empty_display_type='CUBE'; col.location=(lo+hi)/2-shift
    col.scale=tuple(max((hi[k]-lo[k])/2,0.025) for k in range(3))
    col.dff.type='COL'; collection.objects.link(col)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); col.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.export_dff.scene(filepath=str(out/(p['asset']+'.dff')),export_coll=False,only_selected=True,export_version='0x36003')
    bpy.ops.export_col.scene(filepath=str(out/(p['asset']+'.col')),export_version='3',only_selected=True)
    (out/(p['asset']+'.txd')).write_bytes(txd)
    bpy.data.objects.remove(col,do_unlink=True)
    assets.append(obj)
    print('EXPORTED',p['asset'],len(obj.data.polygons),tuple(hi-lo))
for obj in list(bpy.data.objects):
    if obj not in assets: bpy.data.objects.remove(obj,do_unlink=True)
# Editable comparison: good row, damaged row, all at original scale.
for i,obj in enumerate(assets): obj.location=((i//2)*2.7,(i%2)*3,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'docs/bobcat_parts.blend'))
