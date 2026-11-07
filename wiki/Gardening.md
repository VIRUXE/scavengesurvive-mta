# Gardening

![Seeds](images/items/2663_cj_bs_bag.png) ![Plant Pot](images/items/2203_plant_pot_1.png) ![Tomato](images/items/19577_tomato1.png) ![Red Apple](images/items/19575_apple1.png) ![Banana](images/items/19578_banana1.png)

Gardening grows fruit and vegetables from a bag of **Seeds** in a **Plant Pot**, with water from a bottle and a Combat Knife to harvest. Seeds and pots are found as loot and in [supply drops](Supply-Drops).

## Seeds

A bag of Seeds (size 2) holds **0 to 4 seeds of one kind**, shown in its name: `Seeds (3, Tomato)` or `Seeds (Empty)`. The kinds:

| Seeds | Crop | Growth steps | Water needed |
|:--|:--|--:|--:|
| Tomato | Tomato | 4 | 0.4 L |
| Apple | Red Apple or Green Apple | 5 | 0.5 L |
| Lemon | Lemon | 5 | 0.5 L |
| Orange | Orange | 5 | 0.5 L |
| Banana | Banana | 6 | 0.6 L |
| Unknown | nothing: a plant or bush grows, but there is no crop | 0 | - |

More than half of the seed kinds are *Unknown*: they grow a plant for decoration and nothing more.

## Planting

1. Drop the Plant Pot (size 4, carried in both hands) where you want it. Only a pot lying on the ground grows anything.
2. Hold the Seeds and press `F` at the pot: *Added seeds to plant pot*. One seed leaves the bag. An empty bag does nothing. Seeds put into a pot that already has a plant start it over with the new seed.
3. Water it: hold a container with **Water** in it (a Bottle or a Can) and press `F` at the pot: *Added 1 water to plant pot*. Each press pours 0.1 L. An empty container or one holding anything but water is refused. With a water bottle in hand near a pot, `F` waters the pot rather than drinking from the bottle.

A tap of `F` at the pot with empty hands shows its state: *Active*, *Seed type*, *Water* and *Growth*, such as `Growth: 2/4`.

## Growing

Every **10 minutes** each pot in the world takes one step:

- with water in it, the plant drinks 1 water and grows 1 step;
- with no water, it withers 1 step, and at 0 the plant dies and the pot is empty again.

So a Tomato needs 4 waters and 40 minutes, a Banana 6 waters and an hour. Keep at least one water in the pot at every step, including the first: a freshly planted pot that is left dry is empty 10 minutes later. Extra water does no harm and is used up as the plant drinks.

A sprout appears after the first step and rises as the plant grows; at the last step the full plant stands on the pot. The pot keeps growing while you are away and across server restarts. *Unknown* seeds show their plant at once; it too dies if the pot is left dry.

## Harvesting

Hold a **Combat Knife** and press `F` at the pot:

- a fully grown plant gives its crop, which appears on the pot, and the pot is empty: *Plant harvested*;
- a young plant: *The plant has not fully grown yet.*;
- an empty pot: *Pot doesn't contain an active plant.*

A Knife on an *Unknown* plant clears it with no crop.

The crops are ordinary food ([Food & Drink](Food-and-Drink)): a Tomato gives 3 bites of 3 food and can be cooked; apples and oranges 4 bites of 4.5, a Lemon 4 bites of 4, a Banana 3 bites of 5.5. Tomato seeds give the most for the least water.

## Moving a pot

Hold `F` for half a second at the pot with empty hands to pick it up. It is carried in both hands and the plant goes with it, growing again once the pot is back on the ground. Like other two-handed items it will not go into your inventory or a bag, but a vehicle trunk or a box takes it; see [Inventory](Inventory).
