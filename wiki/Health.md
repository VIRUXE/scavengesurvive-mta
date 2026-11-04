# Health

Your character has two meters: health and hunger. Both are saved with the character and shown on the HUD and in the inventory's Health Status panel (open it with `H`).

Health is 0 to 100. At 0 you die. A first-ever character starts with 90 health and 80 hunger; a character created after a death starts with 100 health and 40 hunger.

## Regeneration

Health regenerates once a second, but only while you are **not bleeding**. The amount depends on hunger:

| Hunger | Health per second (not bleeding) |
|--:|--:|
| 100 | about 0.19 |
| 50 | about 0.10 |
| 20 | about 0.04 |

A [wound infection](Infection) halves the regeneration. [Morphine and Adrenaline](Drugs) add health on top of it.

## Hunger

Hunger falls every second, faster the faster you move:

| Activity | Hunger lost per second |
|:--|--:|
| Standing still | 0.004 |
| Walking or jogging (up to about 13 km/h) | 0.0048 |
| Running (up to about 19 km/h) | 0.0072 |
| Sprinting (faster) | 0.0088 |
| In a vehicle | 0.0008 |

A [food infection](Infection) adds 0.004 per second on top. See [Food & Drink](Food-and-Drink) for how to refill it.

Below 20 hunger you start to starve and lose `(20 - hunger) / 30` health per second, up to about 0.67 per second at 0 hunger. Starving is a cause of death.

## Ways to lose health

- [Bleeding & Wounds](Bleeding-and-Wounds): every wound adds to your bleed rate, which drains health each second.
- Starvation, as above.
- The drug Air (from an empty injector) costs 1 health on half the seconds; see [Drugs](Drugs).
- Low health darkens the screen. [Painkillers and Adrenaline](Drugs) hide the darkness.

## Unconsciousness

A wound can knock you unconscious. You cannot move, shoot or use items while out; the knockout is 1.5 to 120 seconds, and a second knockout while already out adds to the time (never beyond 120 seconds). The chance and length grow with the number of wounds you carry, with your bleed rate and with how low your health is, and depend on where you were hit: a headshot is by far the most likely to knock you out, the legs the least. A worn hat cuts the knockout chance of a headshot by 60 %.

The Health Status panel shows your current chance as "% Unconscious".

While you are unconscious other players can:

- take the item from your hands with the interact key (see [Surrender & Disarm](Surrender-and-Disarm));
- wake you at once by injecting you with an Adrenaline [injector](Drugs).

## Healing

Stop the bleed first, then heal. Bandages, Medkits and Doctor's Bags are covered on [Medical](Medical); the short version:

- **Bandage** and **Antiseptic Bandage** reduce the bleed rate.
- **Medkit** reduces the bleed rate and removes wounds.
- **Doctor's Bag** stops the bleed, removes wounds and gives a drug.
- Eating keeps hunger up, which keeps regeneration fast.

## Death

At 0 health your character dies for good: everything it carried drops around a body and the next character starts from nothing, skills included. See [Death](Death). Quitting during a fight counts as dying: see [Combat Log](Combat-Log).
