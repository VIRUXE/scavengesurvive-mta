# Auth session continuity — 2026-11-03

Auth reloads now preserve admitted sessions on the existing player elements in server-only, client-denied `auth.session` data. Successful admission saves the account profile; resource stop refreshes the profile and original whitelist deadline. Resource start restores sessions synchronously, before client readiness can show a login prompt. It does not re-emit `playerAuthenticated`, respawn the character or insert a connection-log row. Old reload protection is cleared during the upgrade. New auth reloads do not freeze players or set that protection flag.

Disconnect clears the snapshot and destroys the player element, so a new connection still goes through normal authentication. New player elements initialize the private key with client changes denied. Pending kicks are preserved separately so restarting auth cannot reinstate a session already refused. Whitelist countdowns retain their deadlines and resume after the settings load. The same-account character reuse safeguard remains in place.

The first deployment copied only currently authenticated sessions through the old resource's public exports into the new private snapshot, before restarting it. This one-time handoff avoided asking the online player to log in again. Subsequent reloads use the new stop/start lifecycle directly.

Production checks after both the initial deployment and the final lifecycle update: Mafioso remained authenticated as account 14 on character 22, unfrozen and without a protection flag. His connection-log row count remained 4. Auth restarted successfully, with no new login record or authentication log message. Lua 5.1 syntax, luacheck, StyLua and diff checks passed. No database changes or automated tests were required.

## Reported missing sniper

Inspected item system-versioned history and current ownership without changing any inventory. His sniper is Model 70 item `137228`:

- Held by character 22 at 19:30:51.
- Moved onto the ground at 19:30:54, at approximately (-2269.25, 543.27, 34.12), before the 19:31:16 auth reload.
- Picked up by character 22 at 19:32:47.
- Holstered at 19:32:48; drawn again at 19:33:54 and holstered at 19:34:23.
- Current row is still owned by character 22 in the holster, with 1 round loaded, 6 in reserve and Ammo308 selected.

The history establishes that the item was recovered and was not deleted. It does not establish whether the original ground transition was a voluntary drop or another gameplay action. No replacement item was issued.
