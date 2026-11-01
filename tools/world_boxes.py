"""GTA's own boxes, crates and bags, cut out of the map and made into carried items.

Every placement of a SOURCES model (the Rockstar IPLs and upstream's maps) is removed on each client and its boxes
come back as items: tools/extract_world_boxes.py cuts each model into its loose parts in Blender (DragonFF), keeps
the parts that are a box, a crate or a bag (`whole` models are one part as they are) and writes each distinct part
once as a port model in box_models/files/, base at z 0 and squared to its footprint. What is not a box (a pallet, a
plank, a plastic sheet) stays in the world as the source's remnant model. PARTS names each distinct part by the
signature the extractor prints; tools/convert/item_types.py makes them item types, tools/convert/world_boxes.py turns
the placements into item spots (world/data/boxes.lua) and the removals and remnants into maps/data/BOXES.lua.
"""

# model, dff and txd name (gta3.img, else gta_int.img); `whole`: the model is one item, its loose parts are not
# looked at; `remnant`: the port id of what is left of a composite once its boxes are items
SOURCES = [
    {"model": 1220, "dff": "cardboardbox2", "txd": "boxes", "whole": True},
    {"model": 1221, "dff": "cardboardbox4", "txd": "boxes", "whole": True},
    {"model": 1230, "dff": "cardboardbox", "txd": "boxes", "whole": True},
    {"model": 1224, "dff": "woodenbox", "txd": "boxes", "whole": True},
    {"model": 1264, "dff": "BlackBag1", "txd": "drubish", "whole": True},
    {"model": 1265, "dff": "BlackBag2", "txd": "drubish", "whole": True},
    {"model": 2912, "dff": "temp_crate1", "txd": "kmb_crateX", "whole": True},
    {"model": 1431, "dff": "DYN_BOX_PILE", "txd": "BREAK_S_BOX"},
    {"model": 1438, "dff": "DYN_BOX_PILE_2", "txd": "BREAK_S_BOX"},
    {"model": 1440, "dff": "DYN_BOX_PILE_3", "txd": "BREAK_S_BOX"},
    {"model": 1441, "dff": "DYN_BOX_PILE_4", "txd": "BREAK_S_BOX", "remnant": 20481},
    {"model": 1299, "dff": "smashboxpile", "txd": "boxes"},
    {"model": 923, "dff": "Packing_carates2", "txd": "crates_n_stuffext", "remnant": 20482},
    {"model": 944, "dff": "Packing_carates04", "txd": "crates_n_stuffext", "remnant": 20483},
    {"model": 3576, "dff": "DockCrates2_LA", "txd": "sjmla_las", "remnant": 20484},
    {"model": 3577, "dff": "DockCrates1_LA", "txd": "sjmla_las", "remnant": 20485},
    {"model": 1558, "dff": "CJ_CARDBRD_PICKUP", "txd": "CJ_BOX1", "remnant": 20486},
    {"model": 1450, "dff": "DYN_CRATE_3", "txd": "BREAK_Pallet", "remnant": 20487},
]

# one row per item: the signatures of its parts as tools/extract_world_boxes.py --survey prints them (the first one's
# mesh is the model, near twins of it share the item), the port model id (20401+), item size (upstream SmallBox 4,
# LargeBox 6) and hitpoints; `holds`: [size, fill], the item is a container of that size and world/server/boxes.lua
# fills it from that table of world/shared/logic/boxes.lua FILLS when it spawns
PARTS = [
    {"uname": "Carton", "name": "Carton", "model": 20401, "sigs": ["7c0b4b8fae"], "size": 4, "hp": 4, "holds": [8, "junk"]},
    {"uname": "CardboardBox", "name": "Cardboard Box", "model": 20402, "sigs": ["3c786449f7"], "size": 4, "hp": 4, "holds": [8, "junk"]},
    {"uname": "LargeCarton", "name": "Large Carton", "model": 20403, "sigs": ["4ac36bd06d", "0a550d6d5f"], "size": 6, "hp": 5, "holds": [10, "junk"]},
    {"uname": "OpenCardboardBox", "name": "Open Cardboard Box", "model": 20404, "sigs": ["79756885be"], "size": 4, "hp": 4, "holds": [8, "junk"]},
    {"uname": "OpenCarton", "name": "Open Carton", "model": 20405, "sigs": ["4c4151fdb1"], "size": 4, "hp": 4, "holds": [6, "junk"]},
    {"uname": "WoodenCrate", "name": "Wooden Crate", "model": 20406, "sigs": ["897a546e84"], "size": 6, "hp": 6, "holds": [10, "crate"]},
    {"uname": "FruitCrate", "name": "Fruit Crate", "model": 20407, "sigs": ["4d36b5e399"], "size": 4, "hp": 5, "holds": [8, "fruit"]},
    {"uname": "SmallCrate", "name": "Small Crate", "model": 20408, "sigs": ["cc6422a514"], "size": 4, "hp": 5, "holds": [8, "crate"]},
    {"uname": "LongCrate", "name": "Crate", "model": 20409, "sigs": ["d9d54ffb22"], "size": 4, "hp": 5, "holds": [8, "crate"]},
    {"uname": "BigCrate", "name": "Big Crate", "model": 20410, "sigs": ["7255aa71ea"], "size": 6, "hp": 6, "holds": [10, "crate"]},
    {"uname": "PackingBox", "name": "Packing Box", "model": 20411, "sigs": ["f254c60b24"], "size": 4, "hp": 4, "holds": [10, "junk"]},
    {"uname": "ShippingBox", "name": "Shipping Box", "model": 20414, "sigs": ["bdea89146d"], "size": 4, "hp": 5, "holds": [8, "junk"]},
    {"uname": "BinBag", "name": "Bin Bag", "model": 20415, "sigs": ["3b3260b1e7"], "size": 3, "hp": 3, "holds": [6, "trash"]},
    {"uname": "RubbishBag", "name": "Rubbish Bag", "model": 20416, "sigs": ["df480744aa"], "size": 3, "hp": 3, "holds": [6, "trash"]},
    {"uname": "TrashBag", "name": "Trash Bag", "model": 20417, "sigs": ["eb0b748e79", "c022ac26cd", "3383f52803"], "size": 3, "hp": 3, "holds": [6, "trash"]},
    {"uname": "WeaponCrate", "name": "Weapon Crate", "model": 20418, "sigs": ["d373c14cec"], "size": 6, "hp": 6, "holds": [10, "weapons"]},
]

# parts that are boxes by shape but stay where GTA put them, in their source's remnant: the 1.5 m dock crates
STATIC = ["138faca3a1", "86c280e4e8"]

# parts that are two crates in one mesh, cut at the middle into two boxes of their own (their signatures as --survey prints
# them): the 1.85 m and 2.89 m pairs of the first import, now the Crate (LongCrate) and the Big Crate
DOUBLES = ["091f4c05b1", "1ef612862e"]
