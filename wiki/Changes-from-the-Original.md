# Changes from the Original

Scavenge & Survive Reborn is a port of Southclaws' Scavenge & Survive for SA-MP to Multi Theft Auto. The game is the same game; this is what a player who knows the original will notice.

## New here

- **Scarcity respawn**: loot and vehicles refill towards a budget, hoarded items count against it, nothing respawns within 150 m of a player ([Loot & Respawn](Loot-and-Respawn)).
- **Driver's dashboard** with warning lamps, a rev counter and a voltmeter ([Driver's Dashboard](Drivers-Dashboard)).
- **Car batteries** that drain, recharge, come out from under the bonnet and are flattened by an EMP, and **starter motors** that wear out ([Car Batteries & Starters](Car-Batteries-and-Starters)).
- The bonnet must be open to repair, a Wrench is needed for wheels, and a car with no wheels left freezes after 2 seconds ([Repairing & Locks](Repairing-and-Locks)).
- **Bobcat salvage parts**: hood, tailgate, doors and bumpers come off, go on and shake off when loose ([Bobcat Salvage Parts](Bobcat-Salvage-Parts)).
- A **towable Airstream** with a door, a lock and cargo that rides along, the one vehicle that takes **welded armour** ([Trailers & Towing](Trailers-and-Towing), [Vehicle Armour](Vehicle-Armour)).
- **Enterable buildings**: a farmhouse, nine trailer models (143 placements) and log cabins with interiors, glazed windows, swinging doors and loot; the original's hollow houses got 75 glazed windows and fitted entrance doors ([Houses & Trailers](Houses-and-Trailers)).
- A **camper stove** model (it does not cook yet), **Fort Defiance**'s rooftop walkways rebuilt as proper models (the rest of the fort is unchanged) and breakable roadblock **wire fences**.
- **Nine hats cut from GTA's own characters** that any skin can wear, and 22 skins with a bare head under a hat ([Clothes & Hats](Clothes-and-Hats)).
- **GTA's own boxes and crates** are containers, and any number of players can look into one at once ([Containers & Bags](Containers-and-Bags)).
- Defence doors swing on a proper hinge ([Defences](Defences)).
- A **Discord bridge** and **Rich Presence** ([Discord](Discord)), and a **voice indicator** ([Voice](Voice)).
- **Live 3D previews** of your gear in the inventory tiles ([Inventory](Inventory)).
- **Item names translated** into every language ([Languages](Languages)).
- `/report near`, `/report killer` and `/bug` ([Reports & Bans](Reports-and-Bans)).

## Changed

- Every item is a database row: nothing is lost on a restart, writes are immediate, no 60 second autosave, no 5-hour restart or re-roll ([Loot & Respawn](Loot-and-Respawn)).
- The HUD and inventory were rebuilt from recordings of the SA-MP version ([HUD](HUD), [Inventory](Inventory)).
- The 221 maps (23,211 objects) are built on your client in about 1.3 seconds on join.
- Bugs of the original are fixed: the unreachable sixth spawn skin, the bandage infecting the healer, the Heroin sky on the injector, unsaved skills, drug stacking, Air and Adrenaline applied twice.
- The spawn skin is rolled from all 29 clothes types; hats and masks fit all 310 human skins ([Clothes & Hats](Clothes-and-Hats), [Masks](Masks)).
- A death drops everything in a ring of 9 spots 1.5 m out, each facing a random way ([Death](Death)).
- A campfire takes only uncooked food and can cook again ([Campfire & BBQ](Campfire-and-BBQ)).
- An antiseptic bandage is spent, and Medical XP given, only when the treatment worked ([Medical](Medical)).
- Skills close 2 % of the gap per action, Repair shortens holds ([Skills](Skills)).
- Explosion damage passes through stacked defences ([Explosives](Explosives)); machines give one output per input ([Machines](Machines)); plants grow one step every 10 minutes ([Gardening](Gardening)).
- The Locker opens only from the front within 60°; a Gun Case or Cupboard keeps its display ([Furniture](Furniture)).
- The parachute works, tracers are lines in the world, trailers attach natively and a zipline is one line ([Parachute](Parachute), [Firearms](Firearms), [Ladders & Ziplines](Ladders-and-Ziplines)).
- 46 craft sets: 5 by combining, 13 by constructing, 28 at the workbench ([Workbench](Workbench)).
- Bans by name, IP and serial with durations, persistent mutes, aliases by IP and serial, duty keeps the character ([Reports & Bans](Reports-and-Bans)).
- Chat without player ids or bubbles, the radio tuned by frequency in a panel ([Chat](Chat), [Radio](Radio)); `/tooltips` saved per account ([Commands](Commands)); supply drop points rest 24 hours ([Supply Drops](Supply-Drops)).
- Passwords are bcrypt hashes; nothing was imported from the original's accounts ([Account & Login](Account-and-Login)).
- Ten languages with every interface text filled in ([Languages](Languages)); every entrance door is fitted to its doorway ([Houses & Trailers](Houses-and-Trailers)).

## Not here yet or dropped

- The SA-MP workarounds (widescreen, anti-ninja, bike collision), MapAndreas, the alternate worlds, filterscripts and the Go runner.
- Some staff commands: `/country`, `/allcountry`, `/delete`, `/setpinglimit`, `/gmx`, `/loadfs` and a few more; `/hudscale` and `/restartinfo`.
- Wild trees: the placement files were not available.
- The Christmas content.
- Pending: checks needing two clients at once, and interface gaps (the skin portrait in the body panel, the Drop and Move-to-bag options).
