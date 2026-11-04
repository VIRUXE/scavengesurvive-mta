# Armour

![Armour](images/items/19515_swatagrey.png)

**Armour** (size 4) is a vest worn on the torso. It soaks up part of every bullet that hits your chest and wears out as it does so. For the metal panels welded onto a vehicle, see [Vehicle Armour](Vehicle-Armour).

## Wearing it

Hold the Armour and press `F`, choose `Wear` on it in the [inventory](Inventory), or click the empty `TORSO` tile while holding it. Click the tile to take it off again; putting on a second piece swaps the first one out. Other players see the vest on your character. It drops on the ground with everything else when you die or use `/dropall`.

## Points

Every piece of Armour has between **25 and 99 points**, rolled when it is made or found. The number is shown in the `TORSO` tile's caption, for example `ARMOUR (73)`. It only ever goes down.

## What it stops

Armour works against **shots to the chest** from a firearm loaded with ammunition. Nothing else touches it, and it protects nothing else: a shot to the head, an arm, the groin or a leg, a punch, a melee weapon, a fall, a fire or an explosion all hurt you as if you wore none.

When a bullet hits your chest:

- the bleed it causes is multiplied by the ammunition's **penetration** (see [Ammunition](Ammunition)), so only that fraction reaches you and starts a [wound](Bleeding-and-Wounds);
- the armour loses `(points + 10) x (bleed that got through x 10)` points.

A low-penetration round is stopped almost entirely and costs the vest little; a high-penetration round goes mostly through and still wears it down. When the points reach **0 the Armour is destroyed**: the tile empties and the next shot lands in full.

| Penetration | Ammunition |
|:--|:--|
| 0.2 | 9mm Hollow Point, 12g Flechette |
| 0.3 | 12g Improvised |
| 0.4 | 5.56 Hollow Point |
| 0.5 | 12g No. 1, 5.56 Tracer |
| 0.6 | .357 Tracer |
| 0.8 | 9mm FMJ, 5.56 FMJ, .308 FMJ |
| 0.9 | .357 FMJ, 7.62 FMJ, .50 Action Express |
| 1.0 | .50 BMG, RPG |

Worked example: a vest with 60 points takes a chest hit that would bleed 0.30 from 9mm Hollow Point (penetration 0.2). You bleed 0.06 instead of 0.30, and the vest loses (60 + 10) x (0.06 x 10) = 42 points, leaving 18.

## Hats

A hat is the head's counterpart: it does not change the damage, but it cuts the chance that a headshot knocks you out by 60 %; see [Clothes & Hats](Clothes-and-Hats).

See also [Bleeding & Wounds](Bleeding-and-Wounds), [Firearms](Firearms) and [Vehicle Armour](Vehicle-Armour).
