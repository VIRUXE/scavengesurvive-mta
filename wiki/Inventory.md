# Inventory

Open the inventory with `H` (rebindable in MTA's key settings). It is the screen where you manage everything you carry.

## Layout

- **Centre:** a list of the items in your inventory, titled `Inventory (used/size)`. Each row reads `[size]Name`; free slots read `<Empty>`.
- **Left:** the Health Status panel: a wound count for each of seven body parts (Head, Torso, Arm R, Arm L, Groin, Leg R, Leg L), red where you were last hit; `Bleed` (red unless it reads 0.00); `Hunger` in percent (yellow under 50, red under 20); `Food Infect` and `Wound Infect` when you have an [infection](Infection); each active [drug](Drugs); and, in the footer, your chance of being knocked unconscious by the next wound.
- **Right:** six gear tiles, `HEAD`, `FACE`, `HAND`, `HOLSTER`, `TORSO` and `BACK`, each with a live, turning 3D model of the item in it and its name below (`<EMPTY>` otherwise). The `HAND` tile shows what you hold with its size, such as `(03) MEAT (UNCOOKED)`; `TORSO` shows the armour's points, `ARMOUR (73)`. Click a filled tile to take the item off, click an empty tile while holding a matching item to put it on, click `HAND` to put the held item away, and click `BACK` to switch to the contents of the worn bag. See [Clothes & Hats](Clothes-and-Hats), [Armour](Armour) and [Holster](Holster).
- Extra rows at the bottom of the list: your worn bag (`Small Bag >`, `Backpack >` ...), `Skills` (see [Skills](Skills)) and `Radio` (see [Radio](Radio)). Opening a vehicle trunk or a container shows its contents next to yours, with `My Inventory >` to switch back.

<!-- shot:shot-inventory -->

## Capacity

Your inventory has **6 slots**. Every item takes as many slots as its size (a size 3 item takes 3 slots); see [Item Sizes](Item-Sizes) and [Item Catalogue](Item-Catalogue). Items too big to put away, such as large crates, can only be carried in your hands, a vehicle or a box.

A worn bag adds its own slots. When your inventory is full, items go into the bag; see [Containers & Bags](Containers-and-Bags) for the sizes.

## Hands

You hold one item at a time. Press `F` to pick up the nearest item within 2 m into your hands; an item behind a wall or a closed door does not count. Then:

| Key | Action |
|:--|:--|
| `F` (hold 500 ms) | Picks up a bag or box lying there with everything in it (a tap opens it instead), or a Sign, a body or a Plant Pot (a tap reads or inspects it instead) |
| `Y` | Put away: into the inventory, then the bag if the inventory is full. A holsterable weapon is holstered, a bag is put on, a parachute goes on your back |
| `N` | Drop the item. With another player within 1.5 m the item is handed to them instead |
| `N` (hold 300 ms) | Unload a firearm and drop its ammunition tin |
| `N` with empty hands | Take off a worn parachute, otherwise your worn bag, into your hands |
| `Y` with empty hands | Draw your holstered weapon |

If the item fits in neither the inventory nor the bag you keep it in your hands and are told that extra slots are required.

## Big items

Some items are carried in both hands, with a lifting animation and a carry pose: wheels, the boxes, crates, cartons and bin bags found around the map, metal panels and doors, the BBQ, the Welder, the Generator, the Gas Cylinder, the Plant Pot, the Dice, a Tent Pack, a Campfire, a body and a few others. They never go into your inventory or a bag (*Too big to put away, it goes in a vehicle or a box*), and you cannot get into a vehicle while holding one. Drop it, hand it over, or put it in a trunk or box with `Y` while that container's list is open.

## Handing items over

With an item in hand and another player within 1.5 m, `N` hands it to them instead of dropping it. Their hands must be empty, and neither of you may be cuffed, knocked out, holding your hands up or on staff duty. You see *You handed it over* and they *You were handed an item*. A bag or box goes over with its contents.

## Inventory actions

Choose a row to get a list of actions:

- **Equip** takes the item into your hands (they must be empty).
- **Use** uses it where it is, for example to eat food or read a note.
- **Wear** puts on a hat, mask, armour, holsterable weapon or clothes.
- **Combine** is shown when you hold something: see [Combining](Combining).
- **Move to ...** sends the item to the open bag, trunk or container, or back to the inventory.
- With something in your hands, an `<Empty>` row offers **Store in ...** for the list it is in.

## Item names

Some names carry their state: food reads `(Cooked)` or `(Uncooked)`; a drink `Bottle (Water 0.4/0.50)` or `(Empty)`; a firearm its rounds and ammunition, `M9 (10/7, 9mm, Hollow Point)`; a Note its first words or `(Blank)`; a Stun Gun `(Charged)` or `(Uncharged)`; Seeds their count and kind; a Gas Bottle its kilograms; a Car Battery its charge, `Car Battery (82%)`; a Key the vehicle kind it was cut for, `Car Key`, `Boat Key`, `Trailer Key`; a Lock and Chain `(Cut)` or `(Uncut)`; a Code its digit; Clothes the set they hold; Pills and Injectors their drug.

## Items on the ground

![A Hotdog on the ground with its label](images/screens/world-item-hotdog.jpg)

Items lying in the world are shown within 150 m of you. Within 4 m each shows its name as a yellow label (bigger within 3 m), hidden while a wall stands between you and it; a built defence shows its hit points from 10 m, and a Sign's text can be read from 25 m. Picking an item up shows a tip about it for 20 seconds; `/tooltips` turns the tips off and on.

## Dropping everything

`/dropall` drops everything you carry, wear and hold in a ring around you and raises your hands, without killing you; a death drops it the same way, plus a Clothes item and a body. See [Death](Death) and [Surrender & Disarm](Surrender-and-Disarm).

See also [Item Sizes](Item-Sizes), [Containers & Bags](Containers-and-Bags) and [Holster](Holster).
