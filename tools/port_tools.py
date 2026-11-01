"""The port's welding kit: a Welder, a Gas Tank and a Generator (carmour, vehicles/shared/logic/carmour.lua).

Upstream has none of them. The Welder is the port's own model (prop_models, id 20202); the Gas Tank and the Generator
are vanilla GTA objects (CJ_O2Tanks 1348, Y_GENERATOR 920). The converters add one item type per row
(tools/convert/item_types.py) and its loot rows (tools/convert/loot_tables.py). The Generator is a fuel-only machine
(items/shared/logic/machines.lua): a Petrol Can fills it, a Welder within its cable draws on it.
"""
GAS_PER_TANK = 5  # welds one Gas Tank carries; its item data is {"gas": n}

# uname, name, model, size, hitpoints, loot { table: weight }, carried: a heavy two-handed hold like the Large Box
TOOLS = [
    dict(uname="Welder", name="Welder", model=20202, size=6, hp=3, loot={"world_industrial": 3.0, "vehicle_industrial": 2.0}, carry=False),
    dict(uname="GasTank", name="Gas Tank", model=1348, size=5, hp=3, loot={"world_industrial": 4.0, "vehicle_industrial": 3.0}, carry=False),
    dict(uname="Generator", name="Generator", model=920, size=12, hp=5, loot={"world_industrial": 1.5}, carry=True),
]
