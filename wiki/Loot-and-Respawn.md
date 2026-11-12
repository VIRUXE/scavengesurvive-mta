# Loot & Respawn

Loot and vehicles do not reset when the server restarts. The world is kept in the database, and the same stock is there after a restart as before it. New loot and new vehicles come back through a **scarcity system**: each category has a fixed carrying capacity, and new spawns are only allowed to refill what has gone missing, at a slow pace.

## The idea

- Every loot zone and the vehicle fleet have a **capacity**. A spawn is only allowed while the world holds less than that capacity.
- **Everything alive counts** against it: items on the ground, items in containers and trunks, items players carry, and vehicles players have parked. Items that are used up, destroyed or rotted away free their share.
- Hoarding is therefore deliberate scarcity: a large stockpile slows the respawn for the whole server. A trickle of new spawns always continues, so a newcomer finds something within the hour.
- Spawns never happen close to players (see below).

## Loot

### Where and when a loot point rolls

Loot lies at about 11,000 fixed loot points spread over the seven zones of the map; which zone holds what, and where the military, police and medical points are, is on [World & Zones](World-and-Zones). Points are not filled at server start. Every 5 minutes each zone earns new spawn allowance (see below) and spends it at once on points drawn at random from the whole zone, wherever the players are. A point can be drawn only if all of these hold:

- its **cooldown** has passed (see below);
- none of the items it spawned before are still there (all picked up, destroyed or rotted away);
- **no player is within 150 m** of the point, so loot never appears in front of you. Players inside an interior or in the tutorial do not count.

A roll tries 3 to 5 slots at the point (3 at many of them), and each slot produces an item only with the point's own spawn chance, 5 to 35 % depending on the point and 20 % at a typical one. Most rolls therefore leave one item or nothing, a few leave several; the items are drawn from the point's loot table, each kind at most once per roll, and never more than 6. A roll larger than the allowance left is cut short.

### Cooldown

After a point rolls, it waits 6 hours, give or take up to 50 % (3 to 9 hours), before it can roll again, even if the roll left nothing. The wait counts from the roll, not from the pickup, so a point emptied late can roll again at once.

### Capacity and refill

- A zone's capacity is 0.3 items per loot point in the zone, a quarter more for every player online after the first.
- Every 5 minutes each zone earns new spawn allowance from its deficit (capacity minus items alive):
  - 10 % of the deficit per hour, but never less than 2 % of the capacity per hour while there is any deficit;
  - allowance never exceeds the deficit, and fractions carry over between ticks.
- The allowance is placed straight away; none of it is saved up for later.

The result: an empty map fills up over about a day, and a looted-out busy area stays thin for hours, since new loot lands at random across the whole zone. The more the map is consumed or destroyed, the faster it earns allowance back, but a zone full of carried and stored items earns almost nothing beyond the 2 % trickle.

### Despawn

Loot nobody touches disappears from its point after 24 hours, and its share goes back to the zone. Picking an item up cancels its despawn timer. The items of a dead player's corpse despawn after 120 minutes unless picked up. Destroyed, eaten or used-up items free their share at once.

### What found items come with

- A gun comes with a random magazine: at military and police loot points, in police and military vehicles and in the weapon drops, 30 % are empty, 20 % part-loaded and 50 % full; elsewhere a found gun is part-loaded at best ([Firearms](Firearms)).
- A tin of ammunition is never full and never empty ([Ammunition](Ammunition)).
- Bottles, cans and cartons hold a random amount of one of their liquids or turn up empty; a Gas Bottle holds 0.5 to 11 kg of propane.
- Pills, Doctor's Bags and Auto-Injectors come with random contents ([Medical](Medical)).
- A Heart Shaped Box found as loot has four items inside.

## Vehicles

### The first roll and restarts

When the server has no vehicles at all, every vehicle spawn point is rolled once (4 % chance per point by default, then the vehicle type's own spawn chance, see [Vehicles](Vehicles)). The number of vehicles that results is the fleet capacity. From then on, restarts rebuild the vehicles from the database, where they were, with their fuel, damage and trunk contents.

### Refill

Every 5 minutes the fleet earns new vehicles by the same rule as loot: 10 % of the deficit (capacity minus vehicles alive) per hour, at least 2 % of the capacity per hour, fractions carried over. A new vehicle is placed on a random spawn point that:

- is off cooldown;
- has no vehicle still standing on it;
- has no player within 150 m.

The vehicle type is still drawn with its own spawn chance, so common types return far more often than rare ones.

### Cooldown of a spawn point

A spawn point cools down for 6 hours, give or take up to a third (about 4 to 8 hours), when:

- a vehicle spawns on it;
- its vehicle explodes while still at the point;
- its vehicle is driven more than 100 m away from it (checked once a minute).

### Abandoned vehicles and wrecks

- A vehicle that has been driven away from its spawn point and then **not used for 3 days** is removed, with its trunk and everything inside. Using it means getting in, opening its trunk, hitching it as a trailer, or using or standing in the walk-in Airstream.
- A vehicle that never left its spawn point is not removed by this rule.
- A wrecked (exploded) vehicle disappears 30 seconds later.
- Parked vehicles count against the capacity while they exist, so keeping many cars slows new spawns for everyone.

## Other respawns

These do not use the scarcity budget:

- **Boxes, crates and bags** that are part of the map (about 2,800 of them) are refilled every 15 minutes at any spot that has lost its item, unless a player is within 60 m. They come back filled: bin bags with rubbish, cartons and cardboard boxes with junk, crates with hardware, the fruit crate with fruit and the weapon crate with ammunition and now and then a weapon. See [Containers & Bags](Containers-and-Bags).
- **Trees** felled with a Chainsaw grow back 3 weeks later, including across restarts; see [Trees & Wood](Trees-and-Wood).
- **Workbenches, the scrapyard machines and the other fixed items** that are taken down or carried off are put back when the server restarts; see [World & Zones](World-and-Zones).
- **Supply drops and weapons caches** follow their own timers and player counts and do not count against any zone capacity; see [Supply Drops](Supply-Drops).

## Maps

Density of the loot points, and every vehicle spawn point by group.

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/loot.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/loot.png" alt="Maps"></a>

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/vehicles.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/vehicles.png" alt="Maps"></a>
