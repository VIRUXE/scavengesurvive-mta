# World wounds and machines live check (smoke steps 45-46), 2026-10-30

Dev server after merging branch `ccr-e37baa1b-tmao7k` (0abe822: #144 falls, drowning, rams and explosions; #145
machines). One client (`VIRUXE`), shared with a peer session, driven over the `dev` resource's rcon: `lua`, `clua`,
`chat`, `screenshot`. The machines were checked with database rows and resource restarts, no client.

## Database

`machine_finish` had been written into `sql/schema.sql` by hand (the branch's session had no MariaDB).
`sqltool apply` put it into the local `scavengesurvive`, and a `dump` afterwards came out byte-identical, so the file
and the live database agree. The two settings rows `vehicles.damage_bleed_mult` / `vehicles.damage_knock_mult`
(1.0) were inserted locally. Both were applied on prod the same evening (the procedure's MD5 matches local).

## Results

| Step | Checked | Result |
| --- | --- | --- |
| 46 c | restart mid-cook, scrap | **fail, then fixed twice**. `653fba5`: `machines.lua` resumed cooks from its own `onResourceStart`, which ran before `main.lua` connected the DB (`Bad argument @ 'dbQuery'` on every start). `c37a086`: `toJSON(results)` sent `[[...]]`, MTA's wrapper array, and the procedure reads `$[*]`, so every cook came out empty (`2 items in, 0 out`). After both: a ScrapMachine with a Bucket and a Barbecue, staged mid-cook in the DB, finished 3 s after `rr items` with 8 Scrap Metal, fuel 20 -> 13 |
| 46 d | refine, water | pass (same staging): 2 Scrap Metal -> 2 Refined Metal; a Bottle of 0.25 Sea Water -> a Bottle of 0.25 Water, fuel 20 -> 16.5 |
| 46 a | tap and hold | pass, after `rr hud` (the merge had changed `hud`, which had not been restarted, so the client ran without the machine hints and holds): `F Access machine` / `F (Hold) Machine menu`; a tap opened the empty `Scrap Machine (0/12)`; the hold showed `Fuel amount: 0.0`; Start refused with `There is not enough fuel. Machine requires 3.5 per item.` |
| 46 b | refuel | pass (`rcon.ps1 hold`): `Refuelling...` with a bar; a 1 s hold moved 2.2 from a 20 L can into the machine, a longer one the rest (18.7 + 1.3 = 20) |
| 46 c | on screen | pass: `Cook time: 3 minutes 13 seconds`, log `started by VIRUXE: 2 items, 193 s`, smoke beside the machine, a tap `2 minutes 42 seconds left`; fast-forwarded in the DB + `rr items`: `2 items in, 8 out`, fuel 18.7 -> 11.7, the smoke gone |
| 46 e | Crowbar | **fail, then fixed** (`07b4237`): the hud sent F to the machine menu whatever was in hand, and the port had no machine recipe at all, so a machine could be neither built nor taken down. Added upstream's three (init.pwn:1329-1331) and the hud skips the machine with a Crowbar in hand; the hints now read `F Deconstruct` only. Live after the fix: a 25 s hold with the deconstruct bar, then the machine gone and Canister, Motor, Fluctuator Unit and Power Supply on the floor. The other diverging recipes are #147 |
| 45 a | falls | pass: four drops from 35 m onto -2667, 94.6. GTA's fall damage was cancelled; each landing cost 1 to 6 hp, added bleed (0 -> 0.06 -> 0.116) and knocked VIRUXE out (the countdown bar on screen) |
| 45 b | drowning | partly: a ped teleported under water stands on the seabed and never drowns, so the GTA side was not reached (needs a real dive, #98). The server path was driven with the client's own `weaponHitReported` for weapon 53: each tick a knockout and 5 hp, no bleed |
| 45 c | rams | needs two clients |
| 45 d | explosions | **fail, then fixed** (`5d726ea`), re-run on the client: `Wounded: right leg -46 hp (bleeding)` and a knockout: a creatorless `createExplosion` (what the `explosives` resource does) reaches `onClientPlayerDamage` as weapon 16 (type 0) or 19 (type 10), never 51, so the blast took the flat fallback: toast `Wounded: torso -20 hp`, no bleeding, no knockout roll. `wound.isExplosion` now maps 16, 19, 35, 36, 39 and 51 to the explosive wound. |
| 45 e | staff duty | not driven |

## Also seen

- A blast's knockout runs over a minute; `9e03e08` adds staff `/knockout <ms> [player]` (upstream level 5), `0` wakes up.
- The explosion probe killed `VIRUXE` (35 hp, then two fallback hits of 20): heal before probing damage.
- A server `setElementHealth` does not stick on a spawned character: `character` owns hp. Use
  `exports.character:modifyStat(p, "hp", n)`.
- Open water: (-2600, 1600) in the SF bay is water (`getWaterLevel` 0); (-3000, 400) is the beach and (-3400, 400)
  has no water at all.
