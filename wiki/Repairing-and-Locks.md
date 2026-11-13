# Repairing & Locks

Tools you hold are used at a vehicle by standing next to it and pressing the interact key (`F`). Where you stand matters: the front is the bonnet (repairs), the driver's side (left) is the door lock, and the rear is the trunk. See [Vehicles](Vehicles) for the rest and [Tools](Tools) for the tools themselves.

## Repairing

![Spanner](images/items/19627_wrench1.png) ![Screwdriver](images/items/18644_screwdriver1.png) ![Hammer](images/items/18635_gtasahammer1.png) ![Ratchet](images/items/20236_ratchet.png)

Stand at the front of the vehicle with the right tool in your hands and press `F`. The bonnet has to be open already (empty hands, a tap of `F`) and after 3 seconds (shorter with the Repair [skill](Skills)) the vehicle gains 150 health, up to a field-repair limit of 990 out of 1000. The tool you need depends on how damaged it is, and it changes as it heals, so you repair in stages:

| Vehicle health | Tool |
|:--|:--|
| under 450 (very broken) | Spanner |
| 450 to 649 | Screwdriver |
| 650 to 799 | Hammer |
| 800 to 989 | Ratchet |
| 990 and over | fully repaired |

The wrong tool says *You need another tool*. When you get into the driver's seat a tip tells you how broken the vehicle is. Under 450 health the engine can cut out at speed, and under 300 it will not run at all.

- **Tyres**: with the engine off, hold a Tyre Wrench beside a wheel (not at the front or rear) and press `F`. The camera moves to the hub: click a lug nut, or pick one with `A` and `D`, and hold the mouse button to undo it; do all of them and the wheel comes off as a Wheel item. To fit one, put a Wheel on the ground within 3 m of the bare hub, then hold the Tyre Wrench and press `F` again and thread the nuts back on. A car with no wheels left freezes after two seconds.
- **Headlights**: hold a Headlight at the front. A broken light is replaced and the item is used up.
- **Battery and starter motor**: with empty hands a tap of `F` at the front opens the bonnet, or lifts a loose battery or a loose starter motor into your hands. A Battery or Starter Motor in hand goes into its empty slot loose with a tap. Hold `F` with a Ratchet at the open bonnet for a menu: repair the engine, or tighten or unbolt those parts. See [Car Batteries & Starters](Car-Batteries-and-Starters).

## Locks

A vehicle is in one of three states:

| State | Meaning |
|:--|:--|
| Unlocked | Anyone can get in and open the trunk |
| Locked | A plain lock, set when the vehicle spawned damaged or when someone locks it from inside. *Door locked, use a Crowbar* |
| Custom lock | Locked with a Locksmith Kit or a Lock and Chain. *Door locked with custom lock* |

A locked vehicle cannot be entered and its trunk will not open.

### Breaking in

Stand at the driver's door (or the rear for the trunk) and press `F` with the tool in your hands. A 3 second bar runs, then the lock is broken: the vehicle is unlocked, any key made for it stops working, and a keypad on it is removed.

| Tool | Breaks |
|:--|:--|
| ![Crowbar](images/items/18634_gtasacrowbar1.png) Crowbar | A plain lock only. A custom lock *cannot be broken* with it |
| ![Electronic Lockpick](images/items/1952_turn_arm_r.png) Electronic Lockpick | Any lock |

The Electronic Lockpick is made at a [Workbench](Workbench).

### Locksmithing

![Locksmith Kit](images/items/1210_briefcase.png) ![Key](images/items/11746_doorkey1.png)

- **Locksmith Kit**: hold it at the driver's door of an unlocked or plainly locked vehicle that has doors and press `F`. After 3 seconds the kit is used up, the vehicle gets a custom lock and you are handed a **Key** cut to it. A vehicle that already has a custom lock is refused (*already locked*), as are vehicles without doors.
- **Key**: hold the matching key at the driver's door and press `F` to lock or unlock. A key for another vehicle says it doesn't fit, a blank key says it is not cut. Extra copies are made by [Constructing](Constructing) a key copy.
- **Lock and Chain**: the lock for vehicles with no doors (bikes, quads, boats, open vehicles), which a kit refuses. First combine it with a Locksmith Kit to cut it ([Combining](Combining)); an uncut one says *has no key*. It then shows as *Lock and Chain (Cut)*. Use it at the vehicle like a kit: it is used up and you get a Key. It does not work on vehicles with doors.
- **Locksmith Kit** itself is made at a [Workbench](Workbench) from a Key and a Motor.

### From inside

Any occupant can lock or unlock a vehicle without a key with `/lock` or the vehicle Sub-mission control (see [Controls](Controls)). The vehicle gets the custom lock if it already has a key, the plain lock if not.

### Caravan doors

The walk-in Airstream trailer has its lock at its door. Keys, kits, chains and break-in tools work within reach of the door, inside or outside. A [Keypad](Keypads) or Advanced Keypad can be fitted to the door (a 6 second job at the door, the item is used up) and then takes a four digit code.

## Armour

While a metal defence is welded onto the Airstream, the Crowbar and the Electronic Lockpick are refused at its door (*The door is armoured, a crowbar will not work*); see [Vehicle Armour](Vehicle-Armour).
