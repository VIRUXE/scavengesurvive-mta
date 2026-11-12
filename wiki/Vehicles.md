# Vehicles

![Common vehicles: Sentinel, Bobcat, Rumpo, Sanchez, Moonbeam and Yosemite](images/scenes/vehicles.png)

![Bobcat](images/vehicles/422_bobcat.png)

Cars, trucks, bikes, boats and a few aircraft are scattered around the map. They are the fastest way to travel and their trunks carry a lot, but they need [fuel](Fuel), can be damaged and [repaired](Repairing-and-Locks), and may be locked.

## Driving

`Y` starts or stops the engine (driver only), `N` switches the lights, `R` opens the [radio](Radio), `/lock` or GTA's sub-mission control locks the doors from inside, and the vehicle secondary fire key (`LCtrl` / `Num 0`) hitches a trailer; all of them follow your bindings, see [Controls](Controls). You cannot get in while carrying a bulky item (a wheel, a panel, a box) or while you are busy repairing or refuelling.

The engine will not start with an empty tank, with a flat or missing battery (below), or when the vehicle is badly broken (health under 300). Below 450 health the engine can cut out while you drive faster than 30 km/h, more often the worse the damage. With the engine running the tank slowly drains, quicker at speed and at each type's own consumption; an empty tank stops the engine. When you get in as the driver a tip tells you how broken the vehicle is and which tool repairs it.

Four pages go deeper: [Driver's Dashboard](Drivers-Dashboard) for the warning lamps, rev counter and voltmeter the driver sees, [Car Batteries & Starters](Car-Batteries-and-Starters) for what keeps the engine turning over, [Bobcat Salvage Parts](Bobcat-Salvage-Parts) for the doors, hood, tailgate and bumpers that come off a Bobcat and go back on, and [Trailers & Towing](Trailers-and-Towing) for the hitch and the Airstream.

## Battery

![Car Battery](images/items/20208_car_battery.png)

Every vehicle with an engine under a bonnet has a battery: cars, trucks, vans, helicopters and planes. Motorbikes, bicycles, boats and the open vehicles without doors (BF Injection, Bandito, Baggage...) have none and need none.

- A vehicle found in the world holds a charge of 15 to 100 %. Below 10 % the engine will not turn over (*The battery is flat*), and a vehicle with no battery does not start at all.
- **Parked**: nothing is lost for 24 hours after the engine last ran; after that the charge drops 1 % per hour.
- **Running**: the engine charges the battery, 10 % per minute while driving (above 5 km/h) and a quarter of that while idling, so an empty battery is full after about ten minutes on the road.
- **Headlights** left on with the engine off drain 12 % per hour from the first second; below 10 % they go out. With the engine off the lights only come on with a battery of 10 % or more.

The **bonnet** of an unlocked vehicle opens and shuts with a tap of `F` at the front with empty hands (a locked vehicle says *The bonnet is locked: unlock the vehicle first*). With the bonnet open:

- a tap of `F` with empty hands lifts a **loose** battery into your hands (labelled with its charge, *Car Battery (63%)*), or a loose starter motor. A tight part stays in the bay until it is unbolted.
- a tap of `F` with a Car Battery in hand puts it into an empty slot loose. The same tap with a Starter Motor puts that in loose.
- press `F` with a **Ratchet** for the available actions: repair the engine when that tool's band applies, unbolt a tight battery or tighten a loose one, and the same for the starter motor. When several actions are available, a shared menu includes nearby ground items and vehicle actions. Scroll to choose and click to confirm; Escape closes it. The engine will not start until a loose part is tightened.

A Car Battery (size 2) keeps its charge while carried; one found as loot holds 15 to 100 %, and a flat one stays flat. Swapping a flat battery for a charged one from another vehicle is the quick way to get a car going. See [Car Batteries & Starters](Car-Batteries-and-Starters).

## EMPs and car batteries

An [EMP](Explosives) switches engines off within 12 m. Its new battery effect also drains an installed Car Battery to 0% and turns the headlights off. The car cannot restart until you fit a charged replacement; taking the flat battery out and reinstalling it does not restore its charge. The flat charge survives a normal server restart.

## Types and spawning

Every vehicle belongs to a **group** (Civilian, Industrial, Medical, Military, Police or Unique), a **type** (car, truck, motorbike, pushbike, helicopter, plane or boat) and a size (small, medium or large). Spawn points are tied to a group and to the types and sizes allowed there. Each type has its own **spawn chance**: the percentage that a given vehicle is allowed when a spawn point picks it. Rare types such as the Rhino are almost never seen.

- Each spawn point has only a small chance to hold a vehicle (4 % by default).
- Nearly every vehicle is found damaged (health mostly 300 to 500 out of 1000), with panels, doors, lights and tyres broken at random.
- Nearly every tank is almost empty; about one vehicle in ten holds more than a litre or so.
- A vehicle with a damaged door and a tank is locked half of the time.
- A vehicle driven away from its spawn point and then not used for 3 days is removed with its trunk, a wreck is gone 30 seconds after it blows up, and new vehicles come back slowly through the scarcity system, never within 150 m of a player; see [Loot & Respawn](Loot-and-Respawn).

## Trunk

Walk to the rear of an unlocked vehicle and press `F` to open the trunk. It works like a [container](Containers-and-Bags): the number of slots in the table below is counted in item sizes ([Item Sizes](Item-Sizes)). A locked trunk can be broken open, see [Repairing & Locks](Repairing-and-Locks). A trunk of 0 slots means the vehicle has none.

## Glovebox

Cars and cab trucks have a glovebox in the dash. Sit in the driver's or front passenger's seat and press `F` to open it; getting out shuts it. It is a small [container](Containers-and-Bags) of 4 slots that takes only items of size 1 (pills, notes, a phone, a knife, a pistol), so anything bigger is refused. The vehicle's lock does not matter, you are already inside. A freshly spawned vehicle may have up to two small items in it. Bikes, boats, aircraft, tanks, trailers and the Airstream have none.

## Trailers

A truck with a hitch can tow a trailer of the same size class: the small hitch (cars and pickups such as the Bobcat, Patriot or Yosemite) tows the small Trailer and Airstream, the Linerunner's large hitch tows the Articulated trailer. Back up next to the trailer and press the secondary fire key; press it again to drop it. While you drive a vehicle with a hitch the key list shows `Hitch trailer` when a free trailer is in reach (the two vehicles' lengths plus a metre, centre to centre) and `Unhitch trailer` while towing; only the driver can hitch. A trailer torn off in a crash stays off until you hitch it again, but a trailer that comes loose from an empty truck is hooked back on by itself.

The Airstream is a walk-in caravan with a door and a lock, room for cargo that rides along, two gas bottle mounts and a shell that takes [Vehicle Armour](Vehicle-Armour), which slows the towing vehicle. It is described on [Houses & Trailers](Houses-and-Trailers), together with the trailers standing around the map that can be entered but not towed.

## Overheating

The Rhino's gun overheats. A red heat bar appears at the bottom of the screen while you drive it. With the engine running every shot adds 20 heat, and heat falls by 10 a second at all times. Above 32 the bar reads *Overheating!*; above 40 an explosion goes off on the vehicle and the heat starts again from zero, so fire in short bursts.

## All vehicles

Fuel tank is in litres, trunk in slots, spawn chance in percent.

<!-- table:vehicles -->
|  | Vehicle | Type | Group | Fuel tank | Trunk slots | Spawn chance |
|:--|:--|:--|:--|--:|--:|--:|
|  | Coastguard | boat | Police | 120 L | 24 | 35 |
|  | Dinghy | boat | Civilian | 81 L | 10 | 64 |
|  | Launch | boat | Military | 213 L | 26 | 40 |
|  | Marquis | boat | Civilian | 900 L | 100 | 50 |
|  | Reefer | boat | Civilian | 245 L | 48 | 60 |
|  | Squalo | boat | Civilian | 50 L | 28 | 20 |
|  | Tropic | boat | Civilian | 260 L | 44 | 55 |
|  | Vortex | boat | Unique | 45 L | 4 | 0.1 |
|  | Baggage | car | Industrial | 14.5 L | 8 | 35.5 |
|  | Blista Compact | car | Civilian | 40 L | 38 | 68 |
|  | Bloodring Banger | car | Unique | 65 L | 32 | 0.5 |
|  | Clover | car | Civilian | 62 L | 34 | 75 |
|  | Comet | car | Civilian | 50 L | 20 | 10 |
|  | Doomride | car | Unique | 180 L | 80 | 0.5 |
|  | Moonbeam | car | Civilian | 60 L | 65 | 30 |
|  | Police Car | car | Police | 78 L | 42 | 80 |
|  | Police Car | car | Police | 70 L | 42 | 80 |
|  | Police Car | car | Police | 75 L | 42 | 80 |
|  | Regina | car | Civilian | 74 L | 48 | 75 |
|  | Sabre | car | Civilian | 60 L | 24 | 17 |
|  | Scimitar | car | Unique | 56 L | 24 | 3.3 |
|  | Sentinel | car | Civilian | 58.8 L | 42 | 78 |
|  | Sultan | car | Civilian | 65 L | 40 | 15 |
|  | Tampa | car | Civilian | 58 L | 38 | 64 |
|  | Maverick | helicopter | Civilian | 240 L | 32 | 1 |
|  | Seasparrow | helicopter | Civilian | 96 L | 10 | 0.31 |
|  | Faggio | motorbike | Civilian | 8 L | 10 | 45 |
|  | Freeway | motorbike | Civilian | 19 L | 15 | 8 |
|  | HPV1000 | motorbike | Police | 60 L | 15 | 45 |
|  | Sanchez | motorbike | Civilian | 10 L | 8 | 15 |
|  | Wayfarer | motorbike | Civilian | 47 L | 15 | 10 |
|  | Rustler | plane | Civilian | 88 L | 15 | 0.8 |
|  | Mountain Bike | pushbike | Civilian | 0 L | 2 | 8 |
|  | APC-30 | truck | Unique | 60 L | 0 | 0.1 |
|  | Airstream | truck | Civilian | 0 L | 0 | 3 |
|  | Ambulance | truck | Medical | 80 L | 70 | 30 |
|  | Articulated | truck | Industrial | 0 L | 100 | 1 |
|  | BF Injection | truck | Civilian | 40 L | 24 | 15 |
|  | Bandito | truck | Unique | 48 L | 15 | 0.1 |
|  | Barracks | truck | Military | 200 L | 100 | 3 |
|  | Bobcat | truck | Civilian | 60 L | 40 | 76 |
|  | Boxville | truck | Industrial | 75 L | 70 | 55 |
|  | DFT-30 | truck | Industrial | 60 L | 0 | 35 |
|  | Duneride | truck | Civilian | 180 L | 85 | 10 |
|  | Enforcer | truck | Police | 90 L | 64 | 10 |
|  | FBI Truck | truck | Police | 80 L | 45 | 3 |
|  | Firetruck | truck | Medical | 115 L | 65 | 0.5 |
|  | Flatbed | truck | Industrial | 70 L | 100 | 15 |
|  | Huntley | truck | Civilian | 70 L | 50 | 57 |
|  | Journey | truck | Civilian | 60 L | 76 | 10 |
|  | Linerunner | truck | Industrial | 120 L | 12 | 5 |
|  | Mesa | truck | Civilian | 77 L | 48 | 70 |
|  | Patriot | truck | Military | 94 L | 50 | 22 |
|  | Rancher | truck | Civilian | 110 L | 52 | 44 |
|  | Ranger | truck | Police | 110 L | 48 | 30 |
|  | Rhino | truck | Military | 1900 L | 12 | 0.01 |
|  | Roadpain | truck | Unique | 210 L | 0 | 1.4 |
|  | Rumpo | truck | Industrial | 55 L | 80 | 45 |
|  | Sadler | truck | Civilian | 60 L | 40 | 34 |
|  | Sandking | truck | Unique | 120 L | 46 | 3.5 |
|  | Steamroller | truck | Unique | 60 L | 0 | 0.1 |
|  | Trailer | truck | Industrial | 0 L | 50 | 20 |
|  | Truckfort | truck | Unique | 265 L | 76 | 1.1 |
|  | Tug | truck | Industrial | 10 L | 8 | 10 |
|  | Walton | truck | Civilian | 60 L | 46 | 40 |
|  | Yankee | truck | Industrial | 60 L | 80 | 40 |
|  | Yosemite | truck | Civilian | 60 L | 44 | 70 |
<!-- /table:vehicles -->

## Map

Every vehicle spawn point, coloured by group.

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/vehicles.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/vehicles.png" alt="Map"></a>
