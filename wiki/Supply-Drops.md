# Supply Drops

![A supply drop: the crate under its parachute, loot spilling out](images/scenes/supply-drop.png)

Supply drops and weapons caches are loot hotspots the server creates while it runs. Both are announced in the chat, both attract fights, and both are a container you open like a trunk or a box ([Containers & Bags](Containers-and-Bags)). They run on their own timers and do not count against the scarcity limits that govern ordinary loot and vehicles, see [Loot & Respawn](Loot-and-Respawn).

## Supply drops

A crate falls from the sky onto a preset spot on the map. The chat announces it as it starts falling, naming the place it will land; half of the time the type of the drop is hidden and shown as *Unknown*:

> [EBS]: SUPPLY DROP: "Military Weapons" INCOMING AT: "<place name>"

The crate trails smoke as it falls; the drop takes between two and a half and five minutes, less where the landing spot is high. Anyone standing where it lands is pushed clear, and the spot keeps smoking for 3 minutes. Once down the crate carries a floating *Supply Crate* label and stays where it landed until the next supply drop replaces it (contents and all); it survives a server restart.

<!-- shot:shot-supply-drop-live -->

Walk up to the crate (within about 3 m) and press `F` to open its 32 slots. A drop holds 4 to 19 items rolled from its type's table; anything that does not fit is left out.

### Types

There are five types. A type only drops while enough players are online, and each has its own timer: after a drop of that type, the next one is due after the interval plus a random extra wait. Two drops are never closer than 10 minutes. When more than one type is due, the first on this list drops. A spot is not used again for 24 hours.

| Type | Players needed | Interval | Random extra | Contents |
|:--|--:|--:|--:|:--|
| Food and Medical | 3 | 15 min | up to 10 min | Tools (wrench, screwdriver, hammer, crowbar), petrol cans, lighters, wood, seeds, tents, plant pots, food and drink, bags and backpacks, medkits, antiseptic bandages, doctor's bags, pills |
| Low Grade Weapons | 4 | 40 min | up to 20 min | Knives, bats, pistols, shotguns, Mac 10, M77-RM rifle and their ammunition |
| Military Weapons | 6 | 70 min | up to 30 min | Pistols, shotguns, MP5, M16, AK-47, rifles, sniper rifle, RPG, flamer, minigun and heavy ammunition |
| Industrial Supplies | 5 | 33 min | up to 15 min | Chainsaws, boxes, electronics (car battery, fuse box, sensors, keypad, motor, receiver), metal panels, gates and doors, wood ramps, gas bottles, angle grinder, tool battery, grinding discs |
| Ordnance Supplies | 8 | 3 h | up to 3 h | TNT and IED charges and the finished bombs and mines, EMP bombs and fluctuator units; see [Explosives](Explosives) |

When the server starts every type is already due, apart from its random extra wait.

### Landing places

A drop lands at one of 36 named spots, and the chat names the spot.

| Zone | Spots |
|:--|:--|
| Bone County | Bone County Canyons, Fort Carson, Verdant Meadows, Bone County East |
| Flint County | Mount Chilliad, Angel Pine, The Farm Flint County, Back-o-Beyond, Flint County Fallen Tree, Flint Range |
| Los Santos | Los Santos Pier, Los Santos Market Station, Los Santos Verdant Bluffs, Los Santos North Car Park, Los Santos Airport, Los Santos Jefferson Motel, Los Santos Docks |
| Las Venturas | Las Venturas Stadium, Las Venturas Airport, Las Venturas South Industrial, Las Venturas North Strip Motel, Las Venturas East Shopping Mall, Las Venturas East Building Roof |
| Red County | Blueberry, Dillimore, Montgomery, Fisher's Lagoon |
| San Fierro | San Fierro Country Club, San Fierro Hospital, San Fierro Driving School, San Fierro Square, San Fierro Promenade, San Fierro Airport |
| Tierra Robada | Tierra Robada North Freeway, Tierra Robada Midland, Tierra Robada South |

## Weapons caches

A weapons cache is a crate of military gear that appears at once on the ground, without a falling crate, at a hidden spot.

- A new cache is made every 25 to 35 minutes while no other cache is active and at least 4 players are online. It never appears within 500 m of a player.
- The server sends three chat signals, 200 seconds apart:

  > [EBS]: WEAPONS CACHE SIGNAL: BEARING: 142.0DEG DISTANCE: 612.3M

  The bearing is in degrees clockwise from north, the distance in metres, measured from a reference point that is not named. Use more than one signal to work out where it is.
- The crate carries a floating *Weapon Cache* label, holds 22 to 32 items from the Military Weapons table and opens like a supply crate (`F`, 32 slots).
- Like the supply crate, a cache stays until the next cache replaces it, and the same spot is not used twice within 24 hours.

## Tips

- Drops draw crowds: other players read the same chat. Bring a way out.
- Industrial drops carry building parts, see [Constructing](Constructing) and [Defences](Defences).

## Map

Supply drop landing points (stars) and weapon cache spots (dots).

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/drops.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/drops.png" alt="Map"></a>
