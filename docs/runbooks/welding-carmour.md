# Welding and carmour

Defences are attached to a vehicle, then welded on with the Welder's torch (only the towable Airstream, model 610, takes
them so far).

## Using it in game

- **Attach**: hold a defence at the trailer and press F. Attach mode shows a ghost of it where the camera aims, lying
  flat on the trailer's surface at full size and turned by the face it is on (long side level; along the trailer on the
  roof). F attaches it there, N cancels. Only metal defences can be welded on: the body takes `MetPanel`, `CorPanel`,
  `SmallPanel` and `MetalGate`; the door leaf takes `CrateDoor` or `ShipDoor` only, stretched to fit it, swinging with it
  (`WoodPanel`, `InsulPanel`, `InsulDoor` and `Door` are refused). The ghost turns red and will not attach when it would
  overlap another defence, touch any part of the trailer (the body, step, hitch or A-frame gas tanks: tested triangle by
  triangle, the panel pushed out until clear), stand more than 0.8 m off the body, have less than 70% of its face over
  the body within 0.4 m, sit under the floor or reach into the ground, stand where the door swings, or when it is aimed
  at an inside surface (where it holds on must be the outer skin: four of five rays fanned out from it leave the trailer).
- An attached panel weighs on the trailer (180 kg, and the tower loses 8% engine acceleration per panel, never below
  40%) but protects nothing: a Crowbar pries it off (3 s), and any blast knocks it to the ground.
- **Weld**: lay the Welder on the ground (one in hand is refused) and tap F at it to take its torch (hold F to pick the
  Welder up). The torch is tethered by 5 m of lead; walking further, taking something in hand or N puts it back. With
  the torch, F at the trailer welds the nearest attached panel within reach: an 8 s hold (shorter with the Repair
  skill) that burns gas by the defence's toughness, 0.44 kg per hitpoint it can take (a 4 HP Metal Gate 1.8 kg, a 5 HP
  Metal Panel 2.2 kg, a 9 HP Ship Door 4.0 kg), and 5 fuel from a Generator within 8 m of the Welder. Fuel a Generator by
  holding F next to it with a Petrol Can in hand.
- **Gas**: a Gas Cylinder (the `Canister` item, 20 kg full) or a Gas Bottle (11 kg) lying within 2.5 m of a Welder on the
  ground, hooked up to it: with empty hands tap F at it ("Hook up to welder"; again to unhook, hold F to pick it up). A
  hose is drawn between them. One gas per Welder; picking up or moving either undoes the link (the Welder's item data
  `{cylinder, wx, wy, gx, gy}` keeps where both lay; the server checks every 4 s and publishes the live links as the
  `vehicles.hoses` element data on the resource root). Gas carried in the inventory does not feed the Welder.
- **Fortified**: the door has 1 HP alone; each welded panel adds its hitpoints. While a panel is welded on, the trailer
  is damage proof and cannot blow up. Explosions eat the welded panels (the door's first), then the door's own HP, whose
  loss breaks the lock. A Crowbar or Lock Breaker is refused at the door while it is armoured.
- **Grinding off**: an Angle Grinder in hand, tap F at the trailer: a 20 s pass at the nearest welded panel within reach
  (walking off cancels it, nothing is used). Each pass burns one charge of a Tool Battery (3 per Tool Battery, item data
  `{charge}`) and wears a Grinding Disc (6 passes, data `{wear}`; a worn-out disc is gone), both taken from the
  inventory or the bag. The panel keeps its passes (`g`), so the cut can be finished later or by someone else; the
  sixth pass (two minutes in all) cuts it through and it drops to the ground, unwelded, with the HP it had.

## Where it lives

- `vehicles/shared/logic/carmour.lua` (the state, weld, damage, weight), `vehicles/shared/logic/carmour_place.lua` (the
  placement: camera ray onto the shell, frame, support, door rule, oriented-box clash test, attach offsets; the client's
  ghost and the server's check run the same code), `vehicles/server/carmour.lua` (attach, torch, weld, pry, grind, persistence,
  mass, tow, damage), `vehicles/client/carmour.lua` (panel objects, door swing, attach mode, torches and their lead).
- `vehicles.carmour` (JSON: `{ base, next, panels = [{ id, u, hp, w, door, c, l, s, sa, sb, g }] }`) and the procedures
  `carmour_attach` (held defence used up), `carmour_weld` (one weld of gas), `carmour_grind` (one pass: a Tool Battery
  charge, a disc's wear, the panel's progress), `carmour_detach` (panels back on the ground).
- Geometry: `python -m tools.carmour_geometry` (Blender + DragonFF) writes `vehicles/shared/data/carmour_geometry.lua`:
  the Airstream's shell (decimated) and door leaf, and every defence's frame and size from its DFF.
- Items: `tools/port_tools.py`; models in `prop_models` via `tools/make_props.py` (Welder 20202, Generator 20204, Angle
  Grinder 20206, Grinding Disc 20207, torch 20205: `WELDER_SOCKET`, `TORCH_STOWED`, `TORCH_LEAD` there match the constants in `vehicles/client/carmour.lua`).

## Giving another vehicle armour

`carmour_geometry.py` and `carmour_place.lua` know one model (`geo.model`). A second vehicle needs its shell exported
and the geometry keyed by model; its door rules only apply to a walk-in door (`door = true` in `tools/convert/vspawn.py`).
