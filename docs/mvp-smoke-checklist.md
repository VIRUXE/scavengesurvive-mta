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
   `/changepass` alone prints the usage line; `/changepass wrong newpass` says the password doesn't match;
   `/changepass <old> abc` says 4 to 32 characters; `/changepass <old> newpass` confirms with the new password in blue,
   and the next login takes `newpass` only (#82).
   On join A reads the orange `Scavenge and Survive (Copyright (C) 2016 Barnaby "Southclaws" Keene)` line and, when
   a MoTD is set, `MoTD: …`; B reads `A has joined`. A quitting shows B `A left the server.`, a timeout `A lost
   connection.`, a kick nothing (#84).
   `/help` and `/chatinfo` open message boxes with a lone Close (tabs as indents, colours kept); `/welcome` re-shows
   the welcome box closable at once; `/rules` and `/admins` list `server.rules` / `server.staff` (entries split on
   `|`, "total: 0" when empty); `/credits` and `/motd` print in chat (#85).
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
    Tapping **N** briefly still drops the pistol itself. **Ammo persistence** (#78, open live check in #80): reload,
    fire 2 rounds and `rr items` at once: the pistol comes back in hand with the count it had (the stop writes the
    held ammo synchronously); fire 2 more, wait 6 s and `SELECT data FROM items WHERE id = <id>` shows the new count
    (the 5 s `item_data_flush`); fire again and put it away (**Y**): the row has the count at once.
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
        With the ingredients within reach, **F** with the tool in hand builds (it no longer says `You are already
        holding an item`, #116); a tool in hand next to items that match no recipe says `Cannot craft these items`.
      - Deconstruction: Hold `Crowbar` and press **F** near constructed object (`Campfire`, `Workbench`, `Barricade`, `LargeFrame`), even with another item lying closer (#97): timed deconstruction progress bar dismantles the object and returns raw materials.
      - Workbench crafting: Place materials in Workbench 16-slot container (e.g. `CorPanel` + `Battery` + tool `Screwdriver`), press **F** at Workbench: crafts `Keypad` inside container.
    - **Defences, Keypads and Plot Poles**:
      - Defences (`LargeFrame`, `Door`, `MetalGate`): Press **F** on an unlocked door/gate to swing it open (+90 deg rotation) with 5-second auto-latch closing.
      - Keypad security: Hold `Keypad` item and press **F** on defence: installs keypad and opens 12-key Keypad UI to set 4-digit code. Interacting with locked defence opens Keypad UI: enter 4-digit code with mouse/numpad, press `>` (Enter); correct code grants access and swings door open for 5 seconds; wrong code plays error sound.
      - `LockBreaker` & `HackDevice`: Hold `LockBreaker` on locked door -> 10s break action removes lock. Hold `HackDevice` on keypad -> 8s bypass timer swings door open.
      - `PlotPole`: Placing `PlotPole` creates 20m claimed territory colshape: entering displays `PLOTPOLEENT` action text; leaving displays `PLOTPOLEEXT`.
      - Tweaking (#133, step 36): building a defence or constructing an item on the ground opens the tweak pad.
22. **Staff & Ops** (#41, #42, #43, #44). Give A level 4 (`UPDATE accounts SET admin_level = 4 WHERE name = 'A'`,
    relog) and leave B at level 0. One-client run of 2026-10-23: `docs/reviews/2026-10-23-m7-live.md` (a, c, d, e, g, h
    and the self-only parts of b and f pass; the kick/ban/mute of B, the whitelist and warning kicks, spectate, duty
    immunity, the kick request and the MOTD on login still need the second PC). Driving A by script: replies are read
    with `rcon.ps1 chat A`, since screenshots never include the chat box.
    - a. **Boot and gate.** `scripts.log` has no `Access denied` for `staff`; B types `/acmds` and gets MTA's unknown
      command notice; A's `/acmds` opens the CEGUI list with the Lead, Administrator, Moderator and Game Master groups.
      B presses P: nothing opens; A presses P: the staff panel lists the same commands; picking `/goto` shows a
      player field with B in the picker, Run with it blank says `Fill in player.`, with B picked it teleports (on
      duty) and the reply shows in the panel's output box; Escape closes the panel.
    - b. **Mute.** A: `/mute B 30s testing`. B sees `Muted from global chat for 30 seconds`, B's chat lines do not
      appear for A and B gets `You are muted. Time remaining: …`; after 30 s B sees `You are now un-muted`. `/mute B
      forever x`, B relogs: still muted; `/unmute B` lifts it. `staff_actions` has `mute` and `unmute` rows.
    - c. **Warn and ban.** A: `/warn B reason` five times. The fifth prints `reached 5 warnings and was banned for
      24h`, B is kicked and on rejoin sees the three ban lines (`You are banned …`, `Reason: Getting 5 warnings`,
      `Unban: <tomorrow>`) and is kicked after a second; `accounts.warnings` for B is 0 again. A: `/unban B`; B joins.
      `/ban B 10m test` with B online kicks B; `/banned B` and `/banlist` show the ban; the `Unban` row action lifts it.
      Offline: `/ban Nobody 1h x` fails with `does not exist`; `/ban <offline account> forever x` records the account's
      last IP and serial (`SELECT ip, serial FROM bans`).
    - c2. **Ban dialogs** (#85). A: `/ban B` alone: B is frozen at once (the frozen line, no movement or controls)
      and A sees "Please enter ban reason" (Continue / Cancel; Cancel bans nobody and unfreezes B), then "Please
      enter ban duration"; Back returns to the reason, `soon` asks again, `10m` bans B for ten minutes (same kick
      and staff line as c.), `forever` permanently. `/unban B` after. A disconnecting mid-dialog unfreezes B; B
      quitting mid-dialog is still banned when A finishes. A `/freeze`-d B stays frozen after a Cancel.
    - d. **Whitelist.** A: `/whitelist on`; B relogs and is kicked after a successful login with `not whitelisted`;
      `/whitelist add B`, B logs in; `/whitelist ?` and `/whitelist list` show B; `/whitelist off`.
    - e. **Reports.** B: `/report A testing report`, `/report near hello`, and after A kills B `/report killer x`.
      A sees `B reported …` lines and `/reports` lists `[new] B (PLY ID)` rows; `View` prints the details and clears
      the marker, `Go to position` needs duty, `Delete` removes the row, `/deletereports` clears the read ones.
    - e2. **Report dialogs** (#85). B: `/report` alone opens "Report a player" with the four upstream modes (Send /
      Cancel). Online → a list of the other players (Report / Back; Back returns to the modes), pick A → "Enter
      report reason" input; Back there returns to the modes, Report with an empty field asks again, a reason files
      it (`Report filed`, A sees the line). Offline name → "Report Offline Player" input, then the reason. Killer
      with nobody having killed B and Near with nobody within 100 m print the upstream red lines and close the
      menu. `/report A` without a reason skips the menu and opens the reason input.
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
      `/setmotd Welcome` is shown to B on join (`MoTD: Welcome`, #84) and `/setmotd off` clears it; `/restart world` restarts the resource.
    - i. **Login alias report** (#83). B logs in from A's PC (or under a second name on B's): A reads
      `Aliases: (n) …` in yellow. Ban B's other name while it is offline (`/ban <name> 1h test`), then log in as B
      again: A also reads the red `Warning: One or more of those aliases is banned!`; with A offline, B is kicked
      with `One of your previously used accounts is banned.` `/unban <name>` afterwards.
    - j. **Whitelist auto and auto-login** (#86). `/whitelist on`, `/whitelist auto`: A (level 4) logging in reads
      `Auto-whitelist: Deactivated the whitelist.`; after A quits, B (not listed) is refused. `UPDATE settings SET
      svalue = '1' WHERE skey = 'player.auto_ip_login'`, `rr auth`: A is logged in without the dialog, B from another
      PC under A's name still gets it. Set both back to 0.
    - k. **Whitelist countdown** (#90). With B (not listed, level 0) logged in, `UPDATE settings SET svalue = '30'
      WHERE skey = 'server.whitelist_kick_s'`, `rr auth` (both log in again), then A: `/whitelist on`. B sees
      `Not whitelisted` / `Time remaining: 00:30` counting down at the top right; `/whitelist add B` hides it; `/whitelist
      remove B` starts it again; at 00:00 B reads the not-whitelisted lines and is kicked with `Not in whitelist`.
      Repeat with `/whitelist off` before zero: the text goes away and B stays. Set the setting back to 300.
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
    - c2. **Frequency input** (#85). Click `Frequency: x`: the "Frequency" input dialog (`Enter a frequency between
      87.5 and 108.0`, Accept / Cancel) over the panel. `101.3` + Enter retunes to 101.30 and the panel stays
      open; `120`, `abc` or an empty field asks again; Escape or Cancel closes only the dialog, the panel stays.
      Clicks on the dialog do not reach the knobs under it.
    - c3. **Inventory row** (#49). Open the inventory on foot: the last row is `Radio` (after the bag and trunk
      rows); selecting it closes the inventory and opens the RADIO panel. Bag and trunk views have no Radio row.
    - d. **Persistence and guards.** A relogs: frequency and mode are back (`characters.radio_freq`, `chat_mode`).
      A sends four messages inside a second: the first three go out and the fourth is refused with `Muted from global
      chat for 30 seconds for chat flooding` (upstream mutes when the streak reaches 3), `/profile A` shows muted, and
      30 s later `You are now un-muted`. A level-0 account cannot `/a`.
    - e. **Voice** (built-in MTA voice, `<voice>1</voice>`). Both in local mode: B within 40 m (same dimension) hears
      A talk, B 50 m away does not, and walking out of range while A keeps talking cuts A off within about half a
      second. Both `/freq 101.3` and `/r`: B hears A anywhere; A in `/g`: everyone without `/quiet` hears A. Nobody
      hears their own voice. `/mute A 30s testing`: A's voice reaches nobody and A sees `You are muted: nobody hears
      your voice until the mute ends` once (not on every key press); after the un-mute A is heard again.
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
    - e. **One call per batch** (#78). `rcon.ps1 lua return exports.loot:rollNear(2000, -1500, 600)` with nobody
      near: one `loot_roll` call places the batch, the `ls` row of `world_budget` loses exactly the items created,
      every new bag or safebox has its `containers` row, and
      `SELECT COUNT(*) FROM items i LEFT JOIN world_items_pos p ON p.item_id = i.id WHERE i.x IS NOT NULL AND p.item_id IS NULL`
      is 0 (the `items` triggers keep the positions; no `loot_roll` warning in `scripts.log`).
29. **Clothes and the spawn pool** (#76). One client.
    - a. **Spawn roll.** New characters spawn in one of upstream's 29 clothes skins of a random gender, civilians most
      of the time; a headgear skin (biker 254, cop 283, SWAT 285, military 287) shows its hatless twin under a hat.
    - b. **Label.** `/additem Clothes` a few times: each shows as "Male …" or "Female …" with its type name, the same
      in the inventory and on the ground, and the name survives a pickup, a drop and a resource restart.
    - c. **Change.** Use a Clothes item of your gender (held or from the inventory): a 3 s progress bar (unlabelled, like upstream's hold bar),
      then the skin changes and the item now shows the clothes you took off; relog and the new skin stays
      (`characters.skin`). Walking during the bar cancels it; the wrong gender says "Wrong gender for clothes"; on
      staff duty it says to go off duty first.
    - d. **Death.** Die: a Clothes item holding the skin you died in lies 1 m east of the body, next to the rest of
      the death drop, and its label names that skin's type.
30. **Player commands: /dropall, /tooltips** (#91). One client.
    - a. **Surrender.** Hold an item, wear a bag with something in it, a hat and armour, carry inventory items, then
      `/dropall`: the hands-up animation plays, everything lies in a ring around you (the bag still holds its
      contents), the gear tiles are empty, no Clothes item appears and you stay alive. Moving ends the animation.
    - a2. **Ground.** Repeat a. and die (`/kill` or a fall) on a steep hillside and on a building's stairs: every
      item rests on the ground under its own spot, tilted with the slope (none floats, sinks or sticks out of the
      hill), each at its own random heading; the death Clothes item too. Pick one up and drop it with the drop key:
      it lies flat again. On a slope steeper than 45° or in deep water items lie flat, the latter 0.9 m under where
      you were (the fallback).
    - b. **Pickup tip.** Pick up an M9 (or any item with a `_T` text): a green paragraph at the lower left with the
      blue `Type /tooltips to toggle these messages` one blank line below it, gone after 20 s or when the item is
      dropped. An item type without a text shows nothing.
    - c. **Repair tip.** Damage a car below 990 and get in as the driver: the matching "slightly / a bit / broken /
      very broken" text for 20 s; a passenger sees nothing.
    - d. **Toggle.** `/tooltips` says `Tooltips disabled`, pickups then show no tip; reconnect and it is still off
      (`accounts.tooltips`), `/tooltips` again turns it back on.
    - e. `/help` no longer lists `/restartinfo`; `/restartinfo` and `/hudscale` do nothing (not ported).
    - f. **Rest rotation** (#92). `/additem` and drop the types with a non-zero `rotz` (Sign, Torso, Wheel,
      Cupboard, Backpack, MediumBag, LargeBackpack, LocksmithKit, LaserPoint, Door, Cross, RedPanel, Burger, Beanie,
      CaptainsCap, SwatHelmet): each now sits turned by that `rotz` from the old look, nothing sinks into the
      ground, and the look survives `rr items`.
31. **Skills** (#93). One client.
    - a. **Gain.** Repair a damaged car at the bonnet with the right tool: green `+Repair` at the bottom centre for
      5 s. Inventory > `Skills` lists `Repair (Novice)` in yellow; Back returns to the inventory, Close shuts it.
    - b. **Time.** `/setskill Repair 1`, then repair again: the bar runs 1.5 s instead of 3 s and the list shows
      `Repair (Master)` in pink. Workbench and ground construction train the skill named after the result's uname:
      `/setskill <result uname> 1` halves that recipe's hold, and the list shows the item type's name.
    - c. **Persistence.** Reconnect, or `rr character` (flush on stop): the list is unchanged
      (`SELECT skills FROM characters WHERE alive = 1`). Die and respawn: `No skills yet`.
32. **Treatment, infection and drugs** (#94). a-g one client, h two clients (A treats B). `/additem` gives the
    zeroed data (`Pills (Antibiotics)`, `Injector (Empty)`, a Doctor's Bag without charges); the other pills and
    injections come from loot (`/rollloot` near a loot spot, or a supply crate). The holds need **F** physically held
    (the client polls the key); over rcon only the outcomes can be driven (`exports.character:treatPlayer`).
    - a. **Labels.** Loot a Pills, an Injector and a Doctor's Bag: the inventory shows `Pills (LSD)`,
      `Injector (Morphine)`, `Doctor's Bag (2/3, Painkill)` and the like, the same after a pickup and a drop.
    - b. **Bandage.** `/setbleed 0.5`, hold a Dirty Bandage and hold **F**: a 4 s bar, then the yellow chat line
      `Reduced bleedrate from … to …` and the bandage is gone; about one time in three `Your wound has become
      infected!` and Health Status lists `Wound Infect` in red. Letting go of **F** before the bar ends cancels it
      and keeps the bandage. An Antiseptic Bandage cures `Wound Infect` and is spent.
    - c. **Wounds.** Take a few wounds (fall, or B shoots A), then use a Medkit or a Doctor's Bag: `Healed N wounds`
      (1-2 on yourself); the Doctor's Bag also stops the bleed, gives its drug and shows one charge less.
    - d. **Painkiller.** `/sethp 30` (the screen darkens), use `Pills (Painkiller)`: a 1 s bar, `Taken Painkill`,
      hp +10, the darkness gone while Health Status lists `Painkill` in yellow.
    - e. **LSD.** Use `Pills (LSD)`: the sky turns to 22:03 with weather 33 and stays there; after 300 s
      `Lsd has worn off` and the server's weather and clock come back.
    - f. **Food infection.** Eat a `Meat (Uncooked)`: 70 % of its food, and Health Status lists `Food Infect`; the
      camera wobbles now and then (cooking: step 33). `Pills (Antibiotics)` cures it (and the wound infection half
      the time).
    - g. **Persistence.** With an infection and a drug active, reconnect or `rr character`: both are still listed,
      the drug with its time left (`SELECT infection, drugs FROM characters WHERE alive = 1`). Die and respawn:
      neither is listed.
    - h. **Others.** A stands within 1.5 m of B and holds **F** with a Bandage or Medkit: B sees a `Being treated`
      bar and gets the outcome (2-3 wounds from a Medkit). A walking away (0.8 m) or B leaving 2.5 m cancels it.
      Knock B out and inject `Injector (Adrenaline)`: B wakes up; A's injector is now `Injector (Empty)`.
33. **Cooking** (#95). One client; `/additem` a Meat, a Fire Lighter, two Wood Logs, a Barbecue and a Petrol Can.
    - a. **Campfire.** Drop the two Wood Logs, hold the Fire Lighter and hold **F** next to them: a Campfire with
      flames. **F** with empty hands and nothing on it does nothing (a campfire is never picked up). Hold the Meat
      (labelled `Meat (Uncooked)` in the inventory and on the ground) and press **F** at the fire: uncooked food that can
      be cooked goes onto a Campfire or Barbecue within reach (the key hint reads `F Cook`, not `F Eat`), `Food added
      / 1 minute cook time`, the Meat sits on the fire and **F** on it says `Still cooking`. After about a minute the
      label reads `Meat (Cooked)` (data `{"cooked": 1}`); **F** with empty hands at the campfire takes it off. Hold
      the cooked Meat at the fire: the hint reads `F Eat` and **F** eats it (full food, no `Food Infect`); cooked
      food and food that cannot be cooked are always eaten.
    - b. **Barbecue.** Drop the Barbecue (and another item next to it, #97). **F** with the Fire Lighter: `Needs fuel
      from a Petrol Can`. **F** with the Petrol Can: `1L of petrol added / 10 BBQ uses`. Put a Meat on it (`Food
      added`), then **F** with the Fire Lighter: `BBQ Lit / Cook time: 30 seconds`, two small fires under the grill,
      the barbecue cannot be picked up. 30 s later the fires go out and the Meat reads `Meat (Cooked)`; **F** with
      empty hands takes the Meat off, a second **F** picks the barbecue up. **F** with a cooked Meat at the barbecue
      eats it.
    - c. **Persistence.** `rr items` while the Meat cooks: the cook still finishes on time
      (`SELECT data FROM items WHERE type_uname IN ('Campfire', 'Barbecue') AND x IS NOT NULL`). Ten minutes after
      it was lit (two in the rain, weather 8 or 16) the campfire turns into three Burnt Logs.
    - d. **Petrol Can amount.** Refuel a car (or fuel the barbecue) from a full Petrol Can, wait 5 s (the held-data
      flush), drop the can, pick it up and refuel again: the can holds what was left, not 20 L again
      (`SELECT data FROM items WHERE type_uname = 'GasCan' AND holder_kind = 'held'` shows `amount`).

34. **Anticheat (#100).** One level-2+ staff account and one player. First confirm `anticheat` starts without SQL,
    missing-event or ACL errors after `run-local.ps1` applies the schema.
    - a. **Detection fields.** As staff, `/field add smoke 995 995 1005 995 1005 1005 995 1005 0 20`, then
      `/gotopos 1000 1000 5` while on duty. `/field log smoke` lists the staff entry; repeat `/gotopos` after leaving
      the field and confirm each entry is logged once. `/field remove smoke` removes it; `staff_actions` holds a
      `field_add` and a `field_remove` row for the staff account (`/acmds` lists `/field` at level 2).
    - b. **Staff exemptions.** While on duty, use `/gotopos` across the map and confirm no anticheat teleport
      rollback; go off duty and walk normally with no alerts.
    - c. **Focus timeout.** With `player.max_tab_out_time` set to 60, move a non-staff player out of MTA focus for
      more than 60 seconds and confirm the server logs and disconnects that player; restore focus before the limit
      and confirm the timer clears.
    - d. **Ping policy.** On a test client with controllable network latency, hold ping above the configured limit
      for 10 seconds and confirm the kick. Confirm short spikes do not kick, the 10-second join grace applies, and
      staff on duty are exempt. Do not change a production ping limit to run this check.
    - e. **Native movement and event guards.** Confirm the deployed server build supports `onPlayerTeleport`,
      `onPlayerTriggerEventThreshold`, and `onPlayerTriggerInvalidEvent`; inspect server logs for a safe test event
      threshold breach in a private test server. No production cheat tools are needed for this smoke step.

35. **Discord reports of 2026-10-26** (#116, #117, #118, #119, #120, #121, #122, #123). One client.
    - a. **Drinking (#122, #118).** `/additem Bottle` and `/additem GasCan` give empty containers (`Bottle (Empty)`
      in the inventory, **F** says `It is empty`); a looted Bottle, Can Drink, Milk Carton or Apple Juice reads
      `(Water 0.4/0.50)`-style with a random level, and a looted Petrol Can `(Petrol 13.2/20.00)` rather than a
      fixed amount. Hold **F** with a filled Bottle: the drinking animation and a 1 s hold bar repeat, the label
      drops 0.2 L per sip, the hunger bar rises per sip (Milk 2.1, Water 0.5), letting go stops it, and the last sip
      ends with `It is empty`. Drinking from a Petrol Can lowers food (-8 per sip, as upstream).
    - b. **Carry items and vehicles (#120).** Holding a `Wheel` or `SmallBox`, try to enter any vehicle: entry is
      refused with `Put that down before getting in`; drop it and enter normally.
    - c. **Pickup and drop animations (#121).** Pick up a Bandage: a short bend (BOM_Plant_In); drop it: the same.
      Pick up a Wheel: short bend animation, held in hand without locking movement; player can walk, run, sprint
      and jump freely while holding it; dropping it plays the bend animation and places it on the ground.
    - d. **Weather cycle (#117).** Weather re-evaluates every minute once 10 minutes have passed since the last change
      (10% roll), and picks a different weather rather than repeating the same rain.
    - e. **Crafting combine (#119).** Hold a `Fusebox` and open inventory with a `Battery`: the `Combine` action produces
      a `PowerSupply` in hands and updates inventory slots.
    - f. **Holster (#123).** Holding a holsterable weapon (`M9Pistol`, `DesertEagle`, `AK47Rifle`), press **Y** to
      holster it with its holster animation (300 ms for thigh pistols, 800 ms for back rifles); hands become empty.
      With empty hands and a holstered weapon, HUD displays `Y Draw weapon` and pressing **Y** equips it.
36. **Tweaking a built item** (#133, upstream `item-tweak.pwn`). One client; `/additem CrateDoor`, `/additem Screwdriver`,
    `/additem Hammer`, two `/additem WoodLog`.
    - a. Drop the Crate Door, hold the Screwdriver and press **F** on it: after the build hold, `Defence built` and a pad
      of eight buttons appears at the right of the screen (`L`, `R`, `^`, `<`, `>`, `v`, `Edit: [LALT]`, `Done`), a
      yellow arrow lies on the door pointing at its front (the side a Crowbar cannot take it down from), and the help
      tip says to move away from the item and press LALT for the mouse (if `/tooltips` is on).
    - b. Press LALT: the mouse appears and the long button reads `Move`. Click `^` while standing next to the door:
      `Cannot move item with players nearby`. Click `Move` (mouse gone), walk 3 m away, LALT, click `^` a few times
      and hold it: the door steps 5 cm forward per click and keeps stepping while the button is held; `<` and `>`
      step sideways, `L` and `R` turn it 2 degrees and the arrow turns with it.
    - c. Keep stepping one way: after about 1.5 m, `Too far from original build position` and the door stays.
    - d. Walk to within 2 m of the door and click: `Cannot move item with players nearby`. A second player standing
      next to it is told `You are blocking an item from being built, please stand back`.
    - e. Click `Done` (or press Enter with the mouse up): `Tweaking finished`, pad and arrow gone, the door stays
      where it was nudged (`rr items` keeps it there). **F** did nothing while the pad was up; **I**, **N** and
      **Y** end the tweak before doing their own thing.
    - f. Drop the two Wood Logs, hold the Hammer and press **F**: the `Barricade` is built and the pad opens without
      an arrow; a Campfire (Fire Lighter on the logs) or a Plot Pole opens no pad, as upstream.
37. **Small item behaviours** (#136, upstream `note`, `sign`, `dice`, `locator`, `stungun`, `molotov.pwn`). One client,
    two for the stun gun; `/additem Note`, `Sign`, `Dice`, `Locator`, `MobilePhone`, `StunGun`, `Battery`, `GasCan`,
    `MolotovEmpty`.
    - a. **Note.** Hold the Note, **F** (hud: `F Read note`): the input dialog `Write a message onto the note:`; `Done`
      with a message stores it (`Note (first 8 letters(...))` in hand, in the inventory and on the ground); **F** again
      shows the message with `Close` / `Tear`; `Tear` destroys it. `Use` from the inventory does the same. A written
      note is never rewritten, and colour codes or line breaks in the text are dropped.
    - b. **Sign.** Drop the Sign, empty hands, tap **F**: `Enter the text to display below ...`; `KEEP\OUT` draws
      `KEEP` over `OUT` above the sign, readable from 25 m and after `rr items`; hold **F** 500 ms to pick it up.
    - c. **Dice.** Drop the Dice: they land 40 cm ahead on a random face (`UPDATE` seen in `items.data` as
      `{"face": n}`), the object lies on that face after `rr items`.
    - d. **Locator.** Drop the Mobile Phone, hold the Locator, **F** on the phone: `Locator synced, you can now locate
      the phone.`; walk off, **F** with the Locator: `Distance: 12.345`; pick the phone up with the other client or put
      it in a safebox: the distance follows it; in a trunk: `Unable to trace the mobile phone`.
    - e. **Stun gun.** Drop the Battery, hold the Stun Gun, **F** on it: `Stun Gun Charged`, the battery is gone and the
      label reads `Stun Gun (Charged)`. Punch the second client: they are knocked out 60 s and the label reads
      `(Uncharged)`; punch again: `Out of charge`, no wound either time.
    - f. **Molotov.** Drop the Empty Molotov, hold a Petrol Can with petrol (fuel pump), **F** on the bottle: `Fuel
      poured in bottle`, the can loses 0.5 L and a Molotov lies there (`/additem GasCan`, empty: `Petrol can empty`;
      a Bottle of water in hand instead: nothing, it is not a can).
38. **Headgear pop, the shield and HerpDerp** (#137, upstream `char/headgear-pop.pwn`, `item/shield.pwn`,
    `item/herpderp.pwn`). Two clients A and B; `/additem Shield`, `/additem HerpDerp`, a hat (`/additem SheriffHat`),
    a mask (`/additem ZorroMask`), any pistol.
    - a. **Headgear pop.** A wears the hat and the mask; B shoots A in the head: both fall to the ground at A's feet
      (the gear tiles empty, A's skin shows its hair again) and can be picked up; a body shot leaves them on.
    - b. **Shield in hand.** A holds the Shield facing B; B shoots A's torso from the front: no wound, no bar; from
      A's side or back: the wound lands; a headshot lands from any side; B crouching and shooting A's legs: blocked,
      standing: lands.
    - c. **Shield on the back.** A holsters it (**Y**, 800 ms); B shoots A from behind: blocked; from the front: lands.
    - d. **Placing it.** A holds the Shield and presses **F** (hud: `F Place shield`): the planting bend, then the
      shield stands on its edge half a metre ahead facing A, still standing after `rr items`; pick it up and drop it
      with **N**: it lies flat as any item.
    - e. **HerpDerp.** **F** with it in hand: a random tattoo-parlour or gang-sign animation each press.


39. **Travel stats and Endurance** (#138, upstream `char/travel-stats.pwn`). One client.
    - a. `/mstats` right after spawning: every `DIST_*` 0.0, `TIME_*` 0, `JUMPS: 0`. Sprint for a while, swim,
      drive, crouch-walk: the matching lines grow (one second of sprinting is about 6.5 m, the others sort by speed),
      and a vehicle trip shows under `DRIVING` only.
    - b. Sprint 500 m in one go (a long straight road): `Endurance` appears in the inventory's Skills list; sprint
      another 500 m within 10 s of that: no second gain until 10 s have passed; swim 200 m: a gain.
    - c. Jump ten times on foot: a gain on the tenth; jumps in a vehicle or while knocked out count nothing.
    - d. With `Endurance` at Master (`/lua return exports.character:setSkill(getPlayerFromName("A"), "Endurance",
      0.95)`), a jump out of a sprint carries about twice as far as a standing jump; a standing jump is unchanged.
    - e. Relog: the counters start again at 0 (session only), the skill stays.
40. **Bodies** (#139, upstream `item/torso.pwn`, `death.pwn` CreateGravestone). Two clients A and B; `/additem Knife`.
    - a. B shoots A dead: next to A's dropped items a body (`Torso`, the dead-torso prop) lies where A fell. A relogs
      and spawns elsewhere; the body stays (`rr items` too).
    - b. Empty hands, tap **F** on the body: a message box titled `A` reading `They died of blood loss caused by what
      looks like bullets.`; a drowning reads `They drowned.`, a fall `Most bones are broken, ...`, starving `They
      starved to death.`, a fist kill `They were beaten to death.`.
    - c. Hold the Knife, **F** on the body: `Harvesting` bar for 3 s with the planting loop, then one `Meat (Uncooked)`
      lies on the body. **F** again: `The body has already been harvested of the edible (tasty) parts`. Walking off
      during the hold takes nothing.
    - d. `UPDATE items SET data = JSON_SET(data, '$.at', 0) WHERE type_uname = 'Torso'` then `rr items`, Knife + **F**:
      `The body has decomposed too much to harvest`.
    - e. Hold **F** 500 ms with empty hands: the body is picked up (carried two-handed) and can be dropped elsewhere;
      a tap on the dropped body still investigates it.
41. **Sitting, hands up and the aim shout** (#140, upstream `char/animations.pwn`, `char/aim-shout.pwn`). Two clients.
    - a. Standing still, hold crouch: after 0.8 s A sits down (PARKSIT_M_IN, then the loop); crouch, sprint or
      jump gets A up (PARKSIT_M_OUT). A quick tap of crouch only crouches. Walking or in a vehicle: no sit.
    - b. Sprint and crouch together while standing: hands up and frozen; the same again lowers them. Knocked out
      or cuffed: nothing.
    - c. `/aimshout` alone: the usage line; `/aimshout Hands up!`: `AimShout set to 'Hands up!'`. Aim at B and
      press look-behind: `A: Hands up!` in local chat for both, not more than once every 750 ms however fast the
      keys are hit; in a car, look-behind with the horn does the same. Relog: the line is forgotten (session only).
    - d. A sits, B knocks A out (charged Stun Gun): the sit ends with the knockout; after `rr character` nobody
      is left sitting.
42. **Fishing** (#141, upstream `item/fishingrod.pwn`). One client at a shore (the Santa Maria pier, Palomino Creek
    lake); `/additem FishRod`.
    - a. Hold the rod on dry land, hold **F**: a `Casting` bar fills (10 s = 100 m), let go: `You need to be closer
      to the water`. At the water's edge, hold **F** for 2 s and let go: `Fishing...` / `Press [F] to cancel`.
    - b. Wait: within 30 to 120 s either `Unlucky!` (about 7 in 10 without the skill) or `The line is tugging...`
      with the sword-block animation, and 2 s later (100 ms per metre of line) a `Raw Fish (Uncooked)` at the feet;
      `Fishing` appears in the Skills list after the first catch.
    - c. With the line out, **F** cancels; dropping the rod (**N**) cancels too; no second cast while one is out.
    - d. `/lua return exports.character:setSkill(getPlayerFromName("A"), "Fishing", 0.95)`: the waits are about
      half as long and the catches about twice as frequent.
43. **Gardening** (#142, upstream `item/plantpot.pwn`, `seedbag.pwn`). One client; `/additem PlantPot`, `/additem
    SeedBag`, `/additem Knife`, a Bottle filled with water.
    - a. A looted or `/additem` bag reads `Seeds (n, Kind)` with n from 0 to 4 (`Seeds (Empty)` at 0; `/additem`
      a few until one has seeds), the same after a relog.
    - b. Drop the pot; hold the Seeds, **F** on the pot: `Added seeds to plant pot`, the bag one seed down. Tap
      **F** on the pot with empty hands: `Plant Pot` box `Active: yes / Seed type: Tomato / Water: 0 / Growth: 0/4`.
    - c. Hold the water bottle, **F** on the pot: `Added 1 water to plant pot`, the bottle 0.1 L down; an empty
      bottle: `Bottle is empty`; a bottle of milk: `Bottle does not contain water`.
    - d. Growth: `UPDATE items SET data = JSON_SET(data, '$.pot.growth', 2) WHERE type_uname = 'PlantPot'` then
      `rr items`: a sprout stands on the pot; at `growth` 4 (Tomato) the tomato plant. Or wait: every 10 minutes a
      watered pot grows one and drinks one water; dry, it withers one and empties at 0.
    - e. Knife, **F** on the grown pot: `Plant harvested`, a Tomato on the pot, the pot empty; on a young plant:
      `The plant has not fully grown yet`; on an empty pot: `Pot doesn't contain an active plant`.
    - f. Hold **F** 500 ms with empty hands: the pot is picked up; the plant is gone with it and back when dropped.
44. **The Locker's door and the Love Box** (#143, upstream `item/locker.pwn`, `heartshapedbox.pwn`). Two clients.
    - a. `/additem Locker`, drop it: the closed locker (SA-MP 11729). A opens it with **F**: both clients see the
      open twin (11730); A closes the list, walks more than 4 m off or opens something else: closed again within
      half a second. A and B both open it; one leaves: still open until the other leaves too.
      Port deviation: it opens only from the door side. From behind or from the side (more than 60 degrees off the
      door's front), or in front but looking away (more than 60 degrees off the locker), **F** refuses with
      `Open the locker from the front, facing its door` and it stays closed; from the front facing it, it opens.
      Check at a few headings of the dropped locker (drop it facing different ways). A player who already has it
      open keeps it open when pressing **F** again.
    - b. Find a looted Heart Shaped Box (a `HeartShapedBox` row with a `loot_spawn_id`, or `rr loot` near a
      spawn that rolls one): opened on the ground it holds a Dildo, Flowers, an Antiseptic Bandage and a Zorro
      Mask; an `/additem HeartShapedBox` box is empty.
    - c. The fixed box (upstream `CreateItem(item_HeartShapedBox, 2912.3301, 2910.2800, 29.7780)`): after a start
      the log has `fixed HeartShapedBox at 2912.33, 2910.28, 29.778: created` (first start) and a `HeartShapedBox`
      row lies there with no loot spawn; opened it is empty. Restart `items`: no second box is added. Carry it off,
      restart `items`: a new one stands there. The spot is open sea in the stock map, so fly there to look.

45. **Falls, drowning, rams and explosions** (#144, upstream `weapon/damage-world.pwn`, `damage-vehicle.pwn`,
    `damage-explosive.pwn`). Two clients A and B.
    - a. A jumps off a roof two storeys up: most landings print nothing (GTA's fall damage is cancelled, the wound
      is a roll); a hard one shows `Wounded: left leg` or `right leg` with a small hp loss and bleeding, sometimes
      a knockout. A step off a kerb never wounds.
    - b. A swims under water until out of breath: each drowning tick knocks A out for 1.5 to 3 s (`KO_shot_stom`,
      the countdown bar) and takes up to 10 hp; surfacing ends it.
      Swim down from the surface: a ped teleported under water stands on the seabed and never drowns.
    - c. A drives into B at speed: B reads `Wounded: torso` (or a leg) with bleed growing with A's speed; past
      55 km/h B is often knocked out for `1 + speed / 20` seconds on top. B's combat window opens (watch red) and
      a death gives A the kill (`[KILL]` in the log, the body reads "They bled to death."). At walking pace no
      wound at all; the server log reads `A rammed B at N km/h`.
    - d. A `/additem TntTimebomb`, plants it next to B and steps back: B is wounded (`torso` or a leg, bleeding)
      and, close to the blast, knocked out. A standing in a campfire loses a tenth of GTA's burn damage.
      The blast reaches the client as weapon 16 or 19 (no creator), not 51; a flat `-20 hp` with no bleeding
      means it took the fallback.
    - e. Give A duty (`/duty`): none of a to d touches A.
46. **Machines** (#145, upstream `itemtype/machine.pwn`, `item/scrap-machine.pwn`, `refine-machine.pwn`,
    `water-purifier.pwn`). One client; the `machine_finish` procedure must be in the database (`sqltool apply`).
    - a. `/additem ScrapMachine` and drop it (or build one: Canister, Motor, Fluctuator, Power Supply and a
      Screwdriver). The key list reads `F Access machine` and `F (Hold) Machine menu`. A tap of **F** opens an
      empty 12-slot "Scrap Machine" container; put a Bucket and a Barbecue in. Hold **F** with empty hands: the
      Start / Cancel box reads `Fuel amount: 0.0`; Start says there is not enough fuel (3.5 per item).
    - b. `/additem GasCan`, hold **F** at the machine: `Refuelling...` with a bar; let go after a second, the
      box now shows the fuel moved (1.1 per 100 ms) and the can's label has lost the same amount. Hold until the
      bar ends: the tank reads 100.0.
    - c. Start: `Cook time: 3 minutes N seconds`, smoke rises from the machine on every client, a tap of **F**
      says how long is left, and the log reads `[MACHINE] ScrapMachine N started`. When it ends the smoke stops,
      the log reads `2 items in, 8 out`, and the container holds 8 Scrap Metal; the fuel dropped by 7.0.
      `rr items` mid-cook: the cook finishes on time after the restart.
    - d. `/additem RefineMachine`: a Wrench put in is refused with `This machine only accepts Scrap Metal`; two
      Scrap Metal cook into two Refined Metal. `/additem WaterMachine`: only a Bottle of sea water goes in (fill
      one at the shore); it comes out as the same amount of Water.
    - e. With a Crowbar in hand the key list reads only `F Deconstruct`; a 25 s hold takes the machine down and its
      four parts drop (whatever was inside goes with it). A Screwdriver over the four parts builds one in 30 s.
