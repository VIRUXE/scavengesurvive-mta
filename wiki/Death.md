# Death

![Torso](images/items/2907_kmb_deadtorso.png)

You have one character. When its [health](Health) reaches 0 it dies for good: everything it carried lands on the ground, a body is left behind, and the next character starts from nothing. Being knocked unconscious is not death (see [Health](Health)); quitting in the middle of a fight is treated as one (see [Combat Log](Combat-Log)).

## Ways to die

- Bleeding out from [wounds](Bleeding-and-Wounds), or starving (hunger under 20, see [Health](Health)).
- Bullets, blades, fists, explosions, fire, a fall, drowning, being run over.
- The Air [drug](Drugs) from an empty injector.

## What happens when you die

1. Your character falls. A second and a half later the **death screen** comes up: the camera rises slowly over the body for half a minute while the screen darkens, with `YOU ARE DEAD!` and a `>Play Again<` button in the middle. The rest of the HUD is hidden.
2. Everything you held, wore and carried drops where you fell: the item in your hands, your bag (with everything in it), your hat, mask and [armour](Armour), and every item of your inventory. They land in a ring of 9 spots 1.5 m around the body, one every 40 degrees, each facing a random way; a tenth item shares the first spot, and so on. A **Clothes** item holding the clothes you died in lies 1 m to the east of the body (see [Clothes & Hats](Clothes-and-Hats)).
3. A **body** is left where you died: a Torso item carrying your name and the cause of death (below).
4. Dropped items disappear after 120 minutes if nobody picks them up, like any loot (see [Loot & Respawn](Loot-and-Respawn)). Anyone can take them, including whoever killed you. Your blood trail stays behind for a while too.

<!-- shot:shot-death-screen -->

Clicking `>Play Again<` creates your next character. Your [skills](Skills) are gone with the old one.

## The body

The body lies on the ground as an item named *Torso*. Standing next to it with empty hands:

- tap `F` to **investigate** it: a window titled with the dead player's name shows the coroner's line;
- hold `F` to **pick it up**. It is carried in both arms like a crate (you cannot get into a vehicle with it), so a body can be moved or hidden.

With a **Combat Knife** in hand, `F` on the body **harvests** it: a 3 second hold that leaves one raw **Meat** on the body, once per body, and only within a day of the death (*The body has decomposed too much to harvest* afterwards). Cook the meat before eating it, see [Campfire & BBQ](Campfire-and-BBQ) and [Food & Drink](Food-and-Drink).

### The coroner's line

| How the character died | What the body says |
|:--|:--|
| Fists or a blunt weapon | They were beaten to death. |
| A knife | They suffered small lacerations on the torso, possibly from a knife. |
| A katana | Large lacerations cover the torso and head, looks like a finely sharpened sword. |
| A chainsaw | There's bits everywhere, probably suffered a chainsaw to the torso. |
| Gunfire | They died of blood loss caused by what looks like bullets. |
| An explosion | They suffered massive concussion due to an explosion. |
| Fire | The entire body is charred and burnt. |
| A spray can or fire extinguisher | They were sprayed and suffocated by a high pressure substance. |
| A fall | Most bones are broken, looks like they fell from a great height. |
| Drowning | They drowned. |
| Bleeding out, or run over by a driver | They bled to death. |
| Starvation | They starved to death. |
| Anything else (the Air drug, a crash with nobody at the wheel) | They died for an unknown reason. |

## Your next character

`>Play Again<` spawns a new character at one of 14 spawn points at the water's edge, never the same one as your last spawn, wearing random clothes of a random gender: the ocean shore west of San Fierro (Ocean Flats and the coast south of it) and of Whetstone, the south coast of Flint County, the river banks and lagoon shores of Red County, and the shores of Tierra Robada and of the bay at the south-west corner of Bone County.

| Character | Health | Hunger | Starts with |
|:--|--:|--:|:--|
| Your very first one | 90 | 80 | a Combat Knife |
| Every one after a death | 100 | 40 | an Antiseptic Bandage |

Nothing else carries over: no items, no skills. Your account, language and password are untouched; your old character's items are still lying where it died, so going back for them is an option, for you and for everyone else.

`/dropall` drops everything the same way without dying, with your hands up; see [Surrender & Disarm](Surrender-and-Disarm) and [Commands](Commands).

## Map

The beaches a new character can wake up on.

<a href="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/spawns.png" target="_blank" rel="noopener noreferrer" title="View full-size map; Ctrl/Cmd-click or middle-click to open in a new tab"><img src="https://raw.githubusercontent.com/wiki/VIRUXE/scavengesurvive-mta/images/map/spawns.png" alt="Map"></a>

See also [Health](Health), [Combat Log](Combat-Log) and [Getting Started](Getting-Started).
