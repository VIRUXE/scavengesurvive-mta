"""Hat items cut from the GTA:SA skins that carry their own headgear (#77).

Each row names one headgear mesh that tools/blender/remodel_head.py deletes from a skin (its HEADS rules) and
exports on its own as `models/files/<dff>.dff`: a static object in the skin's own texture, with the Head bone at its
origin, that `items` attaches on SA-MP bone 2 at zero offset (items/shared/logic/apparel.lua CUT_HATS). The model
ids are the port's own, above SA-MP's range (PORT_MODEL_MIN); `models/hats.lua` maps them to the files and the
converters add one item type per row (tools/convert/item_types.py) and its loot rows (tools/convert/loot_tables.py).
Skins whose headgear a SA-MP object already covers (police caps, SWAT and army helmets, the pizza cap, the beanie)
are left out, as are the cuts that are mostly hair (dwayne's mullet, bikerb's bandana).
"""
PORT_MODEL_MIN = 20001

# uname, display name, skin, ped dff name, loot: { table: weight }, blocks: the 8x8 atlas blocks (column, row; row 0 at
# the top) that are the hat. GTA models a skull patch under its hats, textured with a smear of the face, and the
# remodel rules cut it off with the hat; faces outside these blocks are left out of the object (they would show
# through its open bottom). Read off an atlas sheet with the 8x8 grid drawn over each skin's texture, then checked
# face by face in Blender with each block in its own colour (the skull patch sits well inside the crown's radius).
# `above`: blocks that are hat only from that height over the Head bone up (the bucket hat's crown top shares a
# block with the hair ring under it).
HATS = [
    dict(uname="SheriffHat", name="Sheriff's Hat", skin=283, ped="csher", loot={"world_police": 12.0, "vehicle_police": 10.0}, blocks={(3, 5), (4, 5), (5, 5), (3, 6)}),
    dict(uname="FireHelmet", name="Fire Helmet", skin=277, ped="lafd1", loot={"world_industrial": 10.0, "vehicle_industrial": 8.0}, blocks={(4, 6), (5, 6), (6, 6), (7, 6), (4, 7), (5, 7), (6, 7), (7, 7)}),
    dict(uname="GardenerHat", name="Gardener's Hat", skin=35, ped="hmogar", loot={"world_civilian": 10.0}, blocks={(5, 4), (6, 4), (7, 4)}),
    dict(uname="PilotCap", name="Pilot's Cap", skin=61, ped="wmyplt", loot={"world_civilian": 5.0, "vehicle_civilian": 4.0}, blocks={(5, 5), (6, 5), (7, 5), (1, 1), (2, 1)}),
    dict(uname="MotoHelmet", name="Motorcycle Helmet", skin=247, ped="bikera", loot={"world_civilian": 8.0, "vehicle_civilian": 8.0}, blocks={(4, 0), (5, 0), (6, 0), (7, 0)}),
    dict(uname="RanchHat", name="Rancher's Hat", skin=161, ped="cwmyfr", loot={"world_civilian": 10.0}, blocks={(6, 2), (7, 2), (6, 3), (7, 3), (6, 4), (7, 4)}),
    dict(uname="GolfCap", name="Golf Cap", skin=36, ped="wmygol1", loot={"world_civilian": 8.0}, blocks={(6, 4), (7, 4)}),
    dict(uname="BurgerHat", name="Burger Hat", skin=205, ped="wfyburg", loot={"world_civilian": 4.0}, blocks={(0, 4), (1, 4), (2, 4), (3, 4), (0, 5), (1, 5), (2, 5), (3, 5)}),
    dict(uname="BucketHat", name="Bucket Hat", skin=2, ped="maccer", loot={"world_civilian": 8.0, "world_survivor": 6.0}, blocks={(0, 3), (1, 3), (2, 3), (3, 3), (2, 4), (3, 4)}, above={(1, 4): 0.13}),
]
for _i, _h in enumerate(HATS):
    _h["model"] = PORT_MODEL_MIN + _i
    _h["dff"] = _h["ped"] + "_hat"
