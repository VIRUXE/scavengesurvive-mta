# Vehicle salvage parts (every car and truck)

The Bobcat's parts (`bobcat-parts.md`, ids 20210–20221) were the first. Every other car and truck the game spawns has its
own set: 35 sets, 414 items, port model ids 21001–21414 in the `car_part_models` resource. The mechanics (remove with a
Ratchet, fit into an empty slot, tighten, loose parts shake off, crash drops) are the Bobcat's, unchanged, for every
model listed in `vehicles/shared/logic/bodyparts.lua` `MODELS`.

## How a set is made

`tools/car_parts.py` is the manifest and the driver; `tools/car_parts_blender.py` is the Blender side (DragonFF).

```
python -m tools.car_parts survey      # per model: its ok/dam frames, slot points, groundDrop -> tools/data/car_parts_survey.json
python -m tools.car_parts build       # cuts every part, writes car_part_models/files + tools/data/car_parts.json
python -m tools.car_parts manifest    # car_part_models/parts.lua + meta.xml
python -m tools.car_parts print items|seed|rest|order|models|loot   # text for the hand-edited data files
```

It reads each car's DFF and TXD straight from `models/gta3.img` (the game at `D:/Games/gtasa`, Blender 5.3 + DragonFF
on the Windows box). A model gets the slots whose `<part>_ok` frame its DFF has (`bonnet`, `boot`, `door_lf/rf/lr/rr`,
`bump_front/rear`); a missing `_dam` mesh falls back to the `_ok` one. Each part is the vehicle's own mesh, centred,
the hood and trunk made double-sided, prelit, its paint markers turned into the model's first `carcols.dat` pair, with a
box collision. Every part draws from one shared `car_parts.txd` holding only the textures the parts use; a texture name
two cars' TXDs use with different pixels is renamed `<name>_<model>` (copcarla/copcarvg's interior).

Slot points (where a player stands, in the vehicle's frame) and `groundDrop` come from the panel boxes and the wheel
dummies, offset to match the Bobcat's hand-placed points. The rest poses (`rotx/y/z`, `modelz`, `item_rest.lua` rows)
are the thin side up, bumpers on their edge; the carry offsets are the Bobcat's per kind of panel.

`SHARE` maps a model onto another's set when the bodies match (Police SF onto Police LS, Ranger onto Rancher): it gets a
`MODELS` entry with the owner's prefix, so the same items fit both. Variants of one GTA model share automatically.

## Data

Hand-edited from the `print` output: `data/generated/item_types.lua` (rows after the Bobcat's, unames in `M.order`),
`sql/seed/0001_item_types.sql` (and the live DB), `loot/shared/item_rest.lua`, `bodyparts.lua` `MODELS`, and the loot
rows. Item names are `partName` templates (`"%s Hood (Good)"`) with `partVehicle` put in by `lib` `lang.itemType` and
`data` `itemName`, so each language translates about 18 templates instead of 800 names.

Loot (`print loot`): a fixed total weight per table (`LOOT_BUDGET`: 12 in `world_industrial`, 4 in
`vehicle_industrial`), split between the sets by the summed spawn chance of the vehicles each fits, evenly over a set's
slots, Bad twice the Good, floored at 0.005 / 0.01. The Bobcat's set takes its share.

## Deploying a new set

A new resource needs its ACL entry (`resource.car_part_models` in the `ScavengeSurvive` group) and its startup line
(`server-config/resources.xml`, `mtaserver.conf`); clients download about 6 MB and load every part model on start.
