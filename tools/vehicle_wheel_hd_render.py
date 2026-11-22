"""Background Blender worker for tools.vehicle_wheel_hd; reads actual DFF wheel geometry."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.vehicle_wheel_hd import SOURCE, OUTPUT, dragon, wheel_atomics


def render(only=None):
    dff, _ = dragon()
    inventory = json.loads((SOURCE/'inventory.json').read_text())
    assets = json.loads((SOURCE/'build.json').read_text())
    previous = {r['key']:r for r in json.loads((OUTPUT/'render_manifest.json').read_text())} if (OUTPUT/'render_manifest.json').exists() else {}
    recipe = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    manifest, seen = [], set()
    dest = OUTPUT/'renders'
    dest.mkdir(exist_ok=True)
    for model in inventory['models']:
        if only and model['model'] not in only:
            continue
        obj = dff.dff()
        obj.load_memory((OUTPUT/'models'/f"{model['name']}.dff").read_bytes())
        for clump in obj.clumps:
            for atomic_index, atomic, chain in wheel_atomics(clump, model['kind']=='upgrade'):
                geometry = clump.geometry_list[atomic.geometry]
                if not geometry.triangles:
                    continue
                signature = hashlib.sha256(repr((geometry.vertices,geometry.triangles,geometry.uv_layers,
                                                [(m.color,[(t.name,model['textures'][t.name.lower()]) for t in m.textures]) for m in geometry.materials])).encode()).hexdigest()
                if signature in seen:
                    continue
                seen.add(signature)
                key = f"{model['model']}_{model['name']}_{atomic_index}"
                textures = sorted({model['textures'][t.name.lower()] for m in geometry.materials for t in m.textures})
                record = {'key':key,'model':model['model'],'atomic':atomic_index,'frame_chain':chain,
                          'geometry_sha256':signature,'textures':textures,'blender':bpy.app.version_string,
                          'triangles':len(geometry.triangles),'dff_sha256':model['dff_sha256']}
                record['render_sha256'] = hashlib.sha256((recipe+signature+''.join(assets[t[:16]]['dds_sha256'] for t in textures)).encode()).hexdigest()
                manifest.append(record)
                if previous.get(key,{}).get('render_sha256') == record['render_sha256'] and all((dest/f'{key}_{phase}.png').exists() for phase in ('before','after')):
                    continue
                bpy.ops.wm.read_factory_settings(use_empty=True)
                scene = bpy.context.scene
                scene.render.engine = 'BLENDER_WORKBENCH'
                scene.render.resolution_x = scene.render.resolution_y = 480
                scene.render.resolution_percentage = 100
                scene.render.image_settings.file_format = 'PNG'
                scene.display.shading.light = 'STUDIO'
                scene.display.shading.color_type = 'TEXTURE'
                scene.display.shading.show_cavity = False
                scene.display.shading.show_shadows = False
                scene.display.shading.show_specular_highlight = False
                scene.display.shading.background_type = 'WORLD'
                scene.world = bpy.data.worlds.new('WheelQA')
                scene.world.color = (0.055,0.065,0.08)
                scene.view_settings.view_transform = 'Standard'
                mesh = bpy.data.meshes.new('VanillaWheel')
                verts = [Vector(v) for v in geometry.vertices]
                mesh.from_pydata(verts, [], [(t.a,t.b,t.c) for t in geometry.triangles])
                wheel = bpy.data.objects.new('VanillaWheel',mesh)
                scene.collection.objects.link(wheel)
                texnodes = []
                for slot, mat in enumerate(geometry.materials):
                    material = bpy.data.materials.new(f'MAT_{slot}')
                    material.use_nodes = True
                    material.diffuse_color = tuple(v/255 for v in mat.color)
                    if mat.textures:
                        texname = mat.textures[0].name.lower()
                        content = model['textures'][texname]
                        node = material.node_tree.nodes.new('ShaderNodeTexImage')
                        node.interpolation = 'Linear'
                        node.extension = 'REPEAT'
                        material.node_tree.nodes.active = node
                        texnodes.append((node,content))
                    mesh.materials.append(material)
                uv = mesh.uv_layers.new()
                for polygon, tri in zip(mesh.polygons,geometry.triangles):
                    polygon.material_index = tri.material
                    polygon.use_smooth = True
                    if geometry.uv_layers:
                        for loop, vertex in zip(polygon.loop_indices,(tri.a,tri.b,tri.c)):
                            coord = geometry.uv_layers[0][vertex]
                            uv.data[loop].uv = (coord.u,1-coord.v)
                lo = Vector([min(v[i] for v in verts) for i in range(3)])
                hi = Vector([max(v[i] for v in verts) for i in range(3)])
                mid, extent = (lo+hi)/2, hi-lo
                axis = min(range(3),key=lambda i:extent[i])
                score = 0
                for tri in geometry.triangles:
                    mat = geometry.materials[tri.material]
                    name = mat.textures[0].name.lower() if mat.textures else ''
                    if 'tyre' not in name and 'tire' not in name:
                        normal = (verts[tri.b]-verts[tri.a]).cross(verts[tri.c]-verts[tri.a])
                        score += normal[axis]*(4 if 'wheel' in name else 1)
                sign = 1 if score>=0 else -1
                # These vanilla wheels have more rear-facing rim triangles than
                # front-facing ones; the area heuristic otherwise shows the hub's back.
                if model['model'] in (435,450,565,591,1025):
                    sign = -sign
                direction = Vector((0.2,-0.25,0.25))
                direction[axis] = sign
                camera = bpy.data.objects.new('CAM_Wheel',bpy.data.cameras.new('CAM_Wheel'))
                scene.collection.objects.link(camera)
                scene.camera = camera
                camera.data.type = 'ORTHO'
                camera.data.ortho_scale = max(extent)*1.22
                camera.data.clip_start = 0.001
                camera.data.clip_end = 500
                camera.location = mid+direction.normalized()*max(extent)*4
                camera.rotation_euler = (mid-camera.location).to_track_quat('-Z','Y').to_euler()
                for phase in ('before','after'):
                    for node,content in texnodes:
                        node.image = bpy.data.images.load(str(OUTPUT/'render_textures'/phase/f'{content[:16]}.png'),check_existing=True)
                    scene.render.filepath = str(dest/f'{key}_{phase}.png')
                    bpy.ops.render.render(write_still=True)
                print('WHEEL_QA',key,flush=True)
    (OUTPUT/'render_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    render({int(s) for s in args[0].split(',')} if args else None)
