"""The port's welding kit: a Welder, a Gas Tank and a Generator (carmour, vehicles/shared/logic/carmour.lua).

Upstream has none of them. The Welder is the port's own model (prop_models, id 20202); the Gas Tank and the Generator
are vanilla GTA objects (CJ_O2Tanks 1348, Y_GENERATOR 920). The converters add one item type per row
(tools/convert/item_types.py) and its loot rows (tools/convert/loot_tables.py). The Generator is a fuel-only machine
(items/shared/logic/machines.lua): a Petrol Can fills it, a Welder within its cable draws on it.
"""
GAS_PER_TANK = 5  # welds one Gas Tank carries; its item data is {"gas": n}
GAS_BOTTLE_CAPACITY = 11.0  # kg of propane in a full Gas Bottle; its item data is {"gas": kg} (items/shared/logic/gas.lua)

# uname, name, model, size, hitpoints, loot { table: weight }, carried: a heavy two-handed hold like the Large Box
TOOLS = [
    dict(uname="Welder", name="Welder", model=20202, size=6, hp=3, loot={"world_industrial": 3.0, "vehicle_industrial": 2.0}, carry=False),
    dict(uname="GasTank", name="Gas Tank", model=1348, size=5, hp=3, loot={"world_industrial": 4.0, "vehicle_industrial": 3.0}, carry=False),
    dict(uname="Generator", name="Generator", model=920, size=12, hp=5, loot={"world_industrial": 1.5}, carry=True),
    # a propane bottle (prop_models 20203, cut from the Airstream's own tanks) holding a random amount of gas; it mounts on a trailer's A-frame
    dict(uname="GasBottle", name="Gas Bottle", model=20203, size=5, hp=3, loot={"world_civilian": 4.0, "world_survivor": 6.0, "world_industrial": 8.0, "airdrop_industrial": 10.0}, carry=False),
]
