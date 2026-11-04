# Vehicle Armour

![The towable Airstream hitched behind a Bobcat, a Gas Bottle and a Welder beside it](images/scenes/airstream.png)

![Metal Panel](images/items/20301_imcmptrkdrl_las_def.png) ![Welder](images/items/20202_welder.png) ![Gas Cylinder](images/items/19816_oxygencylinder1.png) ![Angle Grinder](images/items/20206_grinder.png)

Metal [defences](Defences) can be fixed onto the walk-in **Airstream** trailer (see [Vehicles](Vehicles)) and welded on with a Welder, so that its door cannot be forced open and the trailer cannot be blown up. No other vehicle takes armour today. For the trailer's door lock itself see [Repairing & Locks](Repairing-and-Locks).

## Which defences

Only metal defences can be welded on. Body panels lie flat on the shell where you aim them; the two doors only go on the trailer's own door, stretched to fit it, and swing with it.

| Defence | Goes on | Hitpoints when new | Gas to weld it on |
|:--|:--|--:|--:|
| Metal Panel | body | 5 | 2.2 kg |
| Corrugated Metal | body | 6 | 2.6 kg |
| Small Metal Panel | body | 5 | 2.2 kg |
| Metal Gate | body | 4 | 1.8 kg |
| Crate Door | the door | 5 | 2.2 kg |
| Ship Door | the door | 9 | 4.0 kg |

A Wood Ramp, Insulated Panel, Insulated Doorway or Metal Door is refused (*Only metal defences can be welded on*). A panel brings the hitpoints it has left, so a damaged one protects less than a new one.

## 1. Attach

Hold the defence next to the trailer and press `F` (the key list reads *Attach to trailer*). A ghost of the panel follows where your camera looks, lying flat on the trailer's skin at full size. Press `F` again to fix it there (*Attach here*; you must be within 4.5 m of the spot), or `N` to cancel. Walking away cancels too.

The ghost turns red and refuses to attach when it would overlap another defence, hang off the trailer, block the door, or be aimed at an inside surface; a Crate Door or Ship Door only fits the door, and nothing else does.

An attached panel is **not yet armour**: it protects nothing, a Crowbar pries it off again in 3 seconds (*Panel pried off*) and any blast knocks it onto the ground. It already weighs on the trailer, though: 180 kg per panel, and the vehicle towing the trailer loses 8 % of its engine acceleration per panel, never below 40 %.

## 2. Weld

![Generator](images/items/20204_generator.png) ![Gas Bottle](images/items/20203_gas_bottle.png)

Welding needs a **Welder** lying on the ground, gas hooked up to it (a Gas Cylinder or Gas Bottle lying within 2.5 m) and a **Generator** with at least 5 fuel within 8 m. The Welder, its torch and the gas hook-up are described on [Tools](Tools#welder-and-welding-gas), the Generator on [Machines](Machines#generator); a Welder in your hands only says *Lay the Welder down and take its torch*, and gas in your inventory does not count.

With empty hands, tap `F` at the Welder to take its **torch** (*Take torch*; holding `F` picks the Welder up instead). The torch hangs on a 5 m lead: walking further, taking anything in your hands, getting into a vehicle or pressing `N` puts it back (*The torch went back on the Welder*).

With the torch in hand press `F` at the trailer: the nearest attached panel within 1.6 m is welded on. The hold takes 8 seconds, shorter with the Repair [skill](Skills) (welding does not train it). Each weld burns 0.44 kg of gas per hit point the defence type can take (the table above) and 5 fuel from the Generator. Too little gas says *The gas hooked up to the Welder has too little left for this defence*; a missing generator *The Welder needs a fuelled Generator within 8 metres*.

<!-- shot:shot-welding -->

## Fortified

- The door alone has 1 hitpoint. Every welded panel adds its hitpoints to the door.
- While at least one panel is welded on, the trailer takes no damage and cannot blow up, and a Crowbar or Electronic Lockpick is refused at the door (*The door is armoured, a crowbar will not work*).
- An explosion is taken out of the armour: every attached but unwelded panel is knocked onto the ground; the welded ones soak up the damage, the door's panels first, and a panel worn down to 0 is wrecked. Only when no welded panel is left does the door's own hitpoint take what remains, and losing it breaks the door's lock (a key cut for it stops working and a keypad is removed). See [Explosives](Explosives).

## Taking armour off

- **Unwelded panel**: a Crowbar, 3 seconds. It lands on the ground beside the trailer.
- **Welded panel**: an **Angle Grinder** in hand, `F` at the trailer (*Grind panel off*): one pass of 20 seconds at the nearest welded panel. Each pass uses one charge of a **Tool Battery** (3 charges when new) and wears a **Grinding Disc** (6 passes when new; a worn-out disc is gone), both taken from your inventory or worn bag. Six passes cut the panel off (*Grinding: n of 6 passes cut* after each); it drops to the ground unwelded with the hitpoints it had. The passes stay on the panel, so the cut can be finished later or by someone else. Walking away during a pass cancels it and uses nothing.

![Tool Battery](images/items/20209_tool_battery.png) ![Grinding Disc](images/items/20207_grind_disc.png)

## Gas bottles on the trailer

The bottles on the Airstream's two A-frame mounts are stored, not used: to weld with one, take it off and lay it next to the Welder. The mounts are described on [Houses & Trailers](Houses-and-Trailers#the-towable-airstream).

See also [Defences](Defences), [Tools](Tools) and [Repairing & Locks](Repairing-and-Locks).
