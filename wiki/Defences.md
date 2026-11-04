# Defences

![A defence wall: a Metal Door between Metal Panels, with its Keypad and a Crowbar on the ground](images/scenes/doorway.png)

Defences are the walls, doors and gates players build bases from. There are 11 kinds. Each starts as an ordinary item you drop; a tool turns it into a fixed, solid defence that nobody can pick up.

![Metal Door](images/items/18553_count_ammundoor.png) ![Metal Panel](images/items/20301_imcmptrkdrl_las_def.png) ![Metal Gate](images/items/19303_pd_jail_door02.png) ![Crate Door](images/items/20302_container_door_def.png) ![Corrugated Metal](images/items/2904_warehouse_door1.png) ![Ship Door](images/items/20303_freight_sfw_door_def.png) ![Insulated Doorway](images/items/19398_wall046.png) ![Insulated Panel](images/items/19371_wall019.png) ![Small Metal Panel](images/items/19843_metalpanel1.png) ![Wood Ramp](images/items/5153_stuntramp7_las2.png) ![Large Frame](images/items/19157_metallightbars1.png)

<!-- table:defences -->
| Defence | Hit points | Size | Can be moved after placing |
|:--|--:|--:|:--|
| Large Frame | 12 | 20 | no |
| Ship Door | 9 | 10 | yes |
| Insulated Doorway | 7 | 10 | no |
| Insulated Panel | 7 | 8 | no |
| Wood Ramp | 7 | 11 | no |
| Corrugated Metal | 6 | 10 | yes |
| Crate Door | 5 | 9 | yes |
| Metal Panel | 5 | 10 | yes |
| Small Metal Panel | 5 | 11 | yes |
| Metal Gate | 4 | 10 | yes |
| Metal Door | 2 | 9 | no |
<!-- /table:defences -->

"Hit points" is how much explosive damage a defence takes before it breaks (see [Explosives](Explosives)). A medium charge deals 2, a small one 1. The Large Frame is built from 4 Refined Metal with a Sledgehammer ([Constructing](Constructing)) and comes out lying flat.

## Building

1. Drop the defence item where you want it.
2. Stand within 3 m of it, hold a **Screwdriver** to stand it upright (a wall or door) or a **Hammer** to lay it flat (a floor or ramp), and hold `F` on it for about 10 seconds. The [Construction skill](Skills) shortens this. Walking off or swapping tools before the time is up cancels the build.
3. The defence is built (*Defence built*), and the nudge pad opens with a yellow arrow on the defence showing its **front**; see *Nudging into place* below.

Hammer and Screwdriver lay the same item in different poses; once built, a defence stays in that pose until it is moved by a motor.

## Nudging into place

Right after a defence is built (and after most items are constructed on the ground, see [Constructing](Constructing)) a pad of eight buttons appears at the right of the screen, and you can shift the item a little:

- `LALT` (the walk key) shows the mouse; the long button then reads *Move* and hides it again so you can walk.
- `^`, `v`, `<` and `>` move the item 5 cm per click (hold the button to keep stepping); `L` and `R` turn it 2 degrees.
- The item never goes further than 1.5 m from where it was built (*Too far from original build position*), and it does not move while anyone, you included, stands within 2.2 m of it (*Cannot move item with players nearby*; the other player is told to stand back). Step back first.
- *Done* or `Enter` finishes (*Tweaking finished*). Dying, getting into a vehicle, clicking the pad from more than 10 m away, dropping or putting away an item, or opening the inventory ends it as well, and the item stays where it is.

On a defence the yellow arrow shows its front: the side from which a Crowbar cannot take it down and a Motor or Keypad cannot be fitted. A Campfire and a Plot Pole open no pad.

## Taking one down

Hold a **Crowbar** and hold `F` on the defence for 10 seconds. You must stand at its back, the inside: from the front you are told that you can only remove a defence from the inside. The defence goes back to a normal item (and any motor or keypad on it is gone).

## Doors and gates

Some defences can be fitted with a **Motor**. Standing at the back, hold the Motor and hold `F` for about 6 seconds: the Motor is used up and the defence now swings between its two poses (standing and lying) whenever someone presses `F` on it. It moves about 1.5 seconds later, and waits while anyone stands within 4 m. Without a Motor, pressing `F` on a built defence does nothing.

Defences that take a Motor: Metal Gate, Metal Panel, Small Metal Panel, Crate Door, Corrugated Metal and Ship Door. The Metal Door, Insulated Doorway, Insulated Panel, Wood Ramp and Large Frame cannot.

A Motor-fitted defence can then take a [Keypad](Keypads), which locks it behind a 4-digit code.

The **Large Frame** is different: pressing `F` on it puts a covering panel over the frame or takes it off.

## Plot Pole

![Plot Pole](images/items/3221_drv_in_spkrs.png)

A Plot Pole marks a claimed territory. Build it on the ground with a Screwdriver from a Gas Cylinder, a Fluctuator Unit, a Power Supply and a Receiver (20 seconds, see [Constructing](Constructing)). While it stands, everyone who comes within 20 m of it is told *Entering claimed territory*, and *Leaving claimed territory* on the way out. That is all the pole does today: it does not stop anyone from building, taking down or picking up anything inside the circle, so the defences still have to do the protecting. The claim lasts as long as the pole stands in the world; it ends when the pole is picked up (`F`, like any item) or dismantled with a Crowbar (30 seconds, the parts drop). The pole gets no nudge pad.

## Notes

- Explosives damage defences: each blast removes hit points from every defence in range, see [Explosives](Explosives).
- A motor is made at the [Workbench](Workbench) from a Power Supply and a Timer Device.
- A built defence keeps its pose and its keypad across server restarts.
