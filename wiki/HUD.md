# HUD

The screen shows only what your character would know: there is no map, no money, no wanted level and no GTA clock. The HUD appears once your character has spawned and is hidden on the death screen.

<!-- shot:shot-hero-gameplay -->

## Top right

- **Health bar**: GTA's own red bar, filled to your [health](Health).
- **Hunger bar**: a green bar of the same width just above the health bar, filled to your hunger (see [Food & Drink](Food-and-Drink)).
- **Weapon icon**: GTA's icon of what you hold. A loaded firearm shows `magazine/reserve` (for example `10/0`) underneath; see [Firearms](Firearms).
- **No armour bar**: the points of a worn vest show only in the inventory's `TORSO` tile; see [Armour](Armour).
- **Area name**: shown briefly when you enter a new district.
- **Crosshair** while aiming.

The radar, money, clock, wanted stars, breath meter, vehicle name and radio station of the stock HUD are hidden.

## Key list (right side)

Under the weapon icon a column lists what your keys do right now: the key in yellow, the action in white. It follows the keys you have bound (see [Controls](Controls)) and changes with what you hold and what is near you, for example:

| Situation | Lines |
|:--|:--|
| Empty hands | `H Open inventory`; `Y Draw weapon` with a holstered weapon; `N Remove bag` with a bag on; `F Remove handcuffs` next to a cuffed player |
| Holding a firearm | `Y Holster weapon` (or `Put away`), `R Reload`, `N (Hold) Unload`, `N Drop item` or `N Give item` (a player within 1.5 m), `H Open inventory` |
| Holding anything else | `Y Put away`, `N Drop item` / `N Give item`, `H Open inventory`, plus the item's use: `F Eat`, `F Cook` (by a campfire), `F Drink`, `F Open satchel`, `Y Wear`, `F Wear clothes`, `F Wear armour`, `F Take Pills`, `F Read note`, `F Locate phone`, `F Cast line`, `F Place shield`, `F Deconstruct` (Crowbar) |
| Near things | `F Open` / `F (Hold) Pick up` at a bag or box on the ground; `F Access machine` / `F (Hold) Machine menu`; `F Open door`, `Close door` or `Door locked` at the Airstream's door; `F Climb ladder`, `Grab zipline`, `Let go`; `F Open supply crate` / `Open weapon cache`; the label of a button or gate; the [armour](Vehicle-Armour) lines (`Attach to trailer`, `Take torch`, `Weld panel`, `Grind panel off`...) |
| Driving | `R Open radio` (`(Hold) Open radio` with a firearm in hand) and `Hitch trailer` / `Unhitch trailer` on the hitch key when a trailer is in reach or towed |

The list is hidden while a dialog is open and while you are knocked out.

## Bottom left: the watch

Bearing, time and radio frequency on a black oval; see [Watch](Watch).

## Bottom right: the vehicle's name

While you drive, the vehicle's name sits in the bottom right corner. The doors, engine, fuel and speed are on the [Driver's Dashboard](Drivers-Dashboard) at the bottom centre; damage shows on the vehicle itself, as engine smoke and body damage. See [Vehicles](Vehicles), [Fuel](Fuel) and [Repairing & Locks](Repairing-and-Locks).

## Centre of the screen

- **Action text**: one white line at about three quarters of the way down, replaced by each new message and gone after 3 seconds: `Equipped`, `Trunk locked`, `Extra 2 slots required`, `Engine stalled`, `Wounded: head  -12 hp  (bleeding)`, `Healed 2 wounds`...
- **Progress bar**: a small grey bar above the action text while a held action runs (repairing, refuelling, a treatment, welding, casting a line...). It is cancelled when you move or let go of the key. The same bar reads out a knockout while you are unconscious.
- **Help tips**: green text to the left of the centre with a tip for what you are doing, sometimes with a blue line under it. The tip on getting into a damaged vehicle stays 20 seconds. `/tooltips` turns them off and on; the choice is saved on your account.
- **Skill notice**: `+Repair` and the like in green at the bottom for 5 seconds after an action trains a [skill](Skills); while you drive it sits just above the dashboard.
- **Heat bar**: a red bar with `Overheating!` while you drive an armed vehicle and fire its gun, see [Vehicles](Vehicles).
- **Darkness**: the screen darkens more and more below 40 health. Painkillers and Adrenaline hide it, see [Drugs](Drugs).
- **Whitelist countdown**: `Not whitelisted / Time remaining mm:ss` at the top of the screen when the server's whitelist turns on and you are not on it, see [Account & Login](Account-and-Login).
- **Death screen**: see [Death](Death).

## Windows

- **List dialogs** (the inventory, bags, trunks, the report menu...): a title with `(used/size)` for containers, rows with the selected one in red, a scrollbar and two buttons. `Enter` presses the left button, `Escape` the right one. See [Inventory](Inventory).
- **Message and input boxes** (login, the welcome text, notes, the frequency entry, a body's coroner line): `Enter` and `Escape` are the two buttons; `Ctrl+V` pastes into a field.
- **Information windows** (`/help`, `/rules`, `/admins`, `/credits`, `/chatinfo`, `/mstats`): close with the Close button, `Escape` or `Enter`.
- The **radio panel** ([Radio](Radio)), the **keypad** ([Keypads](Keypads)) and the **tweak pad** for placed items ([Constructing](Constructing)) have their own pages.
- The **chat box** in the top left corner is MTA's; see [Chat](Chat).
