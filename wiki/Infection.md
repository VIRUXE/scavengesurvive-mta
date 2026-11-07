# Infection

There are two infections, tracked separately. Both are listed in red in the inventory's Health Status panel as `Food Infect` and `Wound Infect`, they are saved when you log out, and a new character starts without them.

## Food infection

Caused by eating raw food that can carry disease, mainly uncooked meat and fish. The [Food & Drink](Food-and-Drink) table lists which foods infect when raw. Cooking the food on a Campfire or Barbecue first makes it safe (see [Campfire & BBQ](Campfire-and-BBQ)).

Effect: your hunger drains faster (an extra 0.004 per second).

## Wound infection

Caused by a Dirty Bandage: there is a one in three chance each time one is used that the patient, the person being bandaged, becomes infected. The healer is not affected.

Effect: your health regenerates at half speed (see [Health](Health)).

## Camera shake

While either infection is active your screen wobbles from time to time, more often and for longer when your health is low. Morphine, Adrenaline and Air hold the wobble off while they last (see [Drugs](Drugs)).

## Cures

| Cure | Food infection | Wound infection |
|:--|:--|:--|
| Pills (Antibiotics) | cured | cured on half of the uses |
| Antiseptic Bandage | no | cured |
| Doctor's Bag | no | cured |

![Pills](images/items/2709_pain_killer.png) ![Antiseptic Bandage](images/items/11748_bandagepack1.png)

An Antiseptic Bandage is used up when it cures or stops a bleed, and it is the safe alternative to a Dirty Bandage. Pills only work on yourself; the type of pill is shown in the item name, for example `Pills (Antibiotics)`. See [Medical](Medical) for every treatment item.

Dying removes both infections.
