"""Inventory actual vehicle wheel atomics, build mipmapped DDS, and render UV QA.

    python -m tools.vehicle_wheel_hd inventory
    python -m tools.vehicle_wheel_hd build
    python -m tools.vehicle_wheel_hd audit
    python -m tools.vehicle_wheel_hd render

Requires the local vanilla GTA SA install and DragonFF for inventory/render only.
The build consumes checked-in PNGs; it never modifies the game or item wheel pack.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys

if 'bpy' not in sys.modules:
    from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/data/vehicle_wheel_hd'
RESOURCE = ROOT / 'resources/[scavengesurvive]/vehicles'
OUTPUT = Path(os.environ.get('TEMP', '/tmp')) / 'codex_vehicle_wheels'
GTA = Path('D:/Games/gtasa')


def dragon():
    addon = os.environ.get('DRAGONFF_PATH')
    if not addon:
        base = Path(os.environ['APPDATA']) / 'Blender Foundation/Blender'
        addon = next(str(p) for p in sorted(base.glob('*/scripts/addons/DragonFF'), reverse=True))
    sys.path.insert(0, str(Path(addon)))
    from gtaLib import dff, txd
    return dff, txd


def definitions(gta):
    result = {}
    for path in [gta / 'data/vehicles.ide', gta / 'data/maps/veh_mods/veh_mods.ide']:
        for line in path.read_text(encoding='latin1').splitlines():
            # Vanilla emperor's row is missing a comma between model and TXD.
            fields = re.split(r'[,\s]+', line.strip())
            if len(fields) >= 3 and fields[0].isdigit():
                model = int(fields[0])
                if 400 <= model <= 611 or model in [1025, *range(1073, 1086), *range(1096, 1099)]:
                    result[model] = (fields[1], fields[2], fields[3] if model < 612 else 'upgrade')
    return result


def wheel_atomics(clump, upgrade=False):
    for index, atomic in enumerate(clump.atomic_list):
        chain, frame = [], atomic.frame
        while frame >= 0:
            chain.append(clump.frame_list[frame].name)
            frame = clump.frame_list[frame].parent
        if upgrade or any(re.match(r'^wheel(?:$|_)', s, re.I) for s in chain):
            yield index, atomic, chain


def pixel_hash(image):
    return hashlib.sha256(struct.pack('<II', *image.size) + image.convert('RGBA').tobytes()).hexdigest()


def inventory(gta=GTA):
    from tools.extract_samp_models import read_img_index, read_img_entry
    dff, txd = dragon()
    archive = gta / 'models/gta3.img'
    index = read_img_index(archive)
    cache = {}

    def dictionary(name):
        if name not in cache:
            path = gta / 'models/generic' / f'{name}.txd'
            data = path.read_bytes() if path.exists() else read_img_entry(archive, index[f'{name}.txd'])
            obj = txd.txd()
            obj.load_memory(data)
            cache[name] = {t.name.lower(): t for t in obj.native_textures}
        return cache[name]

    SOURCE.mkdir(parents=True, exist_ok=True)
    (SOURCE / 'originals').mkdir(exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / 'models').mkdir(exist_ok=True)
    models, textures, excluded, unresolved = [], {}, [], []
    for model, (name, own_txd, kind) in sorted(definitions(gta).items()):
        data = read_img_entry(archive, index[f'{name}.dff'])
        obj = dff.dff()
        obj.load_memory(data)
        row = {'model': model, 'name': name, 'txd': own_txd, 'kind': kind,
               'dff_sha256': hashlib.sha256(data).hexdigest(), 'atomics': [], 'textures': {}}
        body_names = set()
        for clump in obj.clumps:
            wheels = list(wheel_atomics(clump, kind == 'upgrade'))
            wheel_indices = {i for i, _, _ in wheels}
            for i, atomic in enumerate(clump.atomic_list):
                if i not in wheel_indices:
                    body_names.update(t.name.lower() for m in clump.geometry_list[atomic.geometry].materials for t in m.textures)
            for i, atomic, chain in wheels:
                geometry = clump.geometry_list[atomic.geometry]
                # Only materials actually referenced by triangles; unused slots are not wheel textures.
                used = sorted({t.material for t in geometry.triangles})
                materials = []
                for slot in used:
                    mat = geometry.materials[slot]
                    for tex in mat.textures:
                        texname = tex.name.lower()
                        owner = next((n for n in (own_txd, 'vehicle', 'wheels') if texname in dictionary(n)), None)
                        if owner is None:
                            unresolved.append([model, texname])
                            continue
                        native = dictionary(owner)[texname]
                        image = Image.frombytes('RGBA', (native.width, native.height), bytes(native.to_rgba()))
                        digest = pixel_hash(image)
                        if digest not in textures:
                            original = f'originals/{digest[:16]}.png'
                            image.save(SOURCE / original)
                            textures[digest] = {'id': digest[:16], 'sha256_rgba': digest, 'size': list(image.size),
                                                'alpha': list(image.getextrema()[3]), 'original': original, 'sources': [], 'models': [], 'wheel_regions': []}
                        entry = textures[digest]
                        src = {'txd': f'models/generic/{owner}.txd' if owner in ('vehicle', 'wheels') else f'gta3.img/{owner}.txd', 'name': texname}
                        if src not in entry['sources']:
                            entry['sources'].append(src)
                        if model not in entry['models']:
                            entry['models'].append(model)
                        row['textures'][texname] = digest
                        vertices = {v for tri in geometry.triangles if tri.material == slot for v in (tri.a, tri.b, tri.c)}
                        uv = [geometry.uv_layers[0][v] for v in vertices] if geometry.uv_layers else []
                        bounds = [[min(getattr(u, c) for u in uv), max(getattr(u, c) for u in uv)] for c in ('u', 'v')] if uv else [[0, 1], [0, 1]]
                        # Wrapped coordinates need the full axis; clamp only tiny floating-point overshoot.
                        region = []
                        for (lo, hi), size in zip(bounds, image.size):
                            region.append([0, size] if lo < -0.001 or hi > 1.001 else
                                          [max(0, math.floor(lo * size) - 1), min(size, math.ceil(hi * size) + 1)])
                        rect = [region[0][0], region[1][0], region[0][1], region[1][1]]
                        if rect not in entry['wheel_regions']:
                            entry['wheel_regions'].append(rect)
                        materials.append({'slot': slot, 'name': texname, 'content': digest, 'uv_bounds': bounds})
                row['atomics'].append({'index': i, 'frame_chain': chain, 'geometry': atomic.geometry,
                                       'triangles': len(geometry.triangles), 'materials': materials,
                                       'untextured_slots': [s for s in used if not geometry.materials[s].textures]})
        if not row['atomics']:
            excluded.append({'model': model, 'name': name, 'kind': kind, 'reason': 'No atomic under a wheel frame'})
            continue
        row['also_used_on_body'] = sorted(body_names & row['textures'].keys())
        models.append(row)
        (OUTPUT / 'models' / f'{name}.dff').write_bytes(data)
    report = {'schema': 1, 'game': 'GTA San Andreas PC', 'selection': 'Every vehicles.ide model plus 17 wheel upgrades; wheel-frame descendants only, all upgrade atomics',
              'hash': 'SHA256(width,height little-endian uint32 + decoded top-level RGBA)',
              'models': models, 'textures': textures, 'excluded': excluded, 'unresolved': unresolved}
    (SOURCE / 'inventory.json').write_text(json.dumps(report, indent=2) + '\n')
    contact(report, 'originals')
    print(f'{len(models)} models; {len(textures)} distinct pixels; {len(excluded)} without wheel atomics; unresolved={unresolved}')
    for digest, t in textures.items():
        print(t['id'], t['size'], len(t['models']), ', '.join(f"{s['txd']}:{s['name']}" for s in t['sources'])[:240])


def contact(report, phase):
    entries = list(report['textures'].values())
    font = ImageFont.truetype('arial.ttf', 16)
    for start in range(0, len(entries), 24):
        batch = entries[start:start + 24]
        sheet = Image.new('RGB', (1200, math.ceil(len(batch) / 6) * 240), '#20252c')
        draw = ImageDraw.Draw(sheet)
        for i, t in enumerate(batch):
            image = Image.open(SOURCE / (t['original'] if phase == 'originals' else t['repaint']))
            image.thumbnail((192, 192), Image.Resampling.NEAREST if phase == 'originals' else Image.Resampling.LANCZOS)
            x, y = i % 6 * 200, i // 6 * 240
            sheet.paste(image.convert('RGB'), (x + (200-image.width)//2, y))
            draw.text((x+3, y+195), f"{start+i+1:02} {t['sources'][0]['name'][:17]}", fill='white', font=font)
            draw.text((x+3, y+216), f"{t['size']} x{len(t['models'])}", fill='#bdc8d4', font=font)
        sheet.save(OUTPUT / f'{phase}_{start//24+1:02}.jpg', quality=85)


def prep():
    """Registered repaint sheets, following the existing item-wheel sheet workflow."""
    report = json.loads((SOURCE / 'inventory.json').read_text())
    batches = []
    entries = []
    for t in report['textures'].values():
        name = t['sources'][0]['name']
        if name in ('vehicletyres128', 'vehiclegeneric256'):
            t['repaint'] = f'../wheel_hd/wheel/{name}.png'
            t['method'] = 'existing reviewed imagegen source; shared with wheel item'
            t['crop'] = [0, 0, *t['size']]
            continue
        regions = t['wheel_regions']
        t['crop'] = [min(v[0] for v in regions), min(v[1] for v in regions),
                     max(v[2] for v in regions), max(v[3] for v in regions)]
        entries.append(t)
    (SOURCE / 'batches').mkdir(exist_ok=True)
    for start in range(0, len(entries), 16):
        batch = entries[start:start+16]
        sheet = Image.new('RGB', (2048, 2048), (255, 0, 255))
        placements = []
        for i, t in enumerate(batch):
            im = Image.open(SOURCE / t['original']).convert('RGB').crop(t['crop'])
            scale = min(480/im.width, 480/im.height)
            size = (round(im.width*scale), round(im.height*scale))
            im = im.resize(size, Image.Resampling.NEAREST)
            x, y = i%4*512+(512-size[0])//2, i//4*512+(512-size[1])//2
            sheet.paste(im,(x,y))
            placements.append({'content': t['sha256_rgba'], 'rect': [x,y,x+im.width,y+im.height]})
        name = f'batch_{start//16+1:02}'
        sheet.save(SOURCE / 'batches' / f'{name}_input.png')
        batches.append({'name':name, 'placements': placements})
    (SOURCE / 'batches.json').write_text(json.dumps(batches,indent=2)+'\n')
    (SOURCE / 'inventory.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'{len(batches)} repaint sheets; 2 shared sources reused')


def accept(batch_number, generated):
    import shutil
    import numpy as np
    report = json.loads((SOURCE / 'inventory.json').read_text())
    batch = json.loads((SOURCE / 'batches.json').read_text())[batch_number - 1]
    raw = SOURCE / 'batches' / f"{batch['name']}_generated.png"
    shutil.copyfile(generated, raw)
    sheet = Image.open(raw).convert('RGB')
    sx, sy = sheet.width / 2048, sheet.height / 2048
    (SOURCE / 'repaints').mkdir(exist_ok=True)
    review = Image.new('RGB', (1600, len(batch['placements']) * 180), '#20252c')
    draw = ImageDraw.Draw(review)
    font = ImageFont.truetype('arial.ttf', 20)
    for i, placement in enumerate(batch['placements']):
        t = report['textures'][placement['content']]
        original = Image.open(SOURCE / t['original']).convert('RGBA')
        target = original.resize((original.width*4, original.height*4), Image.Resampling.LANCZOS)
        rect = placement['rect']
        patch = sheet.crop((round(rect[0]*sx), round(rect[1]*sy), round(rect[2]*sx), round(rect[3]*sy)))
        # Generated sheets can move their registration border by a pixel. Strip
        # only magenta registration pixels, extending the nearest painted texel.
        # This happens before resizing, so no pink fringe enters the mip chain.
        pixels = np.array(patch)
        values = pixels.astype('int16')
        mask = (values[:,:,0] > values[:,:,1]+45) & (values[:,:,2] > values[:,:,1]+45)
        t['registration_pixels_removed'] = int(mask.sum())
        while mask.any():
            old = mask.copy()
            padded = np.pad(pixels,((1,1),(1,1),(0,0)),mode='edge')
            invalid = np.pad(old,1,constant_values=True)
            for yy,xx in ((0,1),(2,1),(1,0),(1,2)):
                neighbour = invalid[yy:yy+mask.shape[0],xx:xx+mask.shape[1]]
                take = mask & ~neighbour
                pixels[take] = padded[yy:yy+mask.shape[0],xx:xx+mask.shape[1]][take]
                mask[take] = False
            if np.array_equal(mask,old):
                raise ValueError(f"{t['id']}: no painted pixels inside registration bounds")
        patch = Image.fromarray(pixels)
        box = t['crop']
        size = ((box[2]-box[0])*4, (box[3]-box[1])*4)
        patch = patch.resize(size, Image.Resampling.LANCZOS)
        # Alpha belongs to the original UV material (bike spokes etc.), never the review sheet.
        alpha = target.getchannel('A').crop(tuple(v*4 for v in box))
        patch.putalpha(alpha)
        target.paste(patch, (box[0]*4, box[1]*4))
        t['repaint'] = f"repaints/{t['id']}.png"
        t['method'] = 'imagegen registered UV-island sheet; untouched atlas regions retained; original alpha retained'
        t['batch'] = batch['name']
        target.save(SOURCE / t['repaint'])
        for col, im in enumerate((original.crop(box), patch)):
            im = im.convert('RGB')
            im.thumbnail((620, 150), Image.Resampling.NEAREST if col == 0 else Image.Resampling.LANCZOS)
            review.paste(im, (col*800+180, i*180+10))
            draw.text((col*800+8,i*180+10), 'BEFORE' if col == 0 else 'HD', fill='white', font=font)
        draw.text((10,i*180+150), f"{t['id']} {t['sources'][0]['name']}", fill='#bdc8d4', font=font)
    review.save(OUTPUT / f"{batch['name']}_review.jpg", quality=85)
    (SOURCE / 'inventory.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f"Accepted {batch['name']}: {len(batch['placements'])} registered source repaints")


def dds_bytes(image, fmt):
    levels, header = [], None
    while True:
        buf = io.BytesIO()
        image.save(buf, 'DDS', pixel_format=fmt)
        raw = buf.getvalue()
        header = bytearray(raw[:128]) if header is None else header
        levels.append(raw[128:])
        if image.size == (1, 1):
            break
        image = image.resize((max(1, image.width//2), max(1, image.height//2)), Image.Resampling.LANCZOS)
    struct.pack_into('<I', header, 8, struct.unpack_from('<I', header, 8)[0] | 0x20000)
    struct.pack_into('<I', header, 28, len(levels))
    struct.pack_into('<I', header, 108, 0x401008)  # TEXTURE | COMPLEX | MIPMAP
    return bytes(header) + b''.join(levels)


def build():
    report = json.loads((SOURCE / 'inventory.json').read_text())
    dest = RESOURCE / 'files/wheel_hd'
    dest.mkdir(parents=True, exist_ok=True)
    assets = {}
    for digest, t in report['textures'].items():
        im = Image.open(SOURCE / t['repaint']).convert('RGBA')
        if im.size != tuple(v*4 for v in t['size']):
            raise ValueError(f"{t['id']}: expected 4x source")
        box, (w, h) = t['crop'], t['size']
        # Keep mostly occupied textures on the fixed-function replacement path.
        if (box[2]-box[0])*(box[3]-box[1]) > w*h*.6:
            box = [0,0,w,h]
        patch = im.crop(tuple(v*4 for v in box))
        dims = [1 << (v-1).bit_length() for v in patch.size]
        # Pad, never stretch: the sampler transform preserves four texels per original texel.
        # Extend edge pixels so every mip has a valid border.
        import numpy as np
        arr = np.asarray(patch)
        arr = np.pad(arr, ((0,dims[1]-patch.height),(0,dims[0]-patch.width),(0,0)), mode='edge')
        padded = Image.fromarray(arr)
        fmt = 'DXT1' if padded.getextrema()[3] == (255,255) else 'DXT5'
        raw = dds_bytes(padded.convert('RGB') if fmt == 'DXT1' else padded, fmt)
        file = f"files/wheel_hd/{t['id']}.dds"
        (RESOURCE / file).write_bytes(raw)
        assets[t['id']] = {'file': file, 'format': fmt.lower(), 'size': dims,
                          'region': [box[0]/w,box[1]/h,box[2]/w,box[3]/h],
                          'transform': [w*4/dims[0],h*4/dims[1],-box[0]*4/dims[0],-box[1]*4/dims[1]],
                          'cropped': box != [0,0,w,h], 'bytes': len(raw),
                          'dds_sha256': hashlib.sha256(raw).hexdigest(),
                          'source_sha256': hashlib.sha256((SOURCE/t['repaint']).read_bytes()).hexdigest()}
    lines = ['-- Generated by python -m tools.vehicle_wheel_hd build; content hashes, not texture names.', 'return {', '    assets = {']
    for key, a in sorted(assets.items()):
        lines += [f'        ["{key}"] = {{', f'            file = "{a["file"]}", format = "{a["format"]}",',
                  f'            cropped = {str(a["cropped"]).lower()},',
                  '            region = { '+', '.join(f'{v:.9g}' for v in a['region'])+' },',
                  '            transform = { '+', '.join(f'{v:.9g}' for v in a['transform'])+' },', '        },']
    lines += ['    },', '    models = {']
    tyre = next(t['id'] for t in report['textures'].values() if t['sources'][0]['name']=='vehicletyres128')
    for r in report['models']:
        lines.append(f'        [{r["model"]}] = {{ -- {r["name"]}')
        for name, digest in sorted(r['textures'].items()):
            if name != 'vehicletyres128':
                lines.append(f'            ["{name}"] = "{digest[:16]}",')
        lines.append('        },')
    lines += ['    },',f'    tyre = "{tyre}",', '}', '']
    (RESOURCE/'shared/data/wheel_hd.lua').write_text('\n'.join(lines))
    subprocess.run(['stylua', str(RESOURCE/'shared/data/wheel_hd.lua')], check=True)
    (SOURCE/'build.json').write_text(json.dumps(assets,indent=2)+'\n')
    meta = RESOURCE/'meta.xml'
    text = meta.read_text()
    block = '\n'.join(['    <!-- wheel_hd:begin (generated by tools.vehicle_wheel_hd) -->',
                       '    <script src="client/wheel_hd.lua" type="client"/>',
                       '    <file src="shared/data/wheel_hd.lua"/>',
                       '    <file src="client/wheel_hd.fx"/>',
                       '    <file src="client/wheel_hd_crop.fx"/>'] +
                      [f'    <file src="{a["file"]}"/>' for _,a in sorted(assets.items())] +
                      ['    <!-- wheel_hd:end -->'])
    if '<!-- wheel_hd:begin' in text:
        text = re.sub(r'    <!-- wheel_hd:begin.*?<!-- wheel_hd:end -->', lambda _:block, text, flags=re.S)
    else:
        text = text.replace('</meta>', block+'\n</meta>')
    meta.write_text(text)
    print(f'{len(assets)} shared DDS: {sum(a["bytes"] for a in assets.values()):,} bytes')
    audit()


def audit():
    import xml.etree.ElementTree as ET
    report = json.loads((SOURCE/'inventory.json').read_text())
    assets = json.loads((SOURCE/'build.json').read_text())
    listed = {e.attrib['src'] for e in ET.parse(RESOURCE/'meta.xml').getroot().findall('file')}
    for t in report['textures'].values():
        a = assets[t['id']]
        source = SOURCE/t['repaint']
        assert Image.open(source).size == tuple(v*4 for v in t['size'])
        assert hashlib.sha256(source.read_bytes()).hexdigest() == a['source_sha256']
        path = RESOURCE/a['file']
        raw = path.read_bytes()
        assert a['file'] in listed and hashlib.sha256(raw).hexdigest() == a['dds_sha256']
        assert raw[:4] == b'DDS ' and raw[84:88].decode() == a['format'].upper()
        h,w = struct.unpack_from('<II',raw,12)
        assert [w,h] == a['size']
        count = struct.unpack_from('<I',raw,28)[0]
        assert count == int(math.log2(max(w,h)))+1
        total = 128
        for _ in range(count):
            total += max(1,(w+3)//4)*max(1,(h+3)//4)*(8 if a['format']=='dxt1' else 16)
            w,h = max(1,w//2),max(1,h//2)
        assert len(raw) == total
        Image.open(path).load()
    assert len(assets) == len(report['textures']) and not report['unresolved']
    actual = {p.name for p in (RESOURCE/'files/wheel_hd').glob('*.dds')}
    assert actual == {Path(a['file']).name for a in assets.values()}
    size = sum(a['bytes'] for a in assets.values())
    assert size < 8*1024*1024, f'{size} exceeds 8 MiB budget'
    print(f"Audit OK: {len(report['models'])} models, {len(assets)} contents, complete mips, {size:,} bytes ({size/2**20:.2f} MiB)")


def render(only=None):
    from tools.extract_ped_models import find_blender
    report = json.loads((SOURCE/'inventory.json').read_text())
    assets = json.loads((SOURCE/'build.json').read_text())
    for phase in ('before','after'):
        (OUTPUT/'render_textures'/phase).mkdir(parents=True,exist_ok=True)
    for t in report['textures'].values():
        orig = Image.open(SOURCE/t['original']).convert('RGBA')
        orig.save(OUTPUT/'render_textures/before'/f"{t['id']}.png")
        a = assets[t['id']]
        decoded = Image.open(RESOURCE/a['file']).convert('RGBA')
        if a['cropped']:
            whole = orig.resize((orig.width*4,orig.height*4),Image.Resampling.BILINEAR)
            b = [round(v*s*4) for v,s in zip(a['region'],[*t['size'],*t['size']])]
            whole.paste(decoded.crop((0,0,b[2]-b[0],b[3]-b[1])),(b[0],b[1]))
        else:
            whole = decoded
        whole.save(OUTPUT/'render_textures/after'/f"{t['id']}.png")
    blender = find_blender(None)
    cmd = [str(blender),'-b','-t','4','--python-exit-code','1','--python',str(ROOT/'tools/vehicle_wheel_hd_render.py')]
    if only:
        cmd += ['--',only]
    with (OUTPUT/'render.log').open('w') as log:
        result = subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(f"Blender failed; see {OUTPUT/'render.log'}")
    comparisons()


def comparisons():
    manifest = json.loads((OUTPUT/'render_manifest.json').read_text())
    font = ImageFont.truetype('arial.ttf',19)
    for start in range(0,len(manifest),12):
        rows = manifest[start:start+12]
        sheet = Image.new('RGB',(1920,math.ceil(len(rows)/3)*370),'#20252c')
        draw = ImageDraw.Draw(sheet)
        for i,r in enumerate(rows):
            x,y = i%3*640,i//3*370
            draw.text((x+8,y+3),f"{r['key']} | BEFORE / HD",font=font,fill='white')
            for col,phase in enumerate(('before','after')):
                im = Image.open(OUTPUT/'renders'/f"{r['key']}_{phase}.png").convert('RGB')
                im.thumbnail((320,320),Image.Resampling.LANCZOS)
                sheet.paste(im,(x+col*320,y+30))
        sheet.save(OUTPUT/f'blender_compare_{start//12+1:02}.jpg',quality=85)
    covered = {t for r in manifest for t in r['textures']}
    expected = set(json.loads((SOURCE/'inventory.json').read_text())['textures'])
    print(f'Blender: {len(manifest)} distinct wheel geometries, {len(covered)}/{len(expected)} contents covered')
    if covered != expected:
        print('Unrendered contents:',expected-covered)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inventory', 'prep', 'accept', 'build', 'audit', 'render'])
    parser.add_argument('--gta', type=Path, default=GTA)
    parser.add_argument('--batch', type=int)
    parser.add_argument('--image', type=Path)
    parser.add_argument('--models', help='comma-separated model ids for a render iteration')
    args = parser.parse_args()
    if args.command == 'inventory':
        inventory(args.gta)
    elif args.command == 'prep':
        prep()
    elif args.command == 'accept':
        accept(args.batch, args.image)
    elif args.command == 'build':
        build()
    elif args.command == 'audit':
        audit()
    elif args.command == 'render':
        render(args.models)


if __name__ == '__main__':
    main()
