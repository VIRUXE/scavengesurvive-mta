# Welding and carmour

Defence panels are welded onto vehicles with a Welder (only the towable Airstream, model 610, has slots so far).

## Using it in game

- **Kit**: a Welder in hand, a Gas Tank (5 welds, in the inventory or the bag), a defence panel (`MetPanel`, `CorPanel`,
  `SmallPanel`, `WoodPanel`, `InsulPanel`, `MetalGate`, `CrateDoor`, `ShipDoor`) lying within 3 m, and a Generator with
  fuel (5 per weld) within 8 m. Fuel a Generator by holding F next to it with a Petrol Can in hand.
- Press F with the Welder at the trailer: an 8 s hold (shorter with the Repair skill) fills the lowest free slot.
- The door has 1 HP alone; each panel adds its hitpoints. While at least one panel is on, the trailer is damage proof
  and cannot blow up. Explosions eat the panels, then the door's own HP, whose loss breaks the lock. A Crowbar or Lock
  Breaker is refused while the door is armoured. Each panel adds 180 kg to the trailer and costs the tower 8% engine
  acceleration (never below 40%).

## Where it lives

- `vehicles/shared/logic/carmour.lua` (pure rules and numbers), `vehicles/server/carmour.lua` (weld, persistence, mass,
  tow, damage), `vehicles/client/carmour.lua` (panel objects, door swing, sparks).
- `vehicles.carmour` (JSON) and the `carmour_weld` procedure (panel and tank used up, armour stored, one transaction).
- Slots: `python -m tools.carmour_slots` (Blender + DragonFF) regenerates `vehicles/shared/data/carmour_slots.lua`, a fixed
  placement per slot and panel type, checked so no mix overlaps (door slot at every angle). Contact sheets: `--sheets DIR`.
- Items: `tools/port_tools.py` (Welder 20202 in `prop_models` via `tools/make_props.py`, Gas Tank 1348, Generator 920),
  converters add the types and loot rows.

## Giving a vehicle slots

Describe its slots in `tools/carmour_slots.py` (it only knows the Airstream today), regenerate, then `exports.vehicles:hasCarmourSlots` is true for it. Its door
hitpoints only matter for a walk-in door (`door = true` in `tools/convert/vspawn.py`).
