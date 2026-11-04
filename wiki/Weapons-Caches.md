# Weapons Caches

A weapons cache is a crate of military gear that the server hides somewhere on the map while it runs. It is announced only by three radio signals giving a bearing and a distance, never by name or place, so finding it is a navigation puzzle before it is a fight. [Supply Drops](Supply-Drops) are the other kind of server-made hotspot; the two share a page section there, and this page covers the cache alone.

## When one appears

- A new cache is made every 25 to 35 minutes, while at least 4 players are online and no other cache is active.
- It is placed at one of 186 fixed positions, all of them in and around San Fierro, and never within 500 m of a player.
- The same position is not used again for 24 hours.
- A cache stays until the next one replaces it, together with whatever is still in it, and it survives a server restart: a cache made last night is still there in the morning if nobody found it.

The crate appears on the ground at once. Nothing falls from the sky, there is no smoke and the chat does not name a place.

## The signals

The server sends three lines to everyone, 200 seconds apart:

> [EBS]: WEAPONS CACHE SIGNAL: BEARING: 142.0DEG DISTANCE: 612.3M

The bearing is in degrees clockwise from north, the distance in metres, both measured from a **reference point** that is not the cache and is not named: one of the other cache positions, picked at random within a kilometre of the cache. Each of the three signals uses its own reference point. A single signal therefore tells you little; three bearings from three unnamed points narrow it down to the streets of San Fierro where the cache positions cluster, and the map of them at the bottom of [Supply Drops](Supply-Drops) shows where those are. Your [watch](Watch) gives your own bearing.

## What it holds

The crate carries a floating *Weapon Cache* label. Stand within 3 m and press `F` to open it: a container of 32 slots that works like a trunk or a box ([Containers & Bags](Containers-and-Bags)), with nothing to pick up behind it. It is filled with 22 to 32 items rolled from the Military Weapons table (pistols, shotguns, MP5, M16, AK-47, rifles, the sniper rifle, RPG, flamer, minigun and heavy ammunition, see [Firearms](Firearms) and [Ammunition](Ammunition)). Items are counted in [sizes](Item-Sizes), so the 32 slots fill up after about nine weapons and ammunition tins; anything rolled that no longer fits is left out, and nothing lies on the ground around the crate.

## Cache or supply drop

| | Weapons cache | Supply drop |
|:--|:--|:--|
| Announced by | three bearing and distance signals | one line naming the landing place |
| Arrives | on the ground at once | falls for 2.5 to 5 minutes, smoking |
| Where | 186 hidden positions, all around San Fierro | 36 named spots across the map |
| Players needed | 4 | 3 to 8 by type |
| Holds | 22 to 32 military items | 4 to 19 items of one of five types |
| Rest | one at a time, 25 to 35 minutes apart | one per type on its own timer, 10 minutes apart at least |

Both open with `F`, both hold 32 slots, both are replaced by the next of their kind and both run outside the scarcity budget that governs ordinary loot ([Loot & Respawn](Loot-and-Respawn)). A cache is worth more and draws everyone who can read a compass, so expect company at the end of the third signal.

See also [Supply Drops](Supply-Drops), [World & Zones](World-and-Zones) and [Firearms](Firearms).
