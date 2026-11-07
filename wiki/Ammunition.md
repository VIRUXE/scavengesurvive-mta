# Ammunition

![9mm and .50 rounds](images/items/2037_cj_pistol_ammo.png) ![Shotgun shells](images/items/2038_ammo_box_s2.png) ![.308 and .357 rounds](images/items/2039_ammo_box_s1.png) ![5.56 and 7.62 rounds](images/items/2040_ammo_box_m1.png)

Ammunition is carried in **tins**, items that hold a number of rounds of one kind. A tin found in the world is usually only partly full. Every [firearm](Firearms) takes one calibre, and each calibre comes in several types with their own effects.

## Calibres

Each calibre has a base bleed rate that the bullet's wound starts from; see the formula on [Firearms](Firearms).

<!-- table:calibres -->
| Calibre | Base bleed rate |
|:--|--:|
| .50 | 0.73 |
| .50 | 0.63 |
| .308 | 0.43 |
| .357 | 0.36 |
| 7.62 | 0.32 |
| 12 Gauge | 0.31 |
| 9mm | 0.25 |
| 5.56mm | 0.19 |
<!-- /table:calibres -->

## Ammunition types

- **Bleed x** multiplies the bleed rate of the wound.
- **Knockout x** multiplies the knockout chance.
- **Penetration** is how much of a shot gets through [Armour](Armour): the bleed that reaches a player wearing armour is multiplied by it.
- **Rounds** is how many a full tin holds.

<!-- table:ammo -->
| Item | Type | Calibre | Rounds | Bleed x | Knockout x | Penetration |
|:--|:--|:--|--:|--:|--:|--:|
| 9mm Rounds | Hollow Point | 9mm | 20 | 1 | 1 | 0.2 |
| .50 Rounds | Action Express | .50 | 28 | 1 | 1.5 | 0.9 |
| Shotgun Shells | No. 1 | 12 Gauge | 24 | 1.1 | 1.8 | 0.5 |
| 5.56 Rounds | FMJ | 5.56mm | 30 | 1.1 | 1.2 | 0.8 |
| .357 Rounds | FMJ | .357 | 10 | 1.2 | 1.1 | 0.9 |
| Rockets | RPG | RPG | 1 | 1 | 1 | 1 |
| 9mm Rounds | FMJ | 9mm | 20 | 1.2 | 0.5 | 0.8 |
| Shotgun Shells | Flechette | 12 Gauge | 8 | 1.6 | 0.6 | 0.2 |
| Shotgun Shells | Improvised | 12 Gauge | 14 | 1.6 | 0.4 | 0.3 |
| 5.56 Rounds | Tracer | 5.56mm | 30 | 0.9 | 1.1 | 0.5 |
| 5.56 Rounds | Hollow Point | 5.56mm | 30 | 1.3 | 1.6 | 0.4 |
| .357 Rounds | Tracer | .357 | 10 | 1.2 | 1.1 | 0.6 |
| 7.62 Rounds | FMJ | 7.62 | 30 | 1.3 | 1.1 | 0.9 |
| .50 Rounds | BMG | .50 | 16 | 1.8 | 1.8 | 1 |
| .308 Rounds | FMJ | .308 | 10 | 1.2 | 1.1 | 0.8 |
<!-- /table:ammo -->

## Loading and unloading

- Press `R` to reload the gun in your hands from its reserve.
- Hold `N` for 300 ms to unload the gun. Every round in it goes into a new tin of the same ammo type, dropped at your feet.
- The type loaded in a gun is shown in its name, for example `Desert Eagle (7/14, .357, FMJ)`. A gun with rounds in it only accepts the same type of ammunition.

## Transferring ammo

You move rounds with `F`, between whatever is in your hands and one item lying on the ground:

| In your hands | On the ground | Rounds move |
|:--|:--|:--|
| A gun | An ammo tin | From the tin into the gun: first its magazine, then its reserve. |
| A gun | Another gun | From the other gun into yours. |
| An ammo tin | A gun | From the gun into the tin. |
| An ammo tin | An ammo tin | The whole ground tin is poured into yours. |

You are told how many rounds were transferred. A tin that has been emptied disappears. The transfer is refused when:

- the calibre does not match: *Wrong calibre for weapon*;
- the gun already holds a different ammo type: *A different ammunition type is already loaded in this weapon*;
- two tins are of different types: *Ammo types can't be mixed in tins*.

A gun only takes what fits in its magazine and reserve; the rest stays in the tin.

## Scrap

Any tin can be broken down in a Scrap Machine for 1 piece of [scrap](Scrap).

See also [Firearms](Firearms) and [Explosives](Explosives).
