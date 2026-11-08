# Bobcat Salvage Parts

![Bobcat](images/vehicles/422_bobcat.png)

The Bobcat pickup is the one vehicle whose body comes apart. Its hood, tailgate, two doors and two bumpers are items: a Ratchet takes them off, a crash knocks them off, and a part in hand goes back onto a Bobcat that is missing it. No other vehicle has removable parts yet.

<!-- shot:shot-bobcat-salvage -->

## The parts

Twelve items, one *Good* and one *Bad* of each part. A Good part is intact or only dented; a Bad one hangs broken, with the glass smashed on the doors.

| Part | Items |
|:--|:--|
| Hood | Bobcat Hood (Good), Bobcat Hood (Bad) |
| Tailgate | Bobcat Tailgate (Good), Bobcat Tailgate (Bad) |
| Left door | Bobcat Left Door (Good), Bobcat Left Door (Bad) |
| Right door | Bobcat Right Door (Good), Bobcat Right Door (Bad) |
| Front bumper | Bobcat Front Bumper (Good), Bobcat Front Bumper (Bad) |
| Rear bumper | Bobcat Rear Bumper (Good), Bobcat Rear Bumper (Bad) |

Every part is size 6 and is carried in both hands like a crate: it never goes into a bag or the inventory, you cannot get into a vehicle while holding one, and it rides in a trunk or a box ([Inventory](Inventory)). All twelve turn up as loot at industrial points (yards, warehouses, workshops), the Bad ones twice as often as the Good; they are never found inside vehicle trunks.

## Taking a part off

1. Hold a **Ratchet** ([Ratchet](Ratchet)).
2. Stand within 1.8 m of the part. The vehicle must be unlocked, standing still, with its engine off. The key list reads `(Hold) Remove Left Door` or the part you are nearest to.
3. Hold `F` for half a second (a tap at the bonnet is the Ratchet's repair of a slightly broken engine instead). A 4 second hold follows, shorter with the Repair [skill](Skills). A part that is still on the Bobcat takes the hold before the battery does, including the hood.

The part lands on the ground beside its slot: a Good item if it was whole or dented, a Bad one if it hung broken. Walking more than 0.8 m, changing what you hold, getting into a vehicle or dying cancels the hold, and only one person can work on a vehicle at a time. A slot that is already empty says there is no part left there to take off.

## Putting a part on

Hold the part, stand by its slot on a Bobcat and press `F` (`Install Bobcat body part` in the key list). The slot must be **empty**: to replace a dented door you take the old one off first. The 4 second hold has the same cancel rules. A Good part leaves the slot as new, a Bad part leaves it dented and hanging, but on the vehicle.

A part put on by hand is only **loose**: *Body part fitted loosely, tighten it with a Ratchet or it will shake off*. Hold a Ratchet at it and hold `F` (`(Hold) Tighten Left Door`): 3 seconds, and *Body part tightened*. Tightening trains the Repair skill. A tightened part stays on until a Ratchet takes it off or a crash does.

## Loose parts shake off

Drive with a loose part on and it comes off by itself:

- above 15 km/h there is a chance every second that one loose part flies off, growing with speed until at 75 km/h it is almost certain;
- braking hard (losing 25 km/h within a second) throws off every loose part at once.

A part that shakes off is flung ahead of the vehicle, up to 12 m, and lands as the item it was, Good or Bad.

## Crash damage

When a crash tears a part off, it drops onto the ground beside its slot as a **Bad** item, so a wreck can be stripped for parts even without a Ratchet. Parts that were already missing when the vehicle spawned never drop.

See also [Vehicles](Vehicles), [Repairing & Locks](Repairing-and-Locks) and [Tools](Tools).
