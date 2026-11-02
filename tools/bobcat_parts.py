"""Bobcat salvage items. Good/Bad correspond to Rockstar's original ok/dam meshes.
Build with Blender: blender -b --python tools/build_bobcat_parts.py -- SCOUT_INPUT
Prepare SCOUT_INPUT using GTA Scout prepare-asset-catalog-views.mjs, model 422.
"""
PARTS = [
    dict(uname='Bobcat'+label.replace(' ', '')+condition, name='Bobcat '+label+' ('+condition+')',
         model=20210+i*2+j, mesh=mesh+'_'+suffix,
         asset='bobcat_'+mesh+'_'+suffix, size=6, hp=5 if j == 0 else 2, loot={'world_industrial': 0.6 if j == 0 else 1.2}, carry=True)
    for i, (label, mesh) in enumerate([
        ('Tailgate', 'boot'), ('Left Door', 'door_lf'), ('Right Door', 'door_rf'),
        ('Hood', 'bonnet'), ('Front Bumper', 'bump_front'), ('Rear Bumper', 'bump_rear')])
    for j, (condition, suffix) in enumerate([('Good', 'ok'), ('Bad', 'dam')])
]
