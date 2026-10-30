# The last upstream core ports, live check (smoke steps 48-52), 2026-10-30

Dev server at 32951cc plus the hold-animation fix below. One client (`VIRUXE`, character 13), shared with two peer
sessions (a house tour and Area 69 work), driven over the `dev` resource's rcon: `lua`, `clua`, `cmd`, `key`, `chat`;
screenshots from the server first, then from the game window through PowerShell (`PrintWindow`) on the user's request.
Spot: the LV airfield runway at (1477, 1560-1602).

## Restart order

`items` had been restarted (by a peer, ~21:55) on 928dd97 before `character`, which did not yet have the new
`isHandsUp` export: every pickup and use threw `items/server/main.lua:124: failed to call 'character:isHandsUp'` until
`rr character` (~22:05). Character 12 died in that window with 1 HP left, possibly unable to treat. Restart the
provider of a new export first (noted on #152 and #57).

## Results

| Step | Checked | Result |
| --- | --- | --- |
| 48 a | Hammer over a dropped Large Frame, Enter, F with empty hands | pass: built lying (`pose horizontal`), `data.defence.covered = true`, on screen the panel lies across the frame's top |
| 48 b | F again, F again, `rr items`, stand on it | pass: covered cleared and set again; after the restart the client draws the frame at z 9.91 and the panel at z 12.51 rotated (0, 90, 0); placed at z 14 the player came to rest at 13.51 on the panel |
| 48 c | Crowbar | pass: from the south (front) nothing; from the north the frame was taken apart into four Refined Metal and the panel went with it. A second frame, built by a Sledgehammer over those four, was unbuilt by the Crowbar instead (row kept, `data` emptied) |
| 48 (user) | "there was no animation when deconstructing" | **fail, fixed**: neither crafting's construct / deconstruct holds nor building's defence holds played one. Now `BOMBER/BOM_Plant_Loop` and `COP_AMBIENT/COPBROWSE_LOOP` as upstream, cleared when the hold ends or is cancelled; seen on screen for the Sledgehammer build and the Crowbar, cleared afterwards |
| 49 a | Fire Lighter on a Firework Box | pass: 6 s later the burst showed (flashes and sparks overhead), up to 37 effects at once, gone a second later |
| 49 b | two presses 1.2 s apart | pass: one launch (its three generations start at 7.7, 7.9 and 10.3 s), the box stays |
| 49 c | Campfire from logs (22:56) | pass: a Fire Lighter over three Wood Logs with no box near held with the plant animation and built a burning Campfire; the logs were used up, the lighter kept |
| 50 a | driver of a Rhino | pass: the empty red bar under the tank |
| 50 b | cannon (the user firing) | pass: the client's heat log rises 20 a shot and falls 1 a tick; over 40 it resets to 0 (`37, 57, 0`), the explosion is created (type 11, seen on screen at and 8 m ahead of the tank). The Rhino is explosion-proof, so it survives: step 50 said "blows up", corrected |
| 50 c | engine off (22:58, the user firing) | pass: the bar stayed empty; the client received no heat change and the engine stayed off |
| 51 a | hands up | pass: F at a Bandage, the inventory key: nothing; after the toggle (the hands-up key again; `stand` does not end it) the Bandage is picked up |
| 51 b | knocked out, on duty | pass: no pickup during `/knockout 6000` or on duty, pickup again off duty. Cuffed (22:57, `setPlayerCuffed`): no pickup, no inventory, cuffs on the wrists; uncuffed, the Bandage is picked up |
| 51 c | `/additem 0`, `/additem NULL` | pass: `Item type 0 cannot be created` |
| 52 a | `/bug`, `/bug <text>` | pass: the `Bug report` dialog with `BUGREPORTDI`; the row (name, account 2, text), `BUGREPORTSU` and the staff line |
| 52 b | `/issues`, open, Delete | pass: `VIRUXE: port check 153 a description lo[...]`; the report box (Reporter, Reason, Date) with Delete / Back at level 5; Delete removed the row, logged `bug_delete`, and the list came back as `There are no bug reports to show.` |

Test rows were removed (`bug_reports` emptied, its counter reset); the frame, metal and firework box were left lying.
