# Firearms

![Every firearm laid out in rows with ammunition between them](images/scenes/arsenal.png)

![M9](images/items/346_colt45.png) ![Desert Eagle](images/items/348_desert_eagle.png) ![Shotgun](images/items/349_chromegun.png) ![MP5](images/items/353_mp5lng.png) ![M16](images/items/356_m4.png) ![Sniper](images/items/358_sniper.png)

Every firearm takes one **calibre** of [ammunition](Ammunition). A gun holds a magazine (the rounds loaded in it) and can carry spare rounds in reserve. Its name in the inventory shows both: `M9 (10/7, 9mm, Hollow Point)` is a pistol with 10 in the magazine and 7 in reserve, loaded with 9mm Hollow Point rounds.

## Weapons

"Spare magazines" is how many extra magazines' worth of rounds the gun can hold in reserve. "Muzzle velocity" decides how much damage the bullet still does at range.

<!-- table:weapons -->
| Weapon | Calibre | Magazine | Spare magazines | Size | Muzzle velocity |
|:--|:--|--:|--:|--:|--:|
| M9 | 9mm | 10 | 1 | 1 | 330 m/s |
| M9 SD | 9mm | 10 | 1 | 1 | 295 m/s |
| Desert Eagle | .357 | 7 | 2 | 1 | 420 m/s |
| Shotgun | 12 Gauge | 6 | 1 | 3 | 475 m/s |
| Sawnoff | 12 Gauge | 2 | 6 | 2 | 265 m/s |
| Spas 12 | 12 Gauge | 6 | 1 | 4 | 480 m/s |
| Mac 10 | 9mm | 32 | 1 | 2 | 376 m/s |
| MP5 | 9mm | 30 | 1 | 4 | 400 m/s |
| WASR-3 | 5.56mm | 30 | 1 | 5 | 943 m/s |
| M16 | 5.56mm | 30 | 1 | 5 | 948 m/s |
| Tec 9 | 9mm | 36 | 1 | 2 | 360 m/s |
| Rifle | .357 | 5 | 1 | 5 | 829 m/s |
| Sniper | .357 | 5 | 1 | 5 | 864 m/s |
| RPG | RPG | 1 | 0 | 6 | 0 m/s |
| Heatseeker | RPG | 1 | 0 | 6 | 0 m/s |
| Minigun | 5.56mm | 100 | 1 | 7 | 853 m/s |
| Camera | Film | 24 | 4 | 2 | 1337 m/s |
| AK-47 | 7.62 | 30 | 1 | 5 | 715 m/s |
| M77-RM | .357 | 1 | 9 | 5 | 823 m/s |
| Dog's Breath | .50 | 1 | 9 | 2 | 888.8 m/s |
| Model 70 | .308 | 1 | 9 | 5 | 860.6 m/s |
| The Len-Knocks | .50 | 1 | 4 | 5 | 938.5 m/s |
<!-- /table:weapons -->

## Loading

- Hold the gun and stand over an ammo tin or another gun lying on the ground, then press `F`: rounds move into your gun, magazine first, then reserve. See [Ammunition](Ammunition).
- `R` reloads from the reserve into the magazine. A gun reloads by itself when the magazine runs dry and there are rounds in reserve.
- Hold `N` for 300 ms to unload the gun: all its rounds drop as an ammo tin.
- A gun cannot hold two different kinds of ammunition at once.
- `Y` puts the gun away or holsters it; see [Holster](Holster).

## Damage

A hit opens a wound whose bleed rate depends on the bullet's speed when it arrives, so it falls off with distance:

<!-- shot:shot-combat-tracers -->

`speed = muzzle velocity - distance ^ (1 - muzzle velocity / 11300)`

`bleed = calibre rate x speed / 1000 x ammo bleed multiplier`

The calibre rates are on the [Ammunition](Ammunition) page and the ammo multipliers in its table. The hit takes the bleed rate times 100 from the victim's health at once, and a headshot doubles the bleed. Some examples, worked out from the formula:

| Shot | Bleed rate |
|:--|--:|
| M9, Hollow Point, 10 m | about 0.08 |
| M16, FMJ, 50 m | about 0.19 |
| Model 70, FMJ, 100 m | about 0.41 |
| The Len-Knocks, BMG, 100 m | about 0.99 |

Wounds, bleeding and knockouts are explained on [Bleeding & Wounds](Bleeding-and-Wounds). Rounds with a higher knockout multiplier knock out more often.

### Range

A hit is only counted inside the weapon's range (plus 5 m of tolerance):

| Weapons | Range |
|:--|--:|
| Desert Eagle, M9, M9 SD, Dog's Breath | 35 m |
| Shotgun, Sawnoff, Spas 12 | 40 m |
| Mac 10, MP5, Tec 9 | 45 m |
| AK-47, WASR-3 | 70 m |
| Minigun | 75 m |
| M16 | 90 m |
| Rifle, M77-RM | 100 m |
| Sniper, Model 70, The Len-Knocks | 320 m |

The Desert Eagle and Dog's Breath can hurt the same target only once every 0.8 s; other guns once every 0.1 s.

## Armour and the Shield

A worn [Armour](Armour) vest lets only a fraction of a chest shot's bleed through (the ammunition's penetration) and wears down as it does; a [Shield](Small-Items#shield) held in the hands blocks shots from the front, and holstered on the back shots from behind.

See also [Melee Weapons](Melee-Weapons), [Explosives](Explosives), [Aimshout](Aimshout) and [Surrender & Disarm](Surrender-and-Disarm).
