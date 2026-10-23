# Live checks, 2026-10-23 (Client VIRUXE, driven through `rcon.ps1`)

Full in-game verification of Milestone M6 (Apparel, Building, Crafting) and upstream utilities (`/move` and `/fly`), run on a local server with connected client `VIRUXE`. Frames captured using `rcon.ps1 screenshot VIRUXE`.

| System / Step | Live Test Action | Observed Outcome | Result |
| :--- | :--- | :--- | :--- |
| **Apparel Attachments (#38)** | Wore `CowboyHat`, `BandanaBl`, `Armour` via stored procedures & element data | Attached to head, face, and spine bones with correct upstream offsets; verified in screenshot `VIRUXE-1792745727.jpg` | **Pass**, later found wrong: hats sat in front of the face and offsets were not per skin; see 2026-10-23-apparel-fit.md (#70) |
| **Body Preview & Gear Tiles (#39)** | Ran `/inventory` command | 3D body preview with health & wound indicators on the left, 6 gear tiles on the right; verified in screenshot `VIRUXE-1792745749.jpg` | **Pass** |
| **Gear tile previews (live `dxDrawModel3D`)** | Picked up a `CowboyHat` (HAND tile), wore it through `item_wear` + `rr items` (HEAD tile), opened `/inventory` | Model drawn in world space under the see-through tile, centred, caption `(01) COWBOY HAT` / `COWBOY HAT` below; `VIRUXE-1792764211.jpg`, `VIRUXE-1792764511.jpg`. First pass with the bounding-box half-diagonal as radius filled under half the tile; switched to the largest half-extent × 1.1 | **Pass** |
| **Safeboxes & Tents (#37)** | Spawned `TentPack`, equipped `Hammer`, pitched tent | World object replaced with model 3243 "Pitched Tent" with 16-slot container; verified in screenshot `VIRUXE-1792745982.jpg` | **Pass** |
| **In-Hand Combine (#35)** | Held `Knife` + `Clothes` in inventory | `Clothes` consumed, `Bandage` created in inventory slot 2, `Knife` preserved in hand | **Pass** |
| **Ground Construction (#35)** | 2x `WoodLog` on ground + held `FireLighter` | 3s construction timer completed, 2 logs consumed via `destroyWorldItem`, `Campfire` spawned in front of player; verified in `VIRUXE-1792746618.jpg` | **Pass** |
| **Deconstruction (#35)** | Held `Crowbar` on `Campfire` | 4s deconstruct timer completed, `Campfire` destroyed, `WoodLog` returned to ground | **Pass** |
| **Workbench Crafting (#35)** | `Workbench` container loaded with `Battery` + `CorPanel`, player holding `Screwdriver` | 5s craft timer completed, ingredients consumed from container, `Keypad` created in slot 1 | **Pass** |
| **Defences & Doors (#36)** | Spawned `Door`, interacted without lock | Door swung open 90° (`rz = 90`), automatically closed back to `rz = 0` after 5 seconds | **Pass** |
| **Keypad Security (#36)** | Installed `Keypad` on door with passcode `1234` | Submitting `9999` rejected (`rz = 0`); submitting `1234` granted access, swinging door open for 5s auto-close | **Pass** |
| **Plot Poles (#36)** | Placed `PlotPole` in world | 20m spherical territory colshape registered: `insideNear = true`, `insideFar = false` | **Pass** |
| **Player Unsticking** | Player relocated to clear ground | Position moved to `-2928.0, -70.0, 1.0` in San Fierro; verified clear in `VIRUXE-1792747631.jpg` | **Pass** |
| **Admin `/move` command** | Ported from `gamemodes/sss/core/admin/level3.pwn` | Tested `/move u 3` and `/move b 10`; player moved smoothly in relative direction | **Pass** |
| **Admin `/fly` feature** | Ported from `filterscripts/fly.pwn` | `/fly` toggles fly mode; Jump + Enter/Exit toggles active flight; skydive animation (`FALL_SKYDIVE`), directional controls and fall damage immunity verified in `VIRUXE-1792747744.jpg` | **Pass** |

---

## Issues Found and Fixed During Testing

1. **MariaDB JSON Array Deserialization**:
   - MTA's `fromJSON` decodes JSON array tables as `{ [1] = { ... } }`.
   - Updated `isPitchedTent` in `items/client/world.lua` and `hands.lua` to check `r.data.pitched or (r.data[1] and r.data[1].pitched)`.
2. **Access Denied @ loadstring in new resources**:
   - New resources `crafting` and `building` required inclusion in the `ScavengeSurvive` ACL group to allow `loadstring` for `lib` module loading.
   - Added `resource.crafting` and `resource.building` to the ACL group dynamically and updated `server-config/resources.xml`.
3. **Module Loading `lib:getModule`**:
   - `getModule` returns Lua source code strings; resources must evaluate via `assert(loadstring(...))()`.
   - Resources must call `db.connect("<tag>")` before issuing database queries.
4. **Stored Procedure Argument Counts**:
   - Fixed `item_create` and `item_create_in_container` calls in `crafting` to specify `n = 11` so trailing `nil` values are not truncated by Lua 5.1 `#params`.
   - Fixed `item_create.sql` and `item_create_in_container.sql` to read `COALESCE(JSON_VALUE(category_data, '$.size'), JSON_VALUE(category_data, '$.bag_size'))` so safeboxes receive their configured capacity.
5. **World and Container Item Deletion**:
   - Added `destroyWorldItem(itemId)` and `destroyContainerItem(itemId)` in `items/server/main.lua` and exported them so ground construction and workbench crafting cleanly remove ingredients without failing `item_destroy` player ownership checks.
