# Auth reload protection — 2026-11-03

`auth` now marks and freezes live players before its VM stops. The server-owned `auth.reauthProtection` element data survives a reload and is cleared only after successful admission, including the whitelist check. Failed passwords and repeated reloads leave the protection active. Successful login restores the previous freeze state while respecting an active staff freeze.

Protected characters take no wounds, scripted health loss, knockouts, infection or drugs. The survival tick pauses, preserving health, food, bleed and existing drug timers. Weapon reports from or against protected players are ignored; client damage remains cancelled without reporting hits. Carried explosives cannot directly kill a protected player. Disconnecting during this maintenance protection saves the character instead of applying a combat-log death.

Character state now records its account ID. Re-authenticating the same account reuses the live character instead of loading and spawning it again, preserving current stats and avoiding the re-login respawn. Normal character-resource restarts still reload characters from the database.

## Validation and rollout

- Committed and pushed implementation `5fc40fe`.
- Luacheck: 0 warnings / 0 errors across 278 files. StyLua, changed-file Lua 5.1 syntax checks, language QA and `git diff --check` pass. No automated tests were added.
- Reloaded `weapons`, `explosives`, `character` and `auth` on production. Existing players were protected manually during the initial installation; subsequent auth protection is automatic.
- Live guarded export calls rejected wounds, knockouts and scripted death while protection was active.
- A further auth reload verified the real stop hook: both connected players already had the protection marker and were frozen when auth stopped. One second later both had identical HP, food and bleed values.
- At admission, both retained the same character ID, HP, food and bleed; protection was removed and both previous freeze states restored. Neither was in a vehicle during this check; the vehicle/seat comparisons remained unchanged. Exact coordinate equality held for one player and not the other, so this check does not establish zero physical movement while waiting. No character respawn was performed on re-login.
- Both players were authenticated, unprotected and unfrozen afterward. No new script-log errors, access-denied failures or failed-resource messages appeared.

Live snapshots and logs are saved outside the repository under `/gta/sa/mta/backups/reauth-20261103/`. No database schema change was required.
