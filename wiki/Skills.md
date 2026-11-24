# Skills

Skills make the actions you repeat faster. Each skill is a value from 0 to 1, shown at the bottom right of the screen as its name and a thin white bar that fills as the skill grows (the ten highest when you have more than ten).

## How skills work

- **Skills persist.** They are saved with your character (about every 10 seconds while they change, and when you log out), so they survive logging out and server restarts. Only death resets them: a new character starts with no skills.
- A skill's bar appears after the first finished action, starting from 0. Finishing an action shows a `+Repair` style notice for five seconds.
- Every time you **finish** an action tied to a skill, the skill closes 2 % of the gap to 1: the new value is `old + 0.02 x (1 - old)`. Early actions count the most, later ones less and less.
- Every time you **start** such an action, its time is cut by half of the skill: `time x (1 - 0.5 x skill)`. At 1.0 a 3 second job takes 1.5 seconds. Nothing is ever faster than half time.
- You can hold up to 50 different skills.

| Actions needed from 0 | Skill reaches | Level |
|--:|--:|:--|
| 6 | 0.10 | Adequate |
| 12 | 0.20 | Intermediate |
| 20 | 0.33 | Experienced |
| 54 | 0.66 | Master |
| 114 | 0.90 | Master |

## Levels

Each skill has a level by its value:

| Level | Skill value |
|:--|:--|
| Novice | under 0.10 |
| Adequate | 0.10 to 0.20 |
| Intermediate | 0.20 to 0.33 |
| Experienced | 0.33 to 0.66 |
| Master | 0.66 and above |

## What trains what

Times are the base time and what it becomes at skill 1.0.

| Skill | Trained by | What it speeds up or improves |
|:--|:--|:--|
| Repair | repairing a vehicle | the repair hold, 3 s to 1.5 s; also the hold for welding armour onto a vehicle, 8 s to 4 s (welding does not train it) |
| Construction | building a [defence](Defences), fitting a Motor or [keypad](Keypads) to a defence, fitting a keypad to a vehicle | building or removing a defence, 10 s to 5 s; fitting a Motor or keypad, 6 s to 3 s (removing a defence is sped up but does not train it) |
| Medical | healing with a Dirty Bandage, Antiseptic Bandage, Medkit or Doctor's Bag, on yourself or another player (pills and injections do not count; see [Bleeding & Wounds](Bleeding-and-Wounds)) | the heal hold, 4 s to 2 s; reviving a knocked-out player, 6 s to 3 s |
| Fishing | a bite that lands on your line | the wait for a bite (30 to 120 s) is cut by up to half, and the chance a bite lands a fish rises from 30 % to 65 % |
| Forestry | felling a tree with a Chainsaw | cutting speed: at 1.0 a tree takes half the time |
| Endurance | covering distance on foot, see below | a running or sprinting jump goes further: its speed is multiplied by `1 + 1.3 x skill`, up to 2.3 times |
| Strength | [pushing a vehicle](Vehicles#pushing) at least 3 m (a full gain from 15 m); climbing: every 5th wall or fence climbed over, or every 15 m climbed up ladders (at most one climbing gain per 10 s) | the push's speed: 0.8 m/s untrained, up to 1.8 m/s at 1.0, before health and the vehicle's weight; the heaviest vehicle you can push: 3000 kg untrained, up to 10,000 kg at 1.0 |
| An item's name | [crafting](Constructing) that item, on the ground or at a [workbench](Workbench) | the same recipe next time: the build hold on the ground, or the workbench's 3.6 s per ingredient; the Crowbar takedown of that item is also shortened, without training |

### Endurance

Endurance gains once for every 500 m run or sprinted, every 200 m swum and every 10th jump on foot, and never twice within 10 seconds (a milestone crossed inside that window is lost). Walking, crouching, driving and falling do not count. Each second is classed by how far you moved in it: 2.5 m or more is running and 5.5 m or more sprinting; less is walking, which earns nothing; crouching, swimming, driving and falling are counted on their own, and a second in which you moved more than 25 m on foot (75 m in a vehicle) is ignored.

`/mstats` opens a window with the distance and time of this session for each kind of movement (walking, running, sprinting, crouching, swimming, driving, falling), your jumps and the time spent knocked out; those counters reset when you log in, the skill does not. See [Commands](Commands).

### Crafting skills

Each thing you can make has a skill of its own, named after it: building Workbenches trains `Workbench`, making Motors trains `Motor`, and so on. They do not carry over to other recipes. Combining two items from the inventory is instant and trains nothing; see [Constructing](Constructing), [Workbench](Workbench) and [Combining](Combining).
