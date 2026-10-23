# MVP smoke checklist (two clients, local server)

Setup: `pwsh server-config/run-local.ps1 -Reset`. Client A and client B connect to `127.0.0.1:22003`
with different MTA nicknames (the account name is the nickname).
On one PC, start the second client with MTA's multiple-instance option, or use a second machine on the LAN.
Record pass/fail and the date. **Any failing step becomes a fix in the task that owns the resource** (lib 4, data 5,
ui 6, auth 7, character 8, items 9, loot 10, hud 11, weapons 12, dev/config 13), with a regression test where one fits.

1. **Boot.** `logs/server.log` shows `Resources: N loaded, 0 failed` and `Server started and is ready to accept
   connections!` with no `ERROR` or `Access denied` line (MTA does not log each resource it starts at boot).
   `rg -n "ERROR" "…/mods/deathmatch/logs/scripts.log"` returns nothing. `mariadb -u root -e "SELECT COUNT(*) FROM
   information_schema.processlist WHERE db='scavengesurvive'"` shows 5 (auth, character, items, loot, dev).
2. **Account.** A registers, logs in and spawns on the shoreline. The HUD shows the stock health bar, the hunger bar above it, the watch bottom-left and the key list on the right; **H** opens the inventory dialog listing `[01]Knife`.
   Relog and log in again with the same password.
3. **DB round trip.** A: `/dbtest` prints `dbtest: <n> ms ok=false code=UNKNOWN_TYPE` with n < 50.
4. **Pick up / drop.** A: `/additem Wrench`. Within 2 s a "Wrench" label appears at the item. **F** picks it up
   (the key list changes to Put away / Drop item), **N** drops it at your feet, **F** picks it up again. B sees each change.
5. **Inventory.** A: **Y** puts the Wrench away. **H** lists it, and **Options → Equip** puts it back in hand. Repeat `/additem` +
   **Y** until the action text says "Extra slots required". The item that does not fit stays in hand.
6. **Bag.** A: `/additem Satchel`, **F**, **Y**: the satchel is worn (visible on the back for B). Put more items away
   than the inventory holds. They overflow into the bag, and **H** shows a `Satchel >` row that opens the `Satchel (used/size)` dialog.
7. **Food.** A: `/additem HotDog`, **F** (the key list shows `F Eat`), **F** again. `/stats` food goes up, and the item is consumed.
8. **Starvation death.** A: `/setfood 0`, `/sethp 3`. Within seconds the death screen shows the rising camera and boxed `YOU ARE DEAD!` / `>Play Again<` lines under the darkened overlay. **Play Again**
   spawns a new character (`/stats` hp=100 food=40) with an AntiSepBandage in **H**. B walks to the corpse spot
   and sees A's old items on the ground.
9. **PvP.** A: `/additem M9Pistol`, **F**, shoots B. B gets the wound action text, B's screen darkens as hp drops below 40, and B's hp drains
   (`/stats` on B). Keep shooting: B dies, and B's items drop where B died.
10. **Loot.** A goes to Los Santos (e.g. Grove Street) and runs `/rollloot`. Items appear at upstream spawn points
    (labels within ~2 s). Run ~500 m away (the MVP has no vehicles): the objects unload. Come back: they reload
    with the same ids.
11. **Restarts.** A holds an item. Server console `rr items`: the item is still in A's hand, and world items reappear
    with no duplicates. `rr character`: `/stats` is unchanged (±1 tick). Then `shutdown` and
    `pwsh server-config/run-local.ps1` (no `-Reset`). A logs in with the same character, position, stats and inventory.

## Post-MVP steps (added as features land)

Results of the 2026-10-22 run: docs/reviews/2026-10-22-live-checks.md (13 and 14 pass; 12 needs a second PC, since
MTA's launcher passes a second `mtasa://` to the already running client instead of opening another one).

12. **Combat log** (#26). A shoots B once: B's watch text turns red and goes white again after 30 s (or at once
    when A quits). B disconnects within 30 s: everyone's chat shows "B combat logged!",
    `scripts.log` has `combat-logged (last hit by A)`, B's items lie where B stood, and B's next login creates a
    new character. Repeat, but B waits 31 s before quitting: B logs back in with the same character. Then shoot B
    and `kick` B from the console within 30 s: B must keep the character (a kick is not a combat log). Finally
    shoot B and `shutdown` within 30 s: note the quit reason MTA reports in `server.log`; if the shutdown counts
    as a combat log, the stop path needs the same guard as a kick.
13. **Weather and clock** (#21). On join the in-game clock matches the host PC's clock (within a minute) and keeps
    pace with it. `scripts.log` has one `[world] weather N (NAME) at start` line per boot, never `SANDSTORM_DESERT`
    (19). `/weather` prints the current id; `/weather rainy_sf` rains for A and B; `/weather 19` is a sandstorm;
    `/weather 20` is refused. `rr world` picks a fresh weather and the clock stays right.
14. **Static maps** (#19). On join the client debug console (F8) shows `maps: N buildings, M objects, K SA-MP models
    skipped, 0 failed, 127 removals in T ms` with no `createBuilding` errors; note N, M, K and T. Grove Street is
    fortified (LS/Fort Defiance) and the Los Santos docks have the fence line (LS/DocksBuildingNorth). Walk through
    one removed building spot (`removals` in `maps/data/LS.lua`): the vanilla model is gone and nothing flickers.
    `/rr maps`: the world is rebuilt once (no doubled objects). An object with both rx and ry non-zero (e.g. the
    `17039` rocks in RC) sits like it does in SA-MP (#55 is answered by measurement: both engines use GTA's ZXY
    `CMatrix::SetRotate`, so this is only a visual confirmation now). Join time and FPS near Grove Street go into the #19 comment.
15. **Loot vehicles** (#30). First boot logs `[vehicles] rolled 2017 spawn points: N vehicles` with N around 80
    (4 %). `/vehcount` matches. Drive one: it starts battered, the engine is off until you start it, some are
    locked, tanks are near empty (no fuel use yet), and the bottom-right vehicle panel shows `DOR`, `ENG`, `DMG`,
    fuel, speed and the vehicle name in Bank Gothic. `rr vehicles`: the same vehicles come back where they were
    left (`N vehicles rebuilt from the database`). `/vehrespawn` drops them all and rolls a fresh set. Blow one
    up: the wreck disappears after 30 s and `/vehcount` drops by one.
16. **Zone colshapes** (#65). Boot logs `[maps] 7 zone colshapes created`. `/zone` prints the player's current zone
    (`ls`, `sf`, `lv`, `rc`, `fc`, `bc`, `tr`); `/zone 2495 -1687` prints `ls`; `rcon.ps1 players` includes `zone=<z>`.
    Crossing a zone border emits `playerZoneLeft` and `playerZoneEntered` and rolls due loot near the player.
17. **Ammo calibres, magazines and reloading** (#24). A: `/additem M9Pistol` and `/additem Ammo9mm`. Pick up `M9Pistol`:
    it equips with one full magazine (`10/0` inside the weapon icon; `[01]M9 (10/0, 9mm, Hollow Point)` when put away in
    **H**). Stand over the `Ammo9mm` tin (`9mm Rounds (20, 9mm, Hollow Point)`) and press **F**: 10 rounds transfer into
    the pistol's reserve (`"Transferred 10 rounds"`, `10/10` inside the weapon icon, `9mm Rounds (10, 9mm, Hollow Point)`
    left on the ground). Fire 3 rounds (`7/10`) and press **R** (`reloadweapon`): the reload animation plays and the
    counter updates to `10/7`. Hold **N** (`dropitem`) for 300 ms (or `/unloadweapon`): the pistol unloads (`0/0`,
    `"There is no ammo loaded in this weapon"`) and drops a `9mm Rounds (17, 9mm, Hollow Point)` tin on the ground.
    Tapping **N** briefly still drops the pistol itself.
18. **Bullet tracers** (#27). A: `/additem M16Rifle` and `/additem Ammo556Tracer`, load and fire. Both A and B see a
    white-to-yellow 3D tracer streak (`dxDrawLine3D`) starting 2 m ahead of the muzzle and travelling at 800 m/s toward
    the hit point. Firing standard `Ammo556` or `Ammo9mm` draws no tracer.
19. **Knockout, handcuffs and disarm** (#25, #28). A hits B with a blunt weapon (`BaseballBat` / `Club`) or shoots B in
    the head/legs until a knockout triggers (or run `exports.character:knockOutPlayer(B, 10000)` via `rcon.ps1 lua`): B
    collapses (`PED:KO_shot_front`), controls are disabled, the `progress2` countdown bar fills across B's screen, and B
    wakes up (`PED:getup_front`) when it finishes. While B is knocked out holding a weapon, A presses **F** with empty
    hands within 2 m to disarm B (`"Disarmed player"`, item moves to A's hands). A equips `HandCuffs` (visible on the
    right-hand bone) and presses **F** near B (unarmed): B's hands lock behind the back and controls are disabled; A
    sees `F Remove handcuffs` with empty hands and pressing **F** uncuffs B and returns `HandCuffs` to A's hands.
20. **Vehicles parity** (#30, #31, #32, #33).
    - **Engine, lights and fuel simulation**: Enter a vehicle as driver: press **Y** (`putaway`) to toggle the engine on/off, **N** (`dropitem`) to toggle headlights. While driving with the engine running, fuel drains continuously (check HUD bottom-right panel `DOR ENG DMG` and fuel L). When fuel reaches 0, the engine cuts out and cannot restart. Sputter/stall chance occurs when health is below 450.
    - **Locks and entry**: Try entering a locked vehicle (`v.locked = 1`): `onVehicleStartEnter` cancels entry, doors rattle, and action text informs the vehicle is locked. Standing outside, `/lock` (or pressing **F** holding a matching `Key`) toggles lock state.
    - **Crowbar lock-breaking**: Outside near a locked vehicle, equip `Crowbar` and press **F**: a 3-second progress bar plays (kick animation). On completion, the lock breaks open and the crowbar takes durability damage.
    - **Locksmith key cutting**: Equip `LocksmithKit` and press **F** near a vehicle: a 10-second progress bar cuts a new `Key` (with matching key code in item data) and adds it to the player's inventory/hands.
    - **Roadside repairs**: Walk to the front (bonnet) of a damaged vehicle:
      - Health < 450 HP: holding `Hammer` (or `SledgeHammer`), press **F** to hammer out the frame back up to 450 HP (3 s progress).
      - Health 450..700 HP: holding `Screwdriver`, press **F** to adjust components up to 700 HP (3 s progress).
      - Health 700..999 HP: holding `Wrench`, press **F** to service the engine up to 1000 HP (3 s progress).
    - **Refuelling**: Hold `GasCan` (Petrol Can) and press **F** near the vehicle: fuel transfers from the can to the vehicle tank over a timed progress bar until full or the can is empty.
    - **Trunk container**: Walk to the rear (trunk) of an unlocked vehicle with empty hands and press **F**: the trunk lid opens (`setVehicleDoorOpenRatio`), and the inventory dialog opens showing the `Trunk (used/size)` screen alongside player inventory. Items can be transferred between hands, inventory, satchel, and trunk. Closing the dialog shuts the trunk lid.
    - **Trailers and towing**: Drive a vehicle with a trailer hitch (e.g. `Sadler`, `Bobcat`, `Yosemite`, `Linerunner`) backing up near a compatible trailer (e.g. `Baggage Trailer`, `Farm Trailer`). Type `/tow`: the trailer attaches (`attachTrailerToVehicle`). Type `/tow` again: the trailer detaches. Attaching persists across resource restarts (`rr vehicles`).
21. **Crafting, Building and Apparel parity** (#35, #36, #37, #38, #39).
    - **Apparel bone attach & protection**:
      - Equip `CowboyHat` / `ArmyHelmet` / `Mask` / `Bandana` / `Armour`: visible attached on head/face/spine bones with upstream offsets.
      - Body damage protection: Torso damage bleed reduced by 50% when wearing `Armour`; Head shot knockout chance reduced by 60% when wearing a helmet/hat.
    - **Body preview & Gear tiles**:
      - Press **Tab** / open inventory: left Body Panel shows Health status, individual bodypart wound counts (Head, Torso, Arms, Groin, Legs) in red when injured, Bleeding status, Hunger %, and unconsciousness chance formula.
      - Right side displays 6 Gear Tiles (`HEAD`, `FACE`, `HAND`, `HOLSTER`, `TORSO`, `BACK`). Clicking an equipped tile takes off the item into hands/inventory; clicking an empty tile with matching held item wears it; clicking `BACK` navigates directly to worn bag. Wearable items in inventory also have a `Wear` option.
    - **Safeboxes & Tents as persistent containers**:
      - World safeboxes (`SmallBox`, `MediumBox`, `LargeBox`, `Locker`, `ToolBox`, `Capsule`, `Suitcase`, etc.): Press **F** near a world safebox to open its persistent container dialog; transfer items between hands and box. When empty, `[Pick up container]` option in dialog allows picking up the box into hands.
      - `TentPack`: Place on ground. Standing near it holding `Hammer`, press **F**: 3-second progress bar pitches the tent into a full 3D tent (model 3243) with a 16-slot container. Interacting with pitched tent opens tent container. Holding `Crowbar` near an empty tent and pressing **F** plays a 3-second packing progress bar, packing it back into portable `TentPack`.
    - **Crafting & Workbench**:
      - In-hand combine: Hold `Knife` and click `Clothes` in inventory -> click `Combine`: instant craft produces `Bandage` in inventory while preserving the `Knife`. Combine `Bottle` + `Bandage` -> `MolotovEmpty`.
      - Ground construction: Drop ingredients on ground (e.g. 2x `WoodLog`), hold `FireLighter`, press **F** (or `/craft`): 3-second construction progress bar consumes logs and spawns `Campfire`. Hold `Hammer` near 3x `WoodLog` -> builds `Barricade`. Hold `Hammer` near 2x `WoodLog` + 2x `CorPanel` -> builds `Workbench`.
      - Deconstruction: Hold `Crowbar` and press **F** near constructed object (`Campfire`, `Workbench`, `Barricade`, `LargeFrame`): timed deconstruction progress bar dismantles the object and returns raw materials.
      - Workbench crafting: Place materials in Workbench 16-slot container (e.g. `CorPanel` + `Battery` + tool `Screwdriver`), press **F** at Workbench: crafts `Keypad` inside container.
    - **Defences, Keypads and Plot Poles**:
      - Defences (`LargeFrame`, `Door`, `MetalGate`): Press **F** on an unlocked door/gate to swing it open (+90 deg rotation) with 5-second auto-latch closing.
      - Keypad security: Hold `Keypad` item and press **F** on defence: installs keypad and opens 12-key Keypad UI to set 4-digit code. Interacting with locked defence opens Keypad UI: enter 4-digit code with mouse/numpad, press `>` (Enter); correct code grants access and swings door open for 5 seconds; wrong code plays error sound.
      - `LockBreaker` & `HackDevice`: Hold `LockBreaker` on locked door -> 10s break action removes lock. Hold `HackDevice` on keypad -> 8s bypass timer swings door open.
      - `PlotPole`: Placing `PlotPole` creates 20m claimed territory colshape: entering displays `PLOTPOLEENT` action text; leaving displays `PLOTPOLEEXT`.
22. **Staff & Ops** (#41, #42, #43, #44). Give A level 4 (`UPDATE accounts SET admin_level = 4 WHERE name = 'A'`,
    relog) and leave B at level 0. One-client run of 2026-10-23: `docs/reviews/2026-10-23-m7-live.md` (a, c, d, e, g, h
    and the self-only parts of b and f pass; the kick/ban/mute of B, the whitelist and warning kicks, spectate, duty
    immunity, the kick request and the MOTD on login still need the second PC). Driving A by script: replies are read
    with `rcon.ps1 chat A`, since screenshots never include the chat box.
    - a. **Boot and gate.** `scripts.log` has no `Access denied` for `staff`; B types `/acmds` and gets MTA's unknown
      command notice; A's `/acmds` opens the list dialog with the Lead, Administrator, Moderator and Game Master groups.
    - b. **Mute.** A: `/mute B 30s testing`. B sees `Muted from global chat for 30 seconds`, B's chat lines do not
      appear for A and B gets `You are muted. Time remaining: …`; after 30 s B sees `You are now un-muted`. `/mute B
      forever x`, B relogs: still muted; `/unmute B` lifts it. `staff_actions` has `mute` and `unmute` rows.
    - c. **Warn and ban.** A: `/warn B reason` five times. The fifth prints `reached 5 warnings and was banned for
      24h`, B is kicked and on rejoin sees the three ban lines (`You are banned …`, `Reason: Getting 5 warnings`,
      `Unban: <tomorrow>`) and is kicked after a second; `accounts.warnings` for B is 0 again. A: `/unban B`; B joins.
      `/ban B 10m test` with B online kicks B; `/banned B` and `/banlist` show the ban; the `Unban` row action lifts it.
      Offline: `/ban Nobody 1h x` fails with `does not exist`; `/ban <offline account> forever x` records the account's
      last IP and serial (`SELECT ip, serial FROM bans`).
    - d. **Whitelist.** A: `/whitelist on`; B relogs and is kicked after a successful login with `not whitelisted`;
      `/whitelist add B`, B logs in; `/whitelist ?` and `/whitelist list` show B; `/whitelist off`.
    - e. **Reports.** B: `/report A testing report`, `/report near hello`, and after A kills B `/report killer x`.
      A sees `B reported …` lines and `/reports` lists `[new] B (PLY ID)` rows; `View` prints the details and clears
      the marker, `Go to position` needs duty, `Delete` removes the row, `/deletereports` clears the read ones.
    - f. **Duty, teleports, spectate.** A: `/goto B` is refused off duty; `/duty` swaps A's skin to 217/211, name
      tags appear over B, and B's shots no longer wound A (`/stats` on A unchanged); `/goto B`, `/get B`, `/gotopos
      0 0 5` move the right player; `/spec B` makes A invisible to B, A's screen shows the `Spectating B` banner and
      the arrow keys cycle; `/free` returns A to where they stood; `/duty` off restores the skin.
    - g. **Freeze, kick request, staff chat.** A: `/freeze B 5` holds B for five seconds (`Frozen by admin for 5
      seconds`); `/a hello` is visible to A only; with a level-5 account C online, A's `/kick B x` becomes a request
      line on C's screen instead of a kick.
    - h. **Accounts.** `/profile B`, `/history B`, `/aliases B`, `/ip B`, `/adminlist`, `/players` print or list
      without errors; `/setadmin B 1` promotes B live (B's `/acmds` works without relog); `/setactive B 0` kicks B and
      blocks B's login (`INACTIVE`); `/setactive B 1`; `/resetpassword B newpass` lets B log in with the new password;
      `/setmotd Welcome` is shown to B on login and `/setmotd off` clears it; `/restart world` restarts the resource.
23. **Supply drops and weapons caches** (#47). A at level 4.
    - a. `/sc` lists the five types with their player requirements; `/sc 1` prints the yellow `[EBS]: SUPPLY DROP:
      "Food and Medical"` (or `"Unknown"`) `INCOMING AT: "staff request"` line for everyone, a blip appears on the
      map, and a crate with a smoke trail descends over A's position for about 4-5 minutes (from z 1000 at 3.5 u/s).
    - b. Stand on the landing spot: on landing A is pushed 3 m away and the two stacked crates (3799, the top one
      upside down) stay there with smoke rising and a yellow `Supply Crate` label; within 3 m the key list shows
      `F Open supply crate` and **F** opens the `Supply Crate (n/32)` container with 4-19 items from
      `airdrop_food_medical` (fewer when the size units run out), nothing on the ground around it. `scripts.log`
      has `supply crate (Food and Medical) at …: i of n rolled items in the crate`, `world_crates` has one `supply`
      row. A second `/sc` while one is falling is refused (`IN_FLIGHT`); the next landing removes the previous
      supply crate with its contents.
    - c. `/wc`: the metal crate (object 964) appears at A's feet with a `Weapon Cache` label; **F** opens the
      `Weapon Cache (n/32)` container holding about nine military weapons and ammo tins (`weapons cache at …: i of
      n rolled items in the crate` in the log), and everyone reads `[EBS]: WEAPONS CACHE SIGNAL: BEARING: xDEG
      DISTANCE: yM` three times, 200 s apart; the bearing/distance from a cache point near Esplanade
      (`weapon_cache_points`, all in `sf`) leads to the crate. `/wc` while signals run is refused (`ACTIVE`).
      `rr loot` rebuilds both crates from `world_crates` with their contents.
    - d. Automatic: with 3 players online and no drop for 10 min, `scripts.log` logs `supply drop Food and
      Medical (<point name>) falling to …` within a minute and `supply_drop_points.used_at` is set for that point;
      with 4 players a cache appears within 25-35 min at a point with nobody within 500 m. `rr loot` while a crate
      is falling removes the crate object and blip (the drop is lost, nothing lands).
24. **Chat modes and the radio** (#49). Two clients A and B.
    - a. **Modes.** A types a message: B within 40 m sees `[Local] A: …` in light blue; B 50 m away sees nothing.
      `/g` switches A to global (`You turn your radio on to the global frequency`), plain messages now reach B
      anywhere as `[Global] A: …`; `/g hi` sends one global line without switching; `/l` back to local; `/me waves`
      prints `[Local] A waves` nearby; `/quiet` on B hides global lines until `/quiet` again.
    - b. **Radio.** A: `/freq 101.3`, B: `/freq 101.3`, both `/r`: messages show as `[101.30] A: …` in orange for both;
      B `/freq 101.4` still hears (0.05 window), `/freq 101.5` no longer does. The watch bottom-left shows each
      player's own frequency live.
    - c. **Panel.** In a vehicle press **R** (the key list shows `R Open radio`), or `/radio` anywhere: the RADIO
      panel at 320,200 with the dial strip, two red knobs (±0.5 MHz, clamped to 87.5-108.0), `global`/`freq`
      toggle, `Frequency: x` (mouse wheel over it: ±0.01), red `on`/`off` power (off = local chat, on returns to the
      last transmitting mode) and Close; hovering highlights; Escape closes. Changes show on the watch at once.
    - d. **Persistence and guards.** A relogs: frequency and mode are back (`characters.radio_freq`, `chat_mode`).
      A sends four messages inside a second: the first three go out and the fourth is refused with `Muted from global
      chat for 30 seconds for chat flooding` (upstream mutes when the streak reaches 3), `/profile A` shows muted, and
      30 s later `You are now un-muted`. A level-0 account cannot `/a`.
25. **House loot** (#48). Walk into a hollow house in San Fierro (e.g. the Ocean Flats block, model 19490 at
    -2787.6, -161.0): `world_civilian` items lie at the upstream offsets inside half of the houses (seed
    `0006_house_loot.sql`, 116 points, ids above 11062); they roll like any spawn (`loot_spawn_state.next_roll_at`,
    `items.loot_spawn_id`), but only while no player is within 150 m (#67), so stand back before `/rollloot`; the
    other half of the houses stay empty every time (deterministic selection by position).
26. **Languages** (#51). `/lang` alone lists the ten codes and the current one; `/lang pt` then `/mute` yourself from a second
    account or trigger any translated line (e.g. get kicked with a reason): the line arrives in Portuguese; `/lang xx` is
    refused with the usage line; a key missing from the language (one of the 149 English-only keys) arrives in English;
    `/lang en` restores. `docs/languages-qa.md` matches `python -m tools.lang_qa --check`.
27. **Ladders and ziplines** (#50). Needs a client; the rope and the climb are client-side.
    - a. **Ladders.** `/gotopos -1056 -628 33` (level 2+ on duty), or walk to the Flint County radio mast ladders listed in
      `world/data/features.lua` (14 ladders). Within 1 m of the base the key list shows `F Climb ladder`; **F** snaps you
      onto the ladder facing it with the climb pose. **W** climbs at 0.1 per frame, **S** descends slower, no key holds
      your place, and the list shows `F Let go`. Past the top (after 1 s on the ladder) you step off forward; **F**
      half-way drops you with a forward nudge.
    - b. **Ziplines.** `/gotopos 2159 -986 71` (Los Santos; 13 ziplines; the start anchors hang in the air beside the
      roofs, as upstream placed them). A dark rope line is visible between the two anchors. Within 2 m of the start (or anywhere under the rope) the list shows `F Grab zipline`; **F** hangs you 1.2 m
      below the rope and you accelerate to the far end. You let go 6 m from the end (or with **F**, or when knocked more
      than 5 m off the line) with a forward boost.
    - c. **Guards.** Nothing happens while knocked out, cuffed, dead or in a vehicle. `rr world` while climbing or riding
      drops you back to normal controls.
28. **Scarcity-driven respawn** (#67, ADR 0001). Server log only, no client needed for a-c.
    - a. **Budget rows.** After `rr vehicles` and `rr loot`: `SELECT * FROM world_budget` has one `vehicles`/`all` row
      (cap = the first roll, about 80, or the vehicles alive when the budget was first created) and one `loot` row per
      zone (`bc fc ls lv rc sf tr`, cap = points × 2, allowance = cap on the first start).
    - b. **Refill ticks.** Every 5 minutes (`world.refill_interval_s`) the log shows
      `[vehicles] refill: cap N alive N removed 0 spawned 0` and `[loot] refill: 7 zones, alive A/C, allowance X (+Y)`.
      With the world full both `spawned` and `+Y` stay 0; `/vehcount` is stable over hours. Blow up a vehicle (or set
      `vehicles.refill_rate` to `20` and `rr vehicles`): the next ticks report `spawned 1` and `/vehcount` recovers,
      never above the cap, with the new vehicle on a cooled point out of sight (150 m or more away).
    - c. **Cooldowns.** `SELECT COUNT(*) FROM vehicle_spawn_state WHERE next_roll_at > NOW()` equals the vehicles rolled
      (6 h ± 33 %). Drive one more than 100 m from its point: within a minute its row has `left_spawn = 1` and its
      point gets a fresh `next_roll_at`.
    - d. **Loot allowance.** Loot a point empty and stand there: it does not re-roll for its cooldown (60 min ± 50 %),
      and the `[loot] refill` line shows `alive` unchanged (the carried items still count: `items.loot_zone` keeps the
      zone after pickup). Nothing rolls within 150 m of any player: walk away and back after the cooldown, the point
      refilled while you were out of range, provided the zone's allowance (`exports.loot:lootAllowances()` through
      `rcon.ps1 lua`) was above 0.
