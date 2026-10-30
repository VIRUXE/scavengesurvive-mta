# World wounds and machines live check (smoke steps 45-46), 2026-10-30

Dev server after merging branch `ccr-e37baa1b-tmao7k` (0abe822: #144 falls, drowning, rams and explosions; #145
machines). One client (`VIRUXE`), shared with a peer session, driven over the `dev` resource's rcon: `lua`, `clua`,
`chat`, `screenshot`. The machines were checked with database rows and resource restarts, no client.

## Database

`machine_finish` had been written into `sql/schema.sql` by hand (the branch's session had no MariaDB).
`sqltool apply` put it into the local `scavengesurvive`, and a `dump` afterwards came out byte-identical, so the file
and the live database agree. The two settings rows `vehicles.damage_bleed_mult` / `vehicles.damage_knock_mult`
(1.0) were inserted locally. **Prod still needs both** (the procedure and the two rows).

## Results

| Step | Checked | Result |
| --- | --- | --- |
| 46 c | restart mid-cook, scrap | **fail, then fixed twice**. `653fba5`: `machines.lua` resumed cooks from its own `onResourceStart`, which ran before `main.lua` connected the DB (`Bad argument @ 'dbQuery'` on every start). `c37a086`: `toJSON(results)` sent `[[...]]`, MTA's wrapper array, and the procedure reads `$[*]`, so every cook came out empty (`2 items in, 0 out`). After both: a ScrapMachine with a Bucket and a Barbecue, staged mid-cook in the DB, finished 3 s after `rr items` with 8 Scrap Metal, fuel 20 -> 13 |
| 46 d | refine, water | pass (same staging): 2 Scrap Metal -> 2 Refined Metal; a Bottle of 0.25 Sea Water -> a Bottle of 0.25 Water, fuel 20 -> 16.5 |
| 46 a, b, e | F menu, refuel hold, smoke, Crowbar | not driven (needs keys on the client) |
| 45 a | falls | pass: four drops from 35 m onto -2667, 94.6. GTA's fall damage was cancelled; each landing cost 1 to 6 hp, added bleed (0 -> 0.06 -> 0.116) and knocked VIRUXE out (the countdown bar on screen) |
| 45 b | drowning | partly: a ped teleported under water stands on the seabed and never drowns, so the GTA side was not reached (needs a real dive, #98). The server path was driven with the client's own `weaponHitReported` for weapon 53: each tick a knockout and 5 hp, no bleed |
| 45 c | rams | needs two clients |
| 45 d | explosions | **fail, then fixed** (`5d726ea`): a creatorless `createExplosion` (what the `explosives` resource does) reaches `onClientPlayerDamage` as weapon 16 (type 0) or 19 (type 10), never 51, so the blast took the flat fallback: toast `Wounded: torso -20 hp`, no bleeding, no knockout roll. `wound.isExplosion` now maps 16, 19, 35, 36, 39 and 51 to the explosive wound. The fix is unit-tested, not re-run on the client |
| 45 e | staff duty | not driven |

## Also seen

- The explosion probe killed `VIRUXE` (35 hp, then two fallback hits of 20): heal before probing damage.
- A server `setElementHealth` does not stick on a spawned character: `character` owns hp. Use
  `exports.character:modifyStat(p, "hp", n)`.
- Open water: (-2600, 1600) in the SF bay is water (`getWaterLevel` 0); (-3000, 400) is the beach and (-3400, 400)
  has no water at all.
