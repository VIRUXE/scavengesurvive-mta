"""The port's welding kit: a Welder, a Gas Tank and a Generator (carmour, vehicles/shared/logic/carmour.lua).

Upstream has none of them. The Welder and the Generator are the port's own models (prop_models 20202, and 20204 built
from the vanilla Y_GENERATOR); the Gas Tank is a vanilla GTA object (CJ_O2Tanks 1348). The converters add one item type per row
(tools/convert/item_types.py) and its loot rows (tools/convert/loot_tables.py). The Generator is a fuel-only machine
(items/shared/logic/machines.lua): a Petrol Can fills it, a Welder within its cable draws on it.
"""
GAS_PER_TANK = 5  # welds one Gas Tank carries; its item data is {"gas": n}
GAS_BOTTLE_CAPACITY = 11.0  # kg of propane in a full Gas Bottle; its item data is {"gas": kg} (items/shared/logic/gas.lua)

# The Welder rides the spine (SA-MP bone 1), not a hand: the two-handed carry pose (useCarryAnim) holds both hands in
# front of the belly, and the model stands there upright, control panel facing forward, its handle bar (0.31 up the
# model) laid across both palms: the offset puts the bar midway between the two hand bones (GTA nodes 24 and 34) in
# that pose, 3.5 cm down so it rests on the palms. x, y, z, rx, ry, rz as SA-MP's attach offsets, checked on the
# studio set (`rcon studio <player> hands`) with attachedit's preview (items/client/attach.lua setPreview).
WELDER_HOLD = (-0.344, 0.358, -0.040, 0.0, 90.0, 0.0)

# The Generator is a portable open-frame unit (prop_models 20204, 0.61 x 0.34 x 0.54 m: the vanilla Y_GENERATOR's body at
# half size in a chrome frame): carried like the Welder, on the spine in the two-handed pose, the frame's carry bar (0.52 up
# the model, 0.21 higher than the Welder's) across both palms; the offset is the Welder's with the bar's extra height taken
# off along the model's up axis.
GENERATOR_HOLD = (-0.554, 0.358, -0.040, 0.0, 90.0, 0.0)

# uname, name, model, size, hitpoints, loot { table: weight }, carried: a heavy two-handed hold like the Large Box
TOOLS = [
    dict(uname="Welder", name="Welder", model=20202, size=6, hp=3, loot={"world_industrial": 3.0, "vehicle_industrial": 2.0}, carry=False, att=WELDER_HOLD, bone=1, anim=True),
    dict(uname="GasTank", name="Gas Tank", model=1348, size=5, hp=3, loot={"world_industrial": 4.0, "vehicle_industrial": 3.0}, carry=False),
    dict(uname="Generator", name="Generator", model=20204, size=8, hp=5, loot={"world_industrial": 1.5}, carry=False, att=GENERATOR_HOLD, bone=1, anim=True),
    # a propane bottle (prop_models 20203, cut from the Airstream's own tanks) holding a random amount of gas; it mounts on a trailer's A-frame
    dict(uname="GasBottle", name="Gas Bottle", model=20203, size=5, hp=3, loot={"world_civilian": 4.0, "world_survivor": 6.0, "world_industrial": 8.0, "airdrop_industrial": 10.0}, carry=False),
]
