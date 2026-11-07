# Machines

![The machines: Scrap Machine, Refining Machine, Water Purifier and Generator, scrap in front](images/scenes/scrapyard.png)

Three machines turn junk into useful material: the Scrap Machine, the Refining Machine and the Water Purifier. Each has a 12-slot container and a fuel tank that you fill from a [Petrol Can](Fuel). They are built on the ground, see [Constructing](Constructing), and every item they make is described on [Scrap](Scrap).

| Machine | Takes | Makes |
|:--|:--|:--|
| ![Scrap Machine](images/items/920_y_generator.png) **Scrap Machine** | Almost anything; items without a scrap value are destroyed | Scrap Metal, one piece per point of scrap value (at most 11 per cook) |
| ![Refining Machine](images/items/943_generator_low.png) **Refining Machine** | Scrap Metal only | One Refined Metal per Scrap Metal |
| ![Water Purifier](images/items/958_cj_chip_maker.png) **Water Purifier** | Bottles of sea water only; nothing fills a bottle with sea water today, so it stands idle | A bottle of clean water for every bottle, with the same amount |

## Where to find one

A Scrap Machine and a Refining Machine stand in the scrapyard in Whetstone, east of Mount Chiliad (in the Flint County zone, see [World & Zones](World-and-Zones)); if one is taken down or carried off it is put back when the server restarts. You can build your own with a Screwdriver from the parts listed on [Constructing](Constructing). The Refining Machine needs a large Metal Panel among its parts, which is what tells it apart from the Scrap Machine. A built machine can be taken down with a Crowbar and gives its parts back.

![The two fixed machines in the Whetstone scrapyard](images/places/scrapyard.png)

## Using a machine

- **Tap `F`** at the machine to open its container and load it. If it is running, you are told how long is left instead. The Refining Machine and Water Purifier refuse items they do not take.
- **Hold `F`** to open its menu, which shows the fuel amount and a **Start** button. The machine must hold at least one item and have 3.5 units of fuel for every item inside, otherwise you are told how much it needs per item.
- **Hold `F` with a Petrol Can in hand** to pour petrol into the tank instead. The tank holds 100 units; the bar fills for as long as you hold the key and stay within 4 m, or until the tank is full or the can is empty.

## Cooking

A cook takes 90 seconds per item inside plus up to 30 seconds more, and burns 3.5 units of fuel per item, taken from the tank when the cook finishes. A full 12-item load therefore needs 42 units and takes 18 to 18.5 minutes. While a machine runs it gives off smoke, and the cook carries on while you are away, even across a server restart. When it finishes, the container's contents are replaced by the results; take them out as from any other container ([Containers & Bags](Containers-and-Bags)).

- The Scrap Machine adds up the scrap value of everything inside (see [Scrap](Scrap)) and makes that many Scrap Metal, at most 11. An item with no scrap value adds nothing and is destroyed.
- The Refining Machine makes exactly one Refined Metal for each Scrap Metal: 12 Scrap Metal give 12 Refined Metal.
- The Water Purifier turns each bottle of sea water into a bottle of water with the same amount, one bottle for one bottle.

## Generator

The Generator is a fuel-only machine with no container and no cook. It is a portable unit: tap `F` at it with empty hands to pick it up, and put it down where you need it. Fuel it by holding `F` next to it with a Petrol Can (same 100-unit tank); holding `F` with empty hands tells you its fuel. It powers the Welder used to fit armour to a vehicle: the Welder draws from a Generator with fuel within 8 m, and each weld burns 5 units. See [Tools](Tools) and [Vehicle Armour](Vehicle-Armour).
