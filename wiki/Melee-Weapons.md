# Melee Weapons

Melee weapons hit at arm's length (the server accepts a hit within about 2 m). They have no damage numbers. Each weapon has a **bleed rate**, the bleeding of the wound it opens, and a **knockout** multiplier that feeds the chance of knocking the victim out. A hit also takes the bleed rate times 100 from the victim's health on the spot, so a weapon with a bleed rate of 0.35 costs 35 health plus the bleeding that follows. A blow to the head doubles the bleed rate. See [Bleeding & Wounds](Bleeding-and-Wounds) for how wounds work and [Medical](Medical) for treating them.

![Baseball Bat](images/items/336_bat.png) ![Combat Knife](images/items/335_knifecur.png) ![Sword](images/items/339_katana.png) ![Nailbat](images/items/2045_cj_bbat_nails.png) ![Sledgehammer](images/items/19631_sledgehammer1.png) ![Spade](images/items/337_shovel.png)

Fists count as a weapon too, with a bleed rate of 0.001 and a knockout multiplier of 0.5. A weapon with a bleed rate of 0 opens no wound at all.

## Bleed and knockout

Sharp weapons bleed, blunt weapons knock out.

| Weapon | Bleed rate | Knockout |
|:--|--:|--:|
| Chainsaw | 0.93 | 10 |
| Sword | 0.44 | 1.5 |
| Big Ass Sword | 0.39 | 0.15 |
| Combat Knife | 0.35 | 1.4 |
| Nailbat | 0.30 | 3.0 |
| Kitchen Knife | 0.29 | 0 |
| Screwdriver | 0.24 | 0 |
| Spade | 0.21 | 4.0 |
| Rake | 0.18 | 1.3 |
| Fork | 0.17 | 0 |
| Broom | 0.11 | 1.1 |
| Baseball Bat | 0.09 | 3.5 |
| Cane (size 3, the plain one) | 0.08 | 1.25 |
| Pool Cue | 0.08 | 3.7 |
| Golf Club | 0.07 | 3.5 |
| Cane (the walking cane) | 0.06 | 2.4 |
| Knuckle Duster | 0.05 | 2.0 |
| Baton | 0.03 | 2.4 |
| Crowbar | 0.03 | 1.25 |
| Sledgehammer | 0.03 | 2.9 |
| Hammer | 0.02 | 1.3 |
| Wrench | 0.01 | 1.2 |
| Pan | 0.01 | 1.05 |
| Frying Pan | 0.01 | 1.06 |
| Dildo, Flowers | 0.01 | 0 |
| Spatula | 0.001 | 0 |
| Mailbox, Stun Gun | 0 | - |

The Chainsaw runs on petrol as a weapon: press `F` at a Petrol Can lying on the ground to fuel it. Felling trees for Wood Logs needs no petrol at all; see [Trees & Wood](Trees-and-Wood).

The Stun Gun opens no wound: charged from a Tool Battery, its next punch knocks the victim out for 60 seconds. See [Small Items](Small-Items#stun-gun).

## Knockouts

The chance of a knockout grows with the weapon's knockout multiplier, with the number of wounds the victim already has and with their total bleed rate. Where you hit matters most: a blow to the head is far more likely to knock someone out than a blow to the body, and a worn hat cuts that chance (see [Health](Health)). Knocked-out players can be woken with [medical](Medical) items, and robbed of what they hold ([Surrender & Disarm](Surrender-and-Disarm)).

Many small melee items (Spatula, Fork, Pan and the like) have no other use but can be broken down in a [Scrap Machine](Scrap).

See also [Firearms](Firearms), [Holster](Holster) and [Item Catalogue](Item-Catalogue).
