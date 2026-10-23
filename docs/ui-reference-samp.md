# UI reference: what Scavenge & Survive looked like on SA-MP, and how to get there on MTA

Research note, 2026-10-22. Two sources were cross-checked for every element:

- **Upstream code** (`../ScavengeSurvive`, the 2020 MPL release): every `CreatePlayerTextDraw`,
  `CreatePlayerProgressBar`, dialog and label definition, quoted with its exact numbers.
- **Southclaws' YouTube footage** (18 videos, 2013–2016, downloaded at 720p and sampled one frame every
  4 s; 2 300 frames read as contact sheets, key frames inspected at full size and colour-sampled with
  Pillow). The 2015 videos (Tutorial #1/#2, Gameplay #1–#5, Loot Talk #1–#3) match the 2020 code
  one-for-one except where noted. The 2013 videos (Forts update, Alpha Test, Final Hours) show an older
  HUD and are listed only for history.

Frame references below are `videoId @ m:ss`. The frames themselves are not committed (they are stills from
someone else's videos); regenerate them with `yt-dlp` + `ffmpeg -vf fps=1/4` if needed.

| Video | Id | Date | What it shows |
| --- | --- | --- | --- |
| THE BASICS – Tutorial #1 | `_umRf_NqftE` | 2015-02-22 | vehicle panel, trunk, fuel, repair, inventory, help tips |
| Weapons and Health – Tutorial #2 | `n_YLXnicEdc` | 2015-07-24 | wounds, bandages, body panel, ammo text, tool tips, combine |
| SUPPLY RAID – Gameplay #1 | `AEp1SnYke4U` | 2015-05 | full inventory screen with container dialog, gear tiles, body panel |
| AIR RECON – Gameplay #2 | `3-2QwIoPOco` | 2015 | helicopter HUD, vehicle panel, trunk |
| AMBUSH! – Gameplay #3 | `eX2b6aGKOyY` | 2015 | vehicle panel, knockout |
| GREED! – Gameplay #4 | `sK5Er8lx9mM` | 2015 | hold-action bar (fuel can), wheel dialog |
| Coward Bandits! – Gameplay #5 | `dcnFvKxCe2Q` | 2015-05-01 | container option dialog, keypad prompt, handcuffs, "Trunk locked" |
| KARMA is a BITCH | `p52g-vd0syA` | 2015-06-06 | death screen, server-restart countdown |
| Loot Talk #1 / #2 / #3 | `Guaq-EBtf5I` / `OEGmck6HIQw` / `CIYCEcp6FjU` | 2015 | trunk dialog (29/42), supply drop, radio |
| Taser Battle, Final Hours, Forts, Defences, Minigames, Don't Get Wet | `ph6zewdKM2o` `sx9NKFirNbY` `l1sciOHrK2s` `CfvK07aVeDc` `aPFtdQVKNUU` `GSynPe4Ycko` | 2013 | old HUD (round watch, no key list) |

## 1. Canvas, scaling and fonts (the rules every element shares)

**Canvas.** SA-MP textdraws live on a 640×480 virtual canvas stretched to the window. On 16:9 that stretches
everything 1.33× horizontally, which is why upstream ships three `/hudscale` profiles
(`core/player/widescreen.pwn`: Normal, HudScaleFix, WidescreenFix) that squash the watch and hunger bar back.
On MTA we control the transform, so the port should use **one uniform scale `s = screenH / 480`** and
**anchor** each element to the edge it sits on (left/right/centre, top/bottom). That reproduces the 4:3 look
without the stretch and makes the three profiles unnecessary. Keep upstream's numbers as the source of truth
and convert at draw time: `px = 640-unit x × s` from the left anchor, `screenW − (640 − x) × s` from the right.

**Letter size → pixels** (measured on the 1280×720 footage, so 1 unit = 1.5 px):

| Upstream letter size (font) | Observed | In 640×480 units |
| --- | --- | --- |
| 0.30 / 1.50 (font 1, key list, tips, action text) | line pitch 22 px, cap height 12 px, "Open inventory" 160 px wide | pitch 14.7, caps 8, ≈5.7 per char |
| 0.25 / 1.60 (font 2, vehicle rows) | line pitch 22.5 px (rows at y 341,356,…,415) | pitch 15 |
| 0.50 / 2.00 (font 2, watch time) | digits 24 px tall | 16 |
| 0.20 / 1.00 (font 1, body labels, spectate) | caps 8 px | 5.3 |
| 0.15 / 1.00 (font 2, gear tile captions) | caps 7 px, all caps | 4.7 |

Rule of thumb: **line pitch ≈ letterY × 9.8 units**; **average glyph width ≈ letterX × 19 units**.
`dxDrawText` scale 1 line heights and glyph widths differ from GTA's bitmap fonts (`default-bold` is `15 px` tall and
narrower than font 1; `bankgothic` is `22 px` tall and wider than font 2). `ui/shared/logic/canvas.lua` corrects both
with per-font `DX_LINE_PX` (`default-bold = 15`, `bankgothic = 22`), `Y_FACTOR` (`bankgothic = 0.85`) and `X_FACTOR`
(`default-bold = 1.5`, `bankgothic = 0.95` at the native `1:4` letter aspect `0.50/2.00`), tuned pixel-by-pixel against
1080p screenshots.

**Fonts.** SA-MP textdraw fonts map to MTA like this:

| SA-MP font | Where upstream uses it | MTA |
| --- | --- | --- |
| 0 (Diploma) | nowhere | `"diploma"` built-in |
| 1 (GTA subtitle font: bold rounded sans) | key list, tips, action text, dialogs-style boxes, death screen, keypad keys | **No exact built-in.** `"default-bold"` (Tahoma Bold) is the nearest stock font and is what `ui`/`hud` use now. For true 1:1 ship a TTF via `dxCreateFont` or render GTA's own glyph page (`models/fonts.txd` → `font1`) as a bitmap font. MTA 1.6 exposes the real font only for stock HUD components (`setPlayerHudComponentProperty(…, "fontStyle", "subtitles")`), not for `dxDrawText`. |
| 2 (GTA "gothic" HUD font, Bank Gothic) | watch, vehicle panel, gear captions, keypad display | `"bankgothic"` built-in: this one is 1:1 |
| 3 (Pricedown) | nowhere | `"pricedown"` built-in |
| 4 (TXD sprite) | watch ellipse `LD_POOL:ball`, radio knobs `LD_DRV:nawtxt`, tweak arrows | `dxDrawImage` on a PNG we ship, or `dxDrawCircle(x, y, r, 0, 360, colour, colour, 64, ratio)` for the watch ellipse (no asset needed) |
| 5 (model preview) | six gear tiles, body panel skin | **MTA has no model-preview widget.** `dxDrawModel3D` (1.6) draws in world space only and the wiki states it cannot target a render target. Use a pre-rendered icon atlas (one PNG per item model at the same rotation `-45, 0, -45`, zoom 1) generated once in-engine by the `dev` resource with `dxCreateScreenSource` + `dxGetTexturePixels`; same for the ~14 civilian skins used by the body panel. |

**Outline and shadow.** Every upstream text has `SetOutline(1)` (1-unit black outline) or `SetShadow(1)`
(1-unit black drop shadow). `dxDrawText` has neither; draw the text once per offset in black
(4 offsets for outline, 1 for shadow) then in colour. Cost is negligible for a HUD of ~30 strings.

**Colour codes.** `~y~` in the key list is GTA's HUD yellow (sampled ≈ `#E8E890` on highlights), `~r~` red,
`~b~` blue, `~w~` white. In chat upstream uses its own palette (`ScavengeSurvive.pwn`):
`YELLOW FFFF00`, `RED E85454`, `GREEN 33AA33`, `BLUE 33CCFF`, `ORANGE FFAA00`, `GREY AFAFAF`, `WHITE FFFFFF`.
MTA: `outputChatBox(text, r, g, b, true)` with `#RRGGBB` inline codes, same values.

**Box colours** (`PlayerTextDrawBoxColor`, RGBA): `255` = black opaque, `128` = black 50 %, `100` = black 39 %,
`85` = black 33 %, `80` = black 31 %, `0x87878787` = grey 53 %, `0x20202080` = dark grey 50 %.

**Clickable textdraws** (`PlayerTextDrawSetSelectable` + `SelectTextDraw(hoverColour)`): the hit box is the
`TextSize` rectangle and the hover recolours the text. MTA: `showCursor(true)`, hit-test in `onClientClick`,
tint on `onClientCursorMove`. Hover colours used: keypad `0xFF0000FF`, radio `0xFFFFFF88`.

**Key names.** Upstream prints `~k~~VEHICLE_ENTER_EXIT~` etc. and GTA substitutes the bound key. MTA has no
`~k~`; resolve the name ourselves: `getKeyBoundToCommand("interact")` for our command binds and
`getBoundKeys("enter_exit")` for GTA controls, upper-cased. Upstream's mapping (`ScavengeSurvive.pwn` 272–280):

| Upstream macro | GTA control (default key) | Our command bind |
| --- | --- | --- |
| `KEYTEXT_INTERACT` | `enter_exit` (F) | `interact` |
| `KEYTEXT_RELOAD` | `PED_ANSWER_PHONE` (R; not an MTA control name) | `reload` |
| `KEYTEXT_PUT_AWAY` / `KEYTEXT_ENGINE` | `conversation_yes` (Y) | `putaway` |
| `KEYTEXT_DROP_ITEM` / `KEYTEXT_LIGHTS` | `conversation_no` (N) | `dropitem` |
| `KEYTEXT_INVENTORY` | `group_control_back` (H) | `inventory` |
| `KEYTEXT_DOORS` | `sub_mission` (2) | — |
| `KEYTEXT_RADIO` | literal "R" | — |

## 2. Element-by-element reference

Positions are upstream 640×480 units unless marked px. "Seen" is the footage that confirms the look.

### 2.1 Always-on HUD

| Element | Upstream definition | Look (footage) | MTA recipe |
| --- | --- | --- | --- |
| **Stock GTA HUD** | SA-MP default: weapon icon + ammo, red health bar, white armour bar when wearing armour, `$00000000` (money is never used), **radar and clock hidden**, no wanted stars | `AEp1SnYke4U @ 3:32`, `_umRf_NqftE @ 3:08` (armour bar) | `setPlayerHudComponentVisible`: hide `radar`, `clock`, `wanted`, `breath`; keep `weapon`, `ammo`, `health`, `armour`. Money: hide (`money` false) — showing eight zeros was a SA-MP limitation, not a design choice; note the deviation. 1.6 `setPlayerHudComponentProperty` can recolour/reposition the bars if we ever need to. |
| **Ammo text** `core/weapon/weapon.pwn:77` | `520.41, 62.65`, centred, font 1, `0.278/1.372`, white, outline 1. String `"%d/%d"` (mag / reserve). | Drawn **under the weapon icon, replacing GTA's own ammo counter**: "4/0", "18/30", "30/30" (`n_YLXnicEdc @ 6:16`) | Hide stock `ammo`. At 1080p MTA's stock weapon icon sits at `1485..1637 × 25..194 px` (`446.7..514.2 × 11.1..86.2` right-anchored units), so `hud/shared/logic/bars.lua` places the counter at `480.4, 75.5` right-anchored. |
| **Hunger bar** `core/char/food.pwn:134` (progress2) | `548, 36`, `62 × 3.2`, colour `0x1FF81FFF` (31,248,31), max 100, direction RIGHT. WidescreenFix profile: x+35, width×0.66. | **2015 footage shows it vertical**: 5 px wide, 140 px tall at x≈1230/1280, black track, green fill from the bottom (`AEp1SnYke4U @ 0:28`). The 2020 code moved it to a short horizontal bar top-right. Either is "upstream"; the vertical one is what players remember. | progress2 bar = three rectangles: black track (alpha of colour), fill at half alpha, value box full colour, 1.2/1.0-unit padding. `dxDrawRectangle` ×3. MTA draws the stock health bar lower and wider (`517.8..593.8 × 98.7` right-anchored units at 1080p), so `hud/shared/logic/bars.lua` places the hunger bar 20 units above it at `517.8, 78.7` (`76 × 3.2`). |
| **Key actions list** `core/ui/key-actions.pwn` | `618, 120`, alignment 3 (right), font 1, `0.30/1.50`, white, outline 1. One line per action: `"~y~KEY ~w~Use~n~"`. Hidden while inventory/container open, knocked out, HUD off, not spawned. | Right column under the HUD: "Y Holster weapon / R Reload / N (Hold) Unload / N Drop item / H Open inventory"; in a vehicle "Y Toggle engine / N Toggle lights / 2 Toggle locks / R Open radio"; near a trunk "F Open Trunk"; next to a cuffed player "F Remove handcuffs" (`AEp1SnYke4U @ 3:32`, `dcnFvKxCe2Q @ 9:12`, `@ 9:40`). Keys yellow, verbs white, 22 px pitch at 720p. | Right-anchored `dxDrawText` block, one line per action, yellow key + white verb, outline. The full decision table (which lines for which held item / area / state) is `_UpdateKeyActions` in `key-actions.pwn` and should be ported verbatim into `hud`. |
| **Watch** `core/ui/watch.pwn` | Background sprite `LD_POOL:ball` centred at `87, 338`, size `108 × 89` (Normal profile: x−1, sx 0.94, bg offset −52.9·sx), black. Texts centred at x 87: bearing `"%.0f DEG"` y 358 font 2 `0.30/1.50`; time `"%02d:%02d"` y 372 font 2 `0.50/2.00`; frequency `"%.2f"` y 391 font 2 `0.30/1.50`; all white, outline 1; **all three turn `RED` while the player is combat-logging** (attacked in the last N seconds). Updated every 1 s; bearing = `360 − facing` (vehicle angle when driving). Shown from spawn. | Black ellipse bottom-left with three Bank Gothic lines: "144 DEG / 23:25 / 107.00" (`AEp1SnYke4U @ 3:32`). The 2013 HUD had the same ellipse with only a clock. | `dxDrawCircle(cx, cy, r, 0, 360, black, black, 64, 89/108)` for the ellipse, three `bankgothic` strings. Red tint when `combatLogging` flag is set by the server. Issue #49. |
| **Vehicle panel** `core/vehicle/vehicle.pwn:102–147` | Right-aligned at x 620 (name 621), font 2, outline 1, white: `DOR` y 341, `ENG` 356, `DMG` 371 (`0.25/1.60`, created `RED`, recoloured: `VEHICLE_UI_ACTIVE`/`INACTIVE` for doors+engine, `VEHICLE_HEALTH_CHUNK_1..4_COLOUR` for damage), fuel `"%.2fL/%.2f"` 386, speed `"%dKM/H"` 401, name 415 (`0.35/1.80`). Shown while driving. | Bottom-right stack "DOR (red, locked) / ENG (yellow) / DMG (yellow) / 16.41L/58.79 / 24KM/H / SENTINEL" (`dcnFvKxCe2Q @ 9:12`, `_umRf_NqftE @ 3:08`). Tutorial #1 explains them: DOR lock state, ENG on/off, DMG wrecked/drivable/working/perfect. | Six right-anchored `bankgothic` strings; fuel/speed from the vehicle element each frame, lock/engine/damage from element data. |
| **Hold-action bar** `core/ui/hold-action.pwn` (progress2) | `291, 345`, `57.5 × 5.19`, `GREY 0xAFAFAFFF`, max = duration ms, +100 every 100 ms; `OnHoldActionFinish` when full. Also `KnockoutBar` `291, 315` RED (knockout countdown) and `OverheatBar` `220, 380`, `200 × 20`, RED, max 30. | Tiny grey bar just below screen centre while filling a fuel can (`sK5Er8lx9mM @ 0:44`), repairing, bandaging, eating (3 200 ms), cuffing (3 000 ms). | Same three-rectangle bar at (291,345)·s. **Current `ui/client/progress.lua` draws a 260 px red bar with a label at 72 % height: wrong size, colour, position.** |
| **Action text** (`action-text` include, used ~60× upstream) | `320, y` centred, font 1, `0.30/1.50`, white, outline 1, wrap width 200. One slot per player; `ShowActionText(p, text, ms)` replaces the previous text, `ms = 0` means sticky until hidden. | Single white line at y≈351 units (527 px): "Equipped", "Trunk locked", "Item added to bag", "Extra 2 slots required", "You don't have the right tool", "Press F to pick up", "Press N to give item", "Transferred 30 rounds from ammo tin to weapon", "Wounded: Firearm / Severity: Minor" (two lines) (`AEp1SnYke4U @ 3:32`, `dcnFvKxCe2Q @ 9:40`, `@ 10:00`). | One centred string with timer. **Current `ui/client/toast.lua` stacks up to four lines at 82 % height for 3 s: replace with the single replace-in-place slot.** |
| **Help tips** `core/ui/tool-tip.pwn` | `150, 350`, font 1, `0.30/1.50`, colour `0x00FF00FF` green, outline 1, box colour 0 (none), width to 520. Shown 20 s on pickup (`<ITEM>_T` language key + `"~n~~n~~b~Type /tooltips to toggle these messages"`), on entering a damaged vehicle, in the tutorial. | Green two-line paragraph bottom-centre plus a blue line (`n_YLXnicEdc @ 5:00–7:00`). | Green `dxDrawText` with word wrap at 370 units width, 20 s timer, per-player toggle persisted. Not ported yet. |
| **Brightness overlay** `core/player/brightness.pwn` | Full-screen box (`0,0`, 640 wide, 50 lines) whose alpha tracks `BrightnessLevel`: darkens as HP drops below 40 (`(40 − hp) × 4.4`), fades back 4/100 ms. | Screen darkens when badly hurt. | `dxDrawRectangle(0,0,sw,sh, tocolor(0,0,0,level))` from the HP pushed by `characterStatsSynced`. Not ported. |
| **Version line** `core/ui/status.pwn` | `632, 2` right, font 1, `0.24/1.00`, white, outline: `"Build N - scavengesurvive.com - site ~n~ Tick: N Ping: N Pkt Loss: %.2f"`, red when tick < 150. | Tiny top-right text ("SouthclawJK.wordpress.com" in the videos). | Optional; `dxDrawText` with `getPlayerPing`/`getNetworkStats`. |
| **Skill notification** `core/char/skills.pwn:60` | `320, 430` centred, font 1, `0.40/1.40`, green `0x00FF00FF`, outline: "+Fishing". | — | Centred green text near the bottom. Defer with skills. |
| **Whitelist countdown** `core/player/whitelist.pwn:56` | `430, 40` centred, font 1, `0.20/1.00`, white, outline: "Not whitelisted~n~Time remaining: 00:00". | — | Defer. |
| **Restart countdown** | Chat only in 2020 code (`level4.pwn`). | 2015 footage shows a textdraw top-centre "Server Restarting In: 59:18" (`p52g-vd0syA @ 0:30–8:00`). | Optional `dxDrawText` top-centre when a restart is scheduled. |

### 2.2 Inventory screen (H)

Opening the inventory shows three things at once (`AEp1SnYke4U @ 0:28`, `dcnFvKxCe2Q @ 9:40`,
`Guaq-EBtf5I @ 2:24`): the **SA-MP list dialog** in the middle, the **body panel** on the left, the
**six gear tiles** on the right. The key-actions list is hidden; the stock HUD, watch and chat stay.

**Dialog (y_dialog / `inventory-dialog.inc`, `container-dialog.inc`)** — `DIALOG_STYLE_LIST`:

- Title `"Inventory (%d/%d)"` (used/size) or `"<Container> (%d/%d)"` (e.g. "Supply Crate (24/48)",
  "Police Car trunk (29/42)", "Travel Rucksack (6/13)").
- Rows: `"[%02d]%s"` = item size in brackets then `GetItemName` ("[03]Daypack", "[04]MP5 (30/30, 9mm, Hollow
  Point)", "[01]Hotdog (Cooked, 50%)", "[01]Key (Sentinel)"), then one `"<Empty>"` per free slot, then the
  extra rows: in the inventory `"<ContainerName> >"` (when a container is open), `"Radio"`; in a container
  `"My Inventory >"` / `"Open Inventory"`.
- Buttons `Options` / `Close`. Selecting a filled row opens a second list titled with the item name:
  inventory `Equip / Use / Drop` + module rows (`Combine…`, `Move to <container>`), container
  `Equip / Move to inventory` + module rows, buttons `Accept` / `Back` (`dcnFvKxCe2Q @ 9:40` "Key (Sentinel)").
- Errors go to the action text: "Extra 2 slots required", "You are already holding an item".
- Geometry at 1280×720: box 420×305 px at (430,205); list area (437,240)–(840,465) with scrollbar; row pitch
  18 px; title 14 px; buttons 95×28 px rounded, 1 px light border.
- Colours (sampled): box `#0D0B07` ≈ black 90 %, list area `#020202`, title bar `#2A2829`, selected row
  `#81181B` (SA-MP's dark red), button fill `#818183`, text white.

MTA has no SA-MP dialog, so this is a dx list widget. **Current `ui/client/list.lua` is a generic
action-list (expand a row to reveal buttons) with a different look and no title bar / Options / Close pair.**
To be 1:1 it needs: the dark box + red highlight + `[NN]Name` rows + `<Empty>` padding + two-level
list (row → options list) + the two buttons, keyboard up/down/enter/esc like a dialog.

**Body panel** `core/ui/body-preview.pwn` + `core/char/inventory.pwn:ShowPlayerHealthInfo`:

- Defaults `x 100, y 120, width 120`, label font 1 `0.20/1.00`; Header "Health status and wounds" (centred,
  boxed), Background box colour `128` (black 50 %) 23.6 lines tall, Footer at y+204 `"%.1f%% Unconsciousness
  chance"` (boxed), skin preview (font 5, model = player skin, size `width×1.333 × 210`, centred).
- Left column (x−55, left aligned) one label per body part: `Head/Torso/Arm R/Arm L/Groin/Leg R/Leg L: n`,
  white, **red `#FF0000` when n > 0**. Right column (x+55, right aligned): `Bleeding` (red→green by rate),
  `Hungry` (when food < 66.6, colour by hunger), `Food Infect`, `Wound Infect` (red), each drug name (yellow).
- Footage: panel 250×350 px at (75,190) on 720p, header bar `#9A9B96`, footer bar `#3D3A33`, "Hungry"
  `#309428`, "Leg R: 2" `#A4090B` (`AEp1SnYke4U @ 0:28`).

Issue #39. Needs the skin-portrait atlas (see fonts table, font 5).

**Gear tiles** `core/char/inventory.pwn:CreatePlayerTile` — six 60×60 tiles at `(490,120) (560,120)
(490,230) (560,230) (490,340) (560,340)` for Head, Face, Hand, Holster, Torso, Back:

- Title above (y−12, centred, font 2 `0.15/1.00`, boxed → grey bar `#747469`), tile = model preview
  (background `0xFFFFFF08`, overlay white, rotation `-45, 0, -45`, zoom 1, empty = model 19300), caption below
  (y+60, centred, font 2 `0.15/1.00`, width+10): item name in caps, `<EMPTY>`; hand slot `"(%02d) %s"`; weapons
  carry their state text "[05] MODEL 70 (1/2, .308, FMJ)".
- Footage: columns at x 980 and 1120 px, rows at y 172/349/526 px on 720p (`AEp1SnYke4U @ 0:28`).

### 2.3 Other screens

| Screen | Upstream | Footage | MTA |
| --- | --- | --- | --- |
| **Death** `core/player/death.pwn:419` | Global textdraws: "YOU ARE DEAD!" `320, 300` centred font 1 `0.50/2.00` white, shadow 1, box `85` (black 33 %) 150 wide; ">Play Again<" `320, 323` `0.37/1.60`, same box, selectable. Screen is black (camera off), chat stays. | `p52g-vd0syA @ 11:52`: grey text in a slightly lighter box on black. | **Current `character/client/deathscreen.lua` draws a 3× red "YOU ARE DEAD" over a 67 % black overlay with a "> Play Again <" line: wrong size, colour and box.** Match the two small boxed lines. |
| **Class select** `core/player/spawn.pwn:111` | "~n~Male~n~~n~" at `250, 200` and "~n~Female~n~~n~" at `390, 200`, centred, font 1 `0.50/2.00`, shadow, box black opaque `100 × 44`, selectable. | `l1sciOHrK2s @ 5:44` (2013): two words on black. | Two dx buttons on the black screen. |
| **Tutorial** `core/player/tutorial.pwn` | Prompt `320, 300` boxed black 150×34 selectable; four annotated boxes (`390,140` keys; `83,250` watch; `390,20` stats; `484,280` exit), font 1 `0.30/1.50`, shadow, box `100` (black 39 %). Strings `TUTORKEYSPR` "This tells you ~>~ what keys to press" etc. in `scriptfiles/languages/English`. | Tutorial #1 opening. | Defer (M8). |
| **Spectate** `core/admin/spectate.pwn:47` | Name `320, 365` and info `320, 380`, centred, font 1 `0.20/1.00`, shadow, box black 340 wide. | — | Staff tooling. |
| **Keypad** `core/ui/keypad.pwn:333–556` | Background `320, 204` centred, box `80` (black 31 %) 82 wide × 16.2 lines; four edge boxes `0x87878787`; display "0000" `320, 210` centred font 2 `0.50/2.00` yellow `0xFFFF00FF` on black 80 wide; 3×4 keys at x `290/320/350`, y `240/270/300/330` (7 8 9 / 4 5 6 / 1 2 3 / X 0 >), each 20×20, font 1 `0.50/2.00`, **black text with white outline** on `0x20202080`; hover `0xFF0000FF`; sound 21002 on open; hack mode with tries. | Prompt "Enter the 4 digit passcode to open this defence." in chat (`dcnFvKxCe2Q @ 9:12`); keypad itself not on camera. | dx grid of 12 buttons, Issue #36. |
| **Radio** `core/ui/radio.pwn` | Panel "RADIO" `320, 200` centred font 1 `0.50/1.50` box `100` 200 wide; strip "-l-l-l…" `320, 220` `0.30/1.00`; knobs sprites `LD_DRV:nawtxt` 30×30 at `220,203` / `390,203` colour `0x780000FA` (±0.5 MHz); `global`/`freq` toggle `238, 251`; "Frequency: %.2f" `320, 251` (click → input dialog 87.5–108.0); power `402, 251` blue; Close `320, 274`; hover `0xFFFFFF88`. Opens from the inventory "Radio" row or R in a vehicle. | "R Open radio" in the vehicle key list; panel not on camera. | dx panel; replace sprites with arrows. Issue #49. |
| **Item tweak** `core/world/item-tweak.pwn:374–466` | Arrow sprites `~u~ ~d~ ~<~ ~>~` at `580,320 / 580,360 / 560,340 / 600,340`, `R`/`L` at `610/550, 310`, "Move" `587, 390`, "Done" `587, 420`. | — | Staff placement UI; defer. |

### 2.4 Chat and 3D text

- **Chat** is the stock SA-MP chatbox, top-left, with client timestamps `[hh:mm:ss]`. Formats
  (`core/player/chat.pwn`): `[Global] (%d) %P{FFFFFF}: %s`, `[Local] (%d) %P{FFFFFF}: %s`, radio
  `[%.2f] (%d) %P{FFFFFF}: %s` (name in the player colour), server lines prefixed `>` in the palette above
  (blue tips, yellow "Vehicle Sentinel saved!", orange/blue supply-drop announcements, grey join/leave).
  MTA: `outputChatBox` reproduces the text; the box itself (font, lines, position) is a **client preset**
  (`Chatboxpresets.xml`, read-only through `getChatboxLayout`) and cannot be set by the server, so an exact
  SA-MP chat look would need a dx chat.
- **Name tags** `core/admin/name-tags.pwn`: `"(%d) %s"` YELLOW, draw distance 6000, no LOS, plus a BLUE
  `[|   |]` LOS variant — staff only. Players see no name tags (`AEp1SnYke4U @ 3:32`). MTA: `setPlayerNametagShowing(false)`
  for everyone, staff get a dx label.
- **World item labels** (`item` include): `SetButtonLabel(name, 0xFFFF00FF, range 2.0, no LOS)` at the
  button height (`z + 0.96`); the pickup prompt is the button text `"Press ~k~~VEHICLE_ENTER_EXIT~ to pick up"`
  rendered through the action text slot. Footage: yellow "Supply Crate" above the crate, white "Press F to pick
  up" at the action-text position (`AEp1SnYke4U @ 3:32`). **Current `items/client/world.lua` already draws a
  yellow label within 15 m; upstream shows it only within 2 m.** Trees: `"0.0"` yellow label at z+1.

## 3. Gap list against `resources/[scavengesurvive]` today

Updated 2026-10-22 after the dx rework (`feat(ui,hud): the SA-MP look`); rows marked **done** landed with it.

| Area | State | Still missing | Next |
| --- | --- | --- | --- |
| `hud/client/main.lua` | **done**: stock HUD with radar, clock, money and ammo hidden; hunger bar at `517.8,78.7` over MTA's health bar; key-actions column from `keyactions.lua` (`Reload`, `(Hold) Unload`, `Remove handcuffs`, `Eat`, `Put away`, `Drop item`, `Open inventory`); `clip/reserve` ammo text under the weapon icon; brightness overlay; state re-requested on start (`hudStateRequested`) | vehicle lines, Give item, Remove bag, combat-log red | vehicle commands in `vehicles`; a client signal for combat logging |
| watch, vehicle panel, radio | **done** (`watch.lua`, `vehiclepanel.lua`; the ellipse is `dxDrawCircle`, font 2 tuned against footage in `a0da42b`/`649aeb7`; radio panel in `chat/client/main.lua` with `chat.PANEL` geometry) | the watch shows the live frequency from `chat`; the panel's knob sprites are boxes with `<`/`>`, the frequency input dialog is the mouse wheel + `/freq` | combat-log red colour needs a `character` signal |
| help tips | missing | `tool-tip.pwn` green paragraph at `150,350` for 20 s on pickup | wire the `<ITEM>_T` strings already in `data/generated/lang_*.lua` and a per-player toggle |
| `ui/client/list.lua` + `items/client/inventory.lua` | **done**: dialog clone (`dialog.lua`, geometry from the footage), `[NN]Name` and `<Empty>` rows, Options → Equip / Use, Bag dialog titled with the worn bag's item name (`<BagName> (used/size)`) and `<BagName> >` / `My Inventory >` navigation | `Drop` and `Move to bag` options | server requests for drop-from-container and move-between-containers |
| `ui/client/actiontext.lua` | **done**: one slot at y 350, replace-in-place, optional timer; `toast()` kept as a 3 s alias | | |
| `ui/client/progress.lua` | **done**: progress2 bar at `291,345`, driven by `character/client/deathscreen.lua` during knockouts (`knockedOut`) | hold actions (eat, repair, cuff) | wire hold timers to `progressShow`/`progressHide` |
| `character/client/deathscreen.lua` | **done**: 30 s rising camera, boxed lines at 325/349 under the alpha-185 brightness overlay with hover highlight (`649aeb7`) | | |
| body panel, gear tiles | missing | | issue #39 + the icon/skin atlas generated by `dev` |
| `auth/client/login.lua` | CEGUI window | SA-MP input dialogs | fine as is (spec: CEGUI only for passwords) |
| world labels | yellow within 15 m | yellow within 2 m, prompt via action text | tighten the range, add the prompt |

## 4. Verified MTA facts used above

- `dxDrawText` built-in fonts: default, default-bold, clear, arial, sans, pricedown, bankgothic, diploma,
  beckett, unifont; custom TTF via `dxCreateFont(path, size 5–150, bold, quality)` after `onClientResourceStart`.
- `dxDrawModel3D` (1.6): world-space only, objects only, "You can not render model to render target".
- `setPlayerHudComponentProperty` (1.6 r22868): components ammo, area_name, armour, breath, clock, health,
  money, radar, vehicle_name, weapon, radio, wanted, crosshair (radar/crosshair not modifiable); properties
  position, size, fillColor, fillColorSecondary, drawBlackBorder, drawPercentage, blinkingValue, dropColor,
  fontOutline, fontShadow, fontStyle (menu/subtitles/pricedown/gothic), fontAlignment, proportional, textSize.
- Chatbox layout: `getChatboxLayout` is read-only; values come from the client's preset.
- Control names: `enter_exit`, `conversation_yes`, `conversation_no`, `group_control_back`, `sub_mission`;
  there is no `answer_phone` control. `getBoundKeys(control)` returns the key table.
- SA-MP textdraw canvas is 640×480; box origin is 10 units up and 5 left of the create position; centred
  boxes take `TextSize(x = ?, y = width)`; sprites and model previews take `TextSize(w, h)`.
