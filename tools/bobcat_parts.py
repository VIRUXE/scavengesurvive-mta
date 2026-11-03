"""Bobcat salvage items. Good/Bad correspond to Rockstar's original ok/dam meshes.
Build with Blender: blender -b --python tools/build_bobcat_parts.py -- SCOUT_INPUT
Prepare SCOUT_INPUT using GTA Scout prepare-asset-catalog-views.mjs, model 422.
"""
# Models are centred on their middle. Lying on the ground: (rotx, roty, rotz) turn the thin side up, and the lift
# (item modelz) is half that thickness, per mesh and condition (the damaged meshes are thicker or taller).
REST = {
    'boot': ((90, 0, 0), {'ok': 0.041, 'dam': 0.085}),
    'door_lf': ((0, 90, 0), {'ok': 0.170, 'dam': 0.091}),
    'door_rf': ((0, 90, 0), {'ok': 0.170, 'dam': 0.086}),
    'bonnet': ((0, 0, 0), {'ok': 0.070, 'dam': 0.134}),
    'bump_front': ((0, 0, 0), {'ok': 0.150, 'dam': 0.166}),
    'bump_rear': ((0, 0, 0), {'ok': 0.143, 'dam': 0.224}),
}
# Carried (hand bone offsets x, y, z, rx, ry, rz), solved from the hand's frame in the box-carry animation: doors
# upright in front of the body with the thin side forward, the tailgate across the waist, bumpers supported on
# the palms, and the hood held like a shield leaning back. The same for the good and the damaged mesh.
CARRY = {
    'boot': (0.209, -0.265, 0.002, -117.619, -23.313, -99.375),
    'door_lf': (0.216, -0.216, -0.018, -117.619, -23.313, -9.375),
    'door_rf': (0.216, -0.216, -0.018, -117.619, -23.313, -9.375),
    'bonnet': (0.293, -0.194, -0.015, -101.189, 55.447, 74.707),
    'bump_front': (0.090, 0.106, -0.181, -115.952, -13.439, -98.847),
    'bump_rear': (0.090, 0.106, -0.181, -115.952, -13.439, -98.847),
}
PARTS = [
    dict(uname='Bobcat'+label.replace(' ', '')+condition, name='Bobcat '+label+' ('+condition+')',
         model=20210+i*2+j, mesh=mesh+'_'+suffix,
         asset='bobcat_'+mesh+'_'+suffix, size=6, hp=5 if j == 0 else 2, loot={'world_industrial': 0.6 if j == 0 else 1.2}, carry=True,
         att=CARRY[mesh], rest=REST[mesh][0], modelz=REST[mesh][1][suffix])
    for i, (label, mesh) in enumerate([
        ('Tailgate', 'boot'), ('Left Door', 'door_lf'), ('Right Door', 'door_rf'),
        ('Hood', 'bonnet'), ('Front Bumper', 'bump_front'), ('Rear Bumper', 'bump_rear')])
    for j, (condition, suffix) in enumerate([('Good', 'ok'), ('Bad', 'dam')])
]
