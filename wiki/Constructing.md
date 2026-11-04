# Constructing

Constructing builds larger items from parts lying on the ground: a campfire, furniture, a workbench, the machines and a few defences. You need the right tool in your hands. The other crafting kinds are [Combining](Combining) (two items from the inventory) and the [Workbench](Workbench).

## How to construct

1. Drop all the ingredients on the ground close together. Everything within about 2.5 m of you counts.
2. Equip the tool the recipe asks for.
3. Press the interact key (`F`) next to the pile, or type `/craft`. A progress bar runs for the build time and you work with your hands while it fills.
4. The ingredients are used up and the new item stands where the parts lay. Most things can then be nudged into place with the pad described under *Nudging into place* on [Defences](Defences); a Campfire, a Plot Pole and a key copy get no pad.

If the pile does not match a recipe you are told *Cannot craft these items*. If it is a [Workbench](Workbench) recipe you are told you need a workbench. When the pile could make more than one thing, the recipe that uses the most items wins, so four Wood Logs and a Refined Metal make a Table, not a Desk. Building trains the matching [skill](Skills), which shortens later builds.

Ingredients marked *kept* stay on the ground. The build fails if one of the used parts is picked up while you work.

## Recipes

| Result | Tool | Ingredients | Build time | Crowbar takedown |
|:--|:--|:--|--:|--:|
| Campfire | Lighter | 3x Wood Log | 5 s | cannot be taken down |
| Workbench | Hammer | 2x Refined Metal, 4x Wood Log | 30 s | 25 s |
| Locker | Sledgehammer | 2x Metal Panel (crafted), Refined Metal | 30 s | 25 s |
| Large Frame | Sledgehammer | 4x Refined Metal | 30 s | 22 s |
| Desk | Screwdriver | Refined Metal, 3x Wood Log | 26.5 s | 25 s |
| Table | Screwdriver | Refined Metal, 4x Wood Log | 28.5 s | 25 s |
| Barstool | Screwdriver | Clothes, Refined Metal, 2x Wood Log | 22.5 s | 22 s |
| Small Table | Screwdriver | 4x Wood Log | 22.5 s | 22 s |
| Scrap Machine | Screwdriver | Gas Cylinder, Fluctuator Unit, Motor, Power Supply | 30 s | 25 s |
| Refining Machine | Screwdriver | Gas Cylinder, Fluctuator Unit, Metal Panel, Motor, Power Supply | 30 s | 25 s |
| Water Purifier | Screwdriver | Bucket, Gas Cylinder, Motor, Power Supply | 30 s | 25 s |
| Plot Pole | Screwdriver | Gas Cylinder, Fluctuator Unit, Power Supply, Receiver | 20 s | 30 s |
| Key (copy) | Screwdriver | Key, Motor, Key (kept) | 18.5 s | no |

Notes:

- Two different items are called Metal Panel. The Locker takes the one made at a [Workbench](Workbench) from 4 Refined Metal; the Refining Machine takes the large panel found as loot (also used as a [defence](Defences)).
- Refined Metal is made from scrap, see [Scrap](Scrap) and [Machines](Machines); the machines' Gas Cylinder, Motor, Power Supply and Fluctuator Unit are [Workbench](Workbench) recipes.
- The Large Frame is laid flat as a [defence](Defences) when built.
- **Key copy**: put a cut key, a blank key and a Motor on the ground. The blank key and the Motor are used up, the cut key stays, and the new key takes its cut. See [Repairing & Locks](Repairing-and-Locks).
- A Campfire is described on [Campfire & BBQ](Campfire-and-BBQ), the machines on [Machines](Machines), the furniture on [Furniture](Furniture) and the Workbench on [Workbench](Workbench).
- A Plot Pole marks a 20 m claimed territory around itself, see [Defences](Defences).

## Taking things down

Hold a Crowbar and press `F` next to a built item (or use `/craft` with the Crowbar in hand). After the takedown time shown above the item is dismantled and every part that was used up building it drops nearby; parts marked *kept* never left their owner. A Campfire and a key copy have no takedown. Takedown time is also shortened by skill.
