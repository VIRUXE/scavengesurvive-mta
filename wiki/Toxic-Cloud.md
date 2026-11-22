# Toxic Cloud

Every few hours a bank of poison gas forms off one edge of the map and drifts across it. You see it coming. What you do next is up to you: get out of its way, get above it, put a mask on, or shut yourself in somewhere airtight.

<!-- shot:toxic-cloud-horizon -->

## The cloud

- About one kilometre across, yellow-green, standing on the ground like a wall. It is visible from kilometres away, and hills and buildings hide it like anything else.
- It moves in a straight line at a jogging pace (8 m/s) and takes about 17 minutes to cross the map. It passes over any one spot in two minutes at most.
- A new one forms every three to four hours. There is no announcement.
- The map (`F11`) and the radar show where it is as a yellow-green patch.
- The gas is heavy. It is at full strength up to 110 m above sea level and gone by 150 m, so a mountain or a tall roof stands clear of it. The rim is thinner than the middle.

Inside it the fog closes in to a few dozen metres and everything takes the gas's colour.

<!-- shot:toxic-cloud-inside -->

## Poison

Breathing the gas raises your **Poison** level, shown in red or amber in the Health Status panel of the [inventory](Inventory). With no protection at all, the middle of the cloud adds about 1 % a second.

| Poison | What happens |
|:--|:--|
| from 15 % | You cough, more often the higher it is. Your view takes a green cast and blurs at the edges. |
| from 40 % | You lose health, slowly at first. |
| from 80 % | You lose health fast: at 100 % a healthy character dies in about a minute. |

In clean air it drops by 1 % every ten seconds, so a full dose takes about 17 minutes to clear. It is saved with your character: logging out does not clear it. A body killed by the gas says so when inspected ([Death](Death)).

## Masks

A mask worn on the face ([Masks](Masks)) keeps part of the gas out.

| Mask | Keeps out | Wears |
|:--|:--|:--|
| Bandana | 15 % | never |
| [Dust Mask](Dust-Mask) | 50 % | Disposable: about 5 minutes of thick gas, then it falls apart. |
| [Half Respirator](Half-Respirator) | 85 % | Its filter lasts about 15 minutes of thick gas. |
| [Gas Mask](Gas-Mask) | 97 % | Its filter lasts about 20 minutes of thick gas. |

- A mask only wears while you breathe gas through it, faster in thicker gas. What is left shows after its name: `Gas Mask (filter 63%)`.
- With a spent filter a respirator or gas mask keeps out only 10 %, and is harder to breathe through. Hold a [Filter](Filter) and use it while you wear the mask to fit a fresh one; the old one is thrown away.
- The mask's own seals wear too, far more slowly (about ten filters). A mask with less than half its seal leaks.
- A mask you find has been used: its filter and seal are somewhere between part worn and new.

### Breathing

The better a mask protects, the harder it is to breathe through, gas or no gas. It limits how long you can sprint before you have to catch your breath:

| Mask | Sprint | Then rest |
|:--|:--|:--|
| Bandana | about 2 minutes | 4 s |
| Dust Mask | 44 s | 5 s |
| Half Respirator | 19 s | 7 s |
| Gas Mask | 12 s | 8 s |
| either, filter spent | 9 to 12 s | 8 to 10 s |

You hear yourself breathe through it, louder and faster the more out of breath you are, with a wheeze once the filter is spent. Players next to you hear a respirator or a gas mask faintly.

## Shelter

Under a roof, what counts is how open the place is to the outside air. The gas inside follows the gas outside through the openings:

- **Airtight** (no way out for the air: a shut room, a sealed base): no gas gets in, however long the cloud sits over it.
- **Leaky** (an open door, a missing wall panel, a broken window): it fills, slowly through a small gap and quickly through a big one, and it empties as slowly once the cloud has passed. Leave while it airs.
- **Open** (a porch, a carport, an open-fronted hangar): hardly better than standing outside.
- **No roof** is the open air, whatever stands around you: the gas sinks into a yard.

You can see it happen: wisps of gas come in through each opening and drift across the floor.

<!-- shot:toxic-cloud-seeping -->

The game's own interiors (the ones you enter through a yellow marker) are sealed.

## Vehicles

A vehicle's cabin counts like a small room:

- **Sound, with every door shut**: it lets in very little. A drive through the cloud costs you a few percent.
- **A damaged door** no longer seals: each one lets in a good deal more.
- **A door open or missing, or the windscreen gone**: the same as standing outside.
- **Bikes, quads, boats and open-topped cars** give no shelter.

## On the HUD

Two bars join thirst, hunger, armour and health, on top of them:

- **Protection** (yellow), while you wear a mask or a cloud is on the map. It is as full as you are protected right now, mask and shelter together, so you can check a room or a car before the cloud arrives. It flashes red while you are breathing gas in.
- **Poison** (purple), while you have any. It fills as the poison builds and empties as it clears, flickers while you are taking more in, and flashes red from 40 %, where it starts to cost health.

## Poison Resistance

Surviving the gas builds a [skill](Skills). Every 10 % of poison you take raises **Poison Resistance** a step, the first steps the biggest, and it cuts the poison you take by up to a quarter at Master. It is lost with the character.

## Staff

`/toxic` tells a staff member (level 4) where the cloud is; `/toxic here` forms one over them, `/toxic cross` sends one across the map and `/toxic stop` ends it. Staff on duty take no poison.

See also [Masks](Masks), [Health](Health), [Skills](Skills) and [World & Zones](World-and-Zones).
