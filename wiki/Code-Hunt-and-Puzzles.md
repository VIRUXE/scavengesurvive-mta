# Code Hunt & Puzzles

Scattered around the map are gates, doors and locked places that open only when you solve something: find the pieces of a code, bring a missing part, or follow a clue. All of them use the same kind of **button**: a spot in the world that shows its prompt in the key list when you are within 1.5 m of it (*Activate*, *Enter*, *Use the lift*, ...). Press the interact key (`F`) there. If an item lies closer to you than the button, `F` picks the item up instead, so step right up to the button. Doors and gates are the same for everyone: what one player opens is open for all.

## Gates and doors

| Where | What |
|:--|:--|
| Chinatown, San Fierro | Two roller shutters, each with a button (*Activate*) on either side. A shutter rises in about 3 seconds and comes down again 3 seconds after it has opened. |
| Easter Basin naval base, San Fierro | The barrier arm at the gate (*Activate gate*) lifts when pressed and stays up until someone presses again. |
| K.A.C.C. Military Fuels, Las Venturas | One button (*Activate*) slides both gates of the compound open in about 8 seconds; they shut again 3 seconds later. The keypad on the post is only decoration, no code is needed. |
| Restricted Area, Bone County | Twelve keypad doors with random codes, see [Area 69](Area-69). |

## Code hunt

![Code](images/items/1898_clicker.png)

In Queens, San Fierro, a lockup is closed behind a door with a keypad. The server makes up a new four-digit code every time it starts and hides four **Code** items around San Fierro, one digit each, at four of eight possible spots: Calton Heights, Paradiso (by the fixed barbecue), Esplanade North, Downtown, Queens, Doherty, Missionary Hill and Easter Bay Airport. The digit is part of the item's name, for example *Code (7)*. The spots change from one start to the next, and the Code items of an earlier code are removed from the world; one you carried off keeps its old digit and is of no use any more.

![The Queens lockup entrance, with its keypad beside the garage shutter](images/places/queens-lockup.png)

1. Collect the four Code items ([Inventory](Inventory)).
2. Press `F` at the lockup's keypad (*Interact*) and enter the four digits. The order is not given, but with four known digits there are at most 24 orders to try; a wrong code is refused (*Incorrect passcode*), and the keypad takes one try every 2 seconds.
3. The right code opens the lockup until the server restarts. The door button outside (*Go inside*) then takes you in, where a few loot points lie, and the button inside (*Leave*) takes you back out. Before the code is entered the door only tells you that it is electronically locked.

A Hack Interface does nothing here (it only works at [Area 69](Area-69)). Anyone who knows the code can go in, so keep the digits to yourself.

## Mount Chiliad radio station

A gate and a door guard the radio station on the summit of Mount Chiliad.

- The gate's button (*Activate*) opens it, and it stays open until pressed again.
- The door's keypad is dead: `F` at the door (*Use*) with empty hands only says *The keypad seems broken*. A **Fuse Box** lies a few metres away. Hold it and press `F` at the door: the fuse box is used up, the keypad has power, and from then on `F` at the door opens and closes it.
- Hold the **Battery** that lies there instead and the keypad shorts out: a shower of sparks, the keypad drops off its mount, and the door is dead until the server restarts.
- Any other item in hand does nothing at the door.

![The summit station and its gate](images/places/chiliad-station.png)

## The ranch and the quarry

1. At a ranch in the south-east of Tierra Robada stands a computer with no hard disk (*Use*): it tells you the disk is missing and finds it mighty suspicious. The **Hard Drive** lies next to it. Hold it and press `F` at the computer: it goes in after a few seconds. `F` again reads the diary on the screen, which says the owner fled to a friend's place on Chiliad and hid a key there; `F` once more leaves the screen.
2. The **Key** lies in a shed on the western slopes of Mount Chiliad.
3. At the bottom of the Hunter Quarry in Bone County a door (*Enter*) will not budge: *There's no way you can get through here without a key. Perhaps you should search the shed?* Hold the Key and press `F`: *You have unlocked the mystery door!* The key is not used up, and the door stays unlocked until the server restarts. From then on `F` at the door takes you down into the caves.

## The caves

The quarry door leads into a cave world of its own. It holds no loot points, but its passages come out across the map. Every passage is a button marked *Enter* (or *Climb up the ladder* / *Climb down the ladder*), and after each jump you are held still for a second.

- Cave 1, where you arrive, has a lift (*Use the lift*) with a button at the top and at the bottom; the ride takes about 19 seconds.
- Passages link cave 1 to cave 2, and cave 2 to cave 3.
- From cave 3 a passage leads to a metro line. At its station another passage leads to the underground of Fort Claw, whose door (*Activate*, a button on each side) shuts 3 seconds after opening; from there an *Enter* comes up in Blueberry, Red County.
- At the far end of the metro tunnels a ladder (*Climb up the ladder*) comes out of a hatch in Ganton, Los Santos; the hatch is a *Climb down the ladder* button for the way back.
- A door marked *Locked* in the metro tunnels never opens.

## Tips

- The puzzle parts must be the ones from their own spot: a Fuse Box, Battery, Hard Drive or Key from elsewhere does not count. If one goes missing the world puts it back at the next server restart.
- Player-built [Keypads](Keypads) are a different thing; the keypads here are fixed in the world.
- See [Ladders & Ziplines](Ladders-and-Ziplines) for the other `F` features of the world and [World & Zones](World-and-Zones) for the map.

## Map

The puzzle sites above ground.

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/puzzles.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/puzzles.png" alt="Map"></a>
