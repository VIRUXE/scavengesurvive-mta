# Bleeding & Wounds

Every hit that draws blood leaves a wound and raises your bleed rate, and an untreated bleed is the commonest way to die. This page covers wounds, the bleed rate, what other players see of it and how to stop it; the items themselves are on [Medical](Medical).

## Wounds

A hit that bleeds adds one wound to your count. Wounds come from:

- bullets and melee hits (see [Firearms](Firearms) and [Melee Weapons](Melee-Weapons)): a headshot doubles the bleed and knocks your hat and mask off, worn [Armour](Armour) softens a chest shot, and a Shield can stop a shot outright;
- long falls: a leg wound, more likely and heavier the harder the landing. A short drop does nothing;
- being rammed or run over by a vehicle: a wound to the torso or a leg whose bleed grows with the vehicle's speed (about 0.04 at 50 km/h). Above 55 km/h you can also be knocked out, longer the faster the vehicle. The driver gets the credit, and the kill;
- explosions: a wound to the torso or a leg, bleeding up to 0.5 right at the blast, with a very high chance of a knockout. See [Explosives](Explosives).

Drowning leaves no wound: every mouthful costs up to 10 health and knocks you out for 1.5 to 3 seconds. Fire only costs health, a tenth of what the flames would take.

Every wound shows as action text, `Wounded: <body part>  -N hp`, with `(bleeding)` when it added to your bleed rate; the inventory's Health Status panel counts your wounds per body part.

Wounds do not heal by themselves. They make a knockout more likely (see [Health](Health)) and slow how fast a bleed clots. A Medkit or Doctor's Bag removes wounds.

Only the bleed rate is saved when you log out. If you log back in still bleeding you come back with one wound.

## Bleed rate

Each wound adds to your bleed rate, a number from 0 to 1 that is capped at 1. Every weapon, ammunition type and body part has its own bleed; a headshot doubles it. Worn [Armour](Armour) cuts the bleed of chest shots.

While the rate is above 0:

- every second there is a 70 % chance that you lose health equal to the rate (a rate of 0.1 costs about 0.07 health per second);
- you do not regenerate health;
- every second there is a 50 % chance that the rate falls a little by itself. It falls faster the lower your health is and slower the more wounds you have.

The Health Status panel in the inventory shows the rate as `Bleed: 0.00`. It is green when it reads 0.00 and red otherwise.

## What others see

A bleeding character sprays blood from the chest and drops a pool of blood at their feet every second while the bleed shows. Whether it shows is re-rolled every second: the higher the rate, the more often it does, and at 0.1 and above it always does. A trail holds the last 15 pools of its owner, the oldest replaced by the newest; pools lie on the ground where they fell, everyone sees the same trail, and it stays for 10 minutes after its owner leaves the server. Players in vehicles, and staff on duty, do not spray or leave pools.

## Tracers

Tracer rounds (the *Tracer* ammunition of the 5.56 and .357 calibres, see [Ammunition](Ammunition)) draw a bright streak behind every shot that everyone can see: it appears 2 m past the muzzle and flies at 800 m/s to where the bullet lands, 6 m long. They give away where a shooter stands.

## Stopping the bleed

Hold the interact key (`F`) with the item in your hands, on yourself or on a player next to you (within 1.5 m). The hold takes 4 seconds (6 seconds on an unconscious patient) and is cancelled by letting go or moving away. The [Medical](Medical) skill shortens it.

| Item | Effect on the bleed |
|:--|:--|
| Dirty Bandage | reduces the rate; 33 % chance to give the patient a [wound infection](Infection) |
| Antiseptic Bandage | reduces the rate and cures a wound infection; never infects |
| Medkit | reduces the rate and removes wounds |
| Doctor's Bag | stops the bleed completely and removes wounds |

![Dirty Bandage](images/items/11747_bandage1.png) ![Antiseptic Bandage](images/items/11748_bandagepack1.png) ![Medkit](images/items/11736_medicalsatchel1.png) ![Doctor's Bag](images/items/11738_mediccase1.png)

A bandage cuts a small bleed almost to nothing and a heavy one only a little, so a bad bleed needs several bandages or a Medkit. A rate under 0.005 counts as stopped. A bandage is used up when it works; if there is no bleed it is not spent.

Medkits remove 1 to 2 wounds from yourself and 2 to 3 from another player. Doctor's Bags remove 1 to 2 from yourself and 3 to 5 from another player.
