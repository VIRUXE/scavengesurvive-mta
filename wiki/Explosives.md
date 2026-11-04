# Explosives

![Explosives around a crate: the TNT, IED and EMP variants and a Molotov](images/scenes/explosives.png)

![Timed TNT](images/items/1252_barrelexpos.png) ![Proximity TNT](images/items/1576_drug_orange.png) ![IED](images/items/2033_cj_sawnoff2.png) ![EMP](images/items/343_teargas.png) ![Molotov](images/items/344_molotov.png) ![Petrol Bomb](images/items/1650_petrolcanm.png)

There are 12 charges: three kinds of explosion (TNT, IED and EMP) times four triggers (timed, proximity, trip mine and phone remote). They are crafted at a [Workbench](Workbench) with a Screwdriver.

## Charges

| Charge | Made from | Effect |
|:--|:--|:--|
| TNT (medium) | TNT | A big blast that wounds players near it and damages loose items and [defences](Defences) in range: 2 hit points to each. |
| IED (small) | A Fireworks box and a Power Supply | A smaller blast: 1 hit point of damage. |
| EMP | A Fluctuator Unit | No blast or direct health damage to nearby players. Knocks players out for 60 seconds within 12 m and switches vehicle engines off. Installed car batteries are drained to 0%, putting the headlights out and preventing a restart until the battery is replaced. Loose items and defences take no damage. |

Players near a blast are wounded in the torso or a leg and are usually knocked out. A blast destroys any loose item lying in range whose hit points are used up; other items lose hit points. Behind a [defence](Defences), a second defence on the same line (within 1 m) only takes what is left over after the first one broke. A charge that goes off in someone's hands or inventory kills them, and one inside a vehicle's storage destroys the vehicle (armoured trailer panels take the damage instead). These carried/stored-charge effects also apply to EMPs.

<!-- table:explosives -->
| Item | Charge | Trigger | Blast radius | Size |
|:--|:--|:--|--:|--:|
| Timed TNT | Medium | Timed | 8 m | 2 |
| Proximity TNT | Medium | Proximity | 8 m | 2 |
| Phone Remote TNT | Medium | Radio | 8 m | 2 |
| Trip Mine TNT | Medium | Motion | 8 m | 2 |
| Timed IED | Small | Timed | 3 m | 2 |
| Proximity IED | Small | Proximity | 3 m | 2 |
| Trip Mine IED | Small | Motion | 3 m | 2 |
| Phone Remote IED | Small | Radio | 3 m | 2 |
| Timed EMP | EMP | Timed | 12 m | 2 |
| Proximity EMP | EMP | Proximity | 12 m | 2 |
| Trip Mine EMP | EMP | Motion | 12 m | 2 |
| Phone Remote EMP | EMP | Radio | 12 m | 2 |
| Petrol Bomb | Incendiary | Timed | 5 m | 3 |
<!-- /table:explosives -->

"Blast radius" is how far item and defence damage and the EMP reach.

## Triggers

Hold the charge and press `F` to place and arm it. Your character drops it and plants it for a second.

| Trigger | How it works | Crafted with |
|:--|:--|:--|
| Timed | Goes off 5 seconds after it is armed. | Timer Device |
| Proximity | Primes after 5 seconds. Then any player who comes within 6 m sets it off, and it explodes 1 second later. That includes you. | Motion Sensor |
| Trip mine | Armed at once. Goes off when anyone interacts with it (presses `F` on it). | Accelerometer |
| Phone remote | Stays inert until synced. Hold a Mobile Phone and press `F` at the charge lying on the ground to sync the two. Then press `F` with the phone in your hands to set it off from any distance. The link is used up when it goes off. | Mobile Phone |

TNT and IED recipes pair the charge material (TNT, or an IED made at the Workbench) with the trigger part above. An EMP pairs a Fluctuator Unit with it. Everything is on the [Workbench](Workbench) page.

## Molotov

A throwable fire bomb. Combine a Bottle with a Dirty Bandage to make an Empty Molotov. Drop it, then hold a Petrol Can with petrol in it and press `F` at the bottle: 0.5 litres are poured in and it becomes a Molotov. Pick it up and throw it. Fire costs health but does not open bleeding wounds. See [Fuel](Fuel) for filling a Petrol Can.

## Petrol Bomb

A size 3 incendiary charge that arms like a timed charge: it flares up with a fire explosion after 5 seconds. It does no damage to items and has no crafting recipe.

See also [Defences](Defences), [Combining](Combining) and [Surrender & Disarm](Surrender-and-Disarm).
