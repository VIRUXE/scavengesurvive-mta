# Welding and carmour

Defences are attached to a vehicle, then welded on with the Welder's torch (only the towable Airstream, model 610, takes
them so far).

## Using it in game

- **Attach**: hold a defence at the trailer and press F. Attach mode shows a ghost of it where the camera aims, lying
  flat on the trailer's surface at full size and turned by the face it is on (long side level; along the trailer on the
  roof). F attaches it there, N cancels. It turns red and will not attach when it would overlap another defence, hang
  off the trailer, stand where the door swings, or when a door defence is aimed away from the door (or a panel at the
  door). Door defences (`Door`, `CrateDoor`, `ShipDoor`, `InsulDoor`) go on the door leaf only, stretched to fit it,
  and swing with it; the body takes `MetPanel`, `CorPanel`, `SmallPanel`, `WoodPanel`, `InsulPanel`, `MetalGate`.
- An attached panel weighs on the trailer (180 kg, and the tower loses 8% engine acceleration per panel, never below
  40%) but protects nothing: a Crowbar pries it off (3 s), and any blast knocks it to the ground.
- **Weld**: lay the Welder on the ground (one in hand is refused) and tap F at it to take its torch (hold F to pick the
  Welder up). The torch is tethered by 5 m of lead; walking further, taking something in hand or N puts it back. With
  the torch, F at the trailer welds the nearest attached panel within reach: an 8 s hold (shorter with the Repair
  skill) that takes one weld from a Gas Tank (5 welds, in the inventory or the bag) and 5 fuel from a Generator within
  8 m of the Welder. Fuel a Generator by holding F next to it with a Petrol Can in hand.
- **Fortified**: the door has 1 HP alone; each welded panel adds its hitpoints. While a panel is welded on, the trailer
  is damage proof and cannot blow up. Explosions eat the welded panels (the door's first), then the door's own HP, whose
  loss breaks the lock. A Crowbar or Lock Breaker is refused at the door while it is armoured.

## Where it lives

- `vehicles/shared/logic/carmour.lua` (the state, weld, damage, weight), `vehicles/shared/logic/carmour_place.lua` (the
  placement: camera ray onto the shell, frame, support, door rule, oriented-box clash test, attach offsets; the client's
  ghost and the server's check run the same code), `vehicles/server/carmour.lua` (attach, torch, weld, pry, persistence,
  mass, tow, damage), `vehicles/client/carmour.lua` (panel objects, door swing, attach mode, torches and their lead).
- `vehicles.carmour` (JSON: `{ base, next, panels = [{ id, u, hp, w, door, c, l, s, sa, sb }] }`) and the procedures
  `carmour_attach` (held defence used up), `carmour_weld` (one weld of gas), `carmour_detach` (panels back on the ground).
- Geometry: `python -m tools.carmour_geometry` (Blender + DragonFF) writes `vehicles/shared/data/carmour_geometry.lua`:
  the Airstream's shell (decimated) and door leaf, and every defence's frame and size from its DFF.
- Items: `tools/port_tools.py`; models in `prop_models` via `tools/make_props.py` (Welder 20202, Generator 20204, torch
  20205: `WELDER_SOCKET`, `TORCH_STOWED`, `TORCH_LEAD` there match the constants in `vehicles/client/carmour.lua`).

## Giving another vehicle armour

`carmour_geometry.py` and `carmour_place.lua` know one model (`geo.model`). A second vehicle needs its shell exported
and the geometry keyed by model; its door rules only apply to a walk-in door (`door = true` in `tools/convert/vspawn.py`).
