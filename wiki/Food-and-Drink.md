# Food & Drink

Eating raises your hunger value and drinking your thirst value (both 0 to 100, shown as the green and blue bars on the HUD and as `Hunger` and `Thirst` in the inventory). Below 20 either one costs health, and health regenerates on the lower of the two, see [Health](Health).

You keep what you have no use for: food is refused with *You are not hungry* at 99 hunger or more, a drink with *You are not thirsty* at 99 thirst, and a drink being sipped stops by itself once you have had enough. Fruit still goes down when you are thirsty, milk and juice when you are hungry, and what is no drink at all (petrol, turpentine) can always be drunk.

## Eating

Hold food in your hands and press the interact key (`F`), or choose `Use` on it in the inventory. The whole item is eaten at once and used up, and you gain its bites times its food per bite in one go. On foot with your hands free your character takes a bite (about two seconds); in a vehicle it is just eaten.

<!-- table:food -->
| Food | Bites | Food per bite | Can be cooked | Infects when raw |
|:--|--:|--:|:--|:--|
| Meat | 8 | 18.12 | yes | yes |
| Pizza | 6 | 18.5 | yes | no |
| Pizza | 6 | 18.3 | yes | no |
| Meat | 6 | 16.7 | yes | yes |
| Pizza Box | 6 | 16.5 | yes | no |
| Hotdog | 4 | 18 | yes | yes |
| Burger | 4 | 17.5 | yes | no |
| Burger | 4 | 16.25 | yes | yes |
| Burger | 4 | 16.25 | yes | no |
| Loaf of Bread | 10 | 6.32 | yes | no |
| Fishy Fingers | 10 | 6.3 | yes | no |
| Taco | 4 | 13.75 | yes | no |
| Ice Cream | 12 | 4.1 | no | no |
| Ice Cream Bars | 12 | 3.9 | no | no |
| Ham | 6 | 6.12 | yes | yes |
| Wrapped Meat | 4 | 6.7 | yes | yes |
| Steak | 4 | 6.49 | yes | yes |
| Beef Jerky | 4 | 6 | no | no |
| Cheesy Puffs | 6 | 4 | no | no |
| Chocolate Chip Cookies | 6 | 4 | no | no |
| Phat Chips | 6 | 4 | no | no |
| Twisted Pretzels | 6 | 3.5 | no | no |
| EgoChaser Bar | 3 | 6 | no | no |
| Fish | 4 | 4.5 | yes | yes |
| Green Apple | 4 | 4.5 | no | no |
| Orange | 4 | 4.5 | no | no |
| Red Apple | 4 | 4.5 | no | no |
| Banana | 3 | 5.5 | no | no |
| Lemon | 4 | 4 | no | no |
| Meteorite Bar | 3 | 5 | no | no |
| Salted Peanuts | 3 | 5 | no | no |
| Zebra Bar | 3 | 5 | no | no |
| Cereal | 6 | 2.2 | no | no |
| Cereal | 6 | 2.2 | no | no |
| Fruit Candy | 4 | 3 | no | no |
| Bread | 5 | 2.34 | yes | no |
| Tomato | 3 | 3 | yes | no |
| Cake Slice | 1 | 2.5 | yes | no |
<!-- /table:food -->

![Burger](images/items/2703_cj_burg_1.png) ![Hotdog](images/items/19346_hotdog01.png) ![Meat](images/items/2804_cj_meat_1.png)

### Wet and salty food

Some food also moves thirst:

| Food | Thirst |
|:--|--:|
| Ice Cream | +12 |
| Ice Cream Bars, Orange | +10 |
| Tomato | +8 |
| Red Apple, Green Apple | +6 |
| Lemon | +5 |
| Banana | +3 |
| Phat Chips, Cheesy Puffs | -4 |
| Twisted Pretzels, Salted Peanuts | -5 |
| Beef Jerky | -6 |

### Raw and cooked food

Food that can be cooked is labelled `(Uncooked)` or `(Cooked)` in its name.

- Eating uncooked food gives only **70 %** of its food value.
- Foods marked "Infects when raw" above also give you a [food infection](Infection).
- Cooked food, and food that cannot be cooked, is always eaten at full value and never infects.

With uncooked food in your hands next to a Campfire or Barbecue, `F` puts it on the fire instead of eating it. A Campfire cooks in 60 seconds and a Barbecue in 30. See [Campfire & BBQ](Campfire-and-BBQ).

## Drinking

![Bottle](images/items/1543_cj_beer_b_2.png) ![Can](images/items/2601_cj_juice_can.png) ![Milk Carton](images/items/19569_milkcarton1.png) ![Orange Juice](images/items/19563_juicebox1.png)

Hold a container with something drinkable in it (a Bottle, a Can, a Milk Carton, a juice box, a bottle of wine and so on) and hold `F`. Each sip takes 1 second and 0.2 litres (a last sip of less gives its share); keep holding to keep drinking. Letting go, moving more than a step or changing what you hold stops it, and an empty container says *It is empty*. You cannot drink in a vehicle or while knocked out, and only from your hands: `Use` on a container in the inventory list does nothing. The container's name shows what is inside and how much: `Bottle (Water 0.4/0.50)` or `Bottle (Empty)`.

A **Petrol Can** is never drunk from: `F` with one in hand fills it at a pump or pours it into a vehicle, machine, barbecue or Empty Molotov ([Fuel](Fuel)). The Oilcan and the Detergent bottle can be drunk, at the cost shown below.

### Containers

| Container | Holds | Found with |
|:--|--:|:--|
| Bottle | 0.5 L | Water (most often), Orange Juice, Carbonated Water, Lemon Juice, Lemonade or Orangeade |
| Can | 0.33 L | the same as a Bottle |
| Milk Bottle | 0.57 L | Milk |
| Milk Carton | 1 L | Milk |
| Apple Juice | 1 L | Apple Juice |
| Orange Juice | 1 L | Orange Juice |
| Wine | 0.75 L | Red Wine or White Wine |
| Whisky | 1.5 L | Whiskey |
| Champagne | 1.5 L | Champagne |
| Detergent | 0.33 L | Turpentine |
| Oilcan | 16 L | Oil |
| Petrol Can | 20 L | Petrol |
| Ketchup, Mustard | 0.5 L | nothing: always empty |

Thirst and hunger gained per 0.2 L sip:

| Liquid | Thirst per sip | Hunger per sip |
|:--|--:|--:|
| Water | 12 | 0 |
| Carbonated Water | 11 | 0 |
| Orangeade | 10 | 2.5 |
| Orange Juice, Apple Juice, Lemonade | 10 | 2 |
| Milk | 8 | 4 |
| Lemon Juice | 8 | 1 |
| Red or White Wine | 4 | 0.4 |
| Champagne | 4 | 0.2 |
| Protein Powder | 0 | 4.5 |
| Sugar | 0 | 0.8 |
| Baking Soda | 0 | 0.1 |

So a 0.5 L Bottle of water gives 30 thirst, a Can 20, and a 1 L carton of juice 50 thirst and 10 hunger.

Not everything that fills a container is a drink. Spirits and sea water **cost** thirst, the rest costs hunger:

| Liquid | Per sip |
|:--|--:|
| Whiskey | -3 thirst |
| Sea Water | -40 thirst |
| Petrol, Diesel, Oil | -8 hunger |
| Ethanol | -44.1 hunger |
| Turpentine, Hydrochloric Acid, Thermite Mix | -101 hunger |

Neither value can go below 0, but a large penalty empties it at once and may start you starving.

### Other uses of a bottle

- Water from a Bottle or Can waters a Plant Pot: `F` at the pot pours 0.1 L into it, and with a pot within reach that comes before drinking. See [Gardening](Gardening).
- Petrol poured from a Petrol Can into an Empty Molotov makes a Molotov; see [Explosives](Explosives).
- The Water Purifier turns bottles of sea water into bottles of water; see [Machines](Machines).
