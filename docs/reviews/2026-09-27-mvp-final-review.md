# Final review — MVP vertical slice (10ae807..ea06956)

Reviewer: final whole-branch review (opus). Read-only. The working tree, index, HEAD and branches were not changed.

**How the code was read.** All 139 code files in the range are new, so I read the current source file by file, which
covers the same content as `review-final-code.diff`. I read it in five passes: (1) `lib` and SQL (migration,
procedures, events, seeds, `tools/sqltool.py`); (2) `data`, `ui` and `auth`; (3) `character`; (4) `items`, `weapons`,
`loot`, `hud` and `dev`; (5) `server-config`, the READMEs, the smoke checklist and the tests. For the rest of the diff
(`.luacheckrc`, `.gitignore` and the community files) I only checked the file list.

**Local checks, run once:** busted 54/0/0, luacheck 0 warnings / 0 errors in 49 files, `stylua --check` clean,
pytest 35 passed.

---

## Strengths

- **The item graph is built well.** Each move is one stored procedure with an EXIT HANDLER, READ COMMITTED, `FOR UPDATE`
  guards, `<=>` for nullable ownership and a single `ok, code, payload` row. The schema backs this up with constraints:
  the exactly-one-location CHECK, `UNIQUE(holder_char_id, holder_kind)`, `UNIQUE(container_id, slot)` and a generated
  column that allows one alive character per account. The concurrency test really races two pickups.
- **Contracts line up across resources.** Every event in `events_registry.lua` is declared with the same remote flag in
  each resource that triggers or handles it. Every export that a caller uses exists with a matching signature. Every
  `db.call` has the right argument count for its procedure (character_create 9, death_drop 6, flush 1, container_put 3,
  container_take 2, item_create 11 with `n = 11`, item_create_in_container 2, item_destroy 2, item_drop 8,
  item_pickup 2).
- **Callbacks survive a player quitting.** Every DB callback that touches a player first checks `isElement(ctx.player)`,
  and there is a test for this (`items_server_spec`).
- **The server does not trust the client for positions.** Pickup and drop positions come from the server. Numbers
  inlined into SQL are server-side and formatted with `%g`/`%d`. Everything else uses placeholders.
- **`net.handler` is the single entry point for remote events.** It enforces `client == source` and a per-player,
  per-event rate limit.
- **The `character_flush` JSON path matches MTA.** `'$[0][*]'` fits `toJSON`'s outer array, and the procedure's
  `WHERE alive = 1` keeps a late flush from reviving a dead character.
- **`Character.die` is idempotent.** It checks `st.dead`, and `onPlayerWasted` returns early when it re-enters.
- **The damage path follows the spec's Appendix B.** The victim cancels the hit and reports it. The server checks
  range, the pair cooldown, `getPedWeapon` and that the held item justifies the weapon. Kills go through
  `killPed(victim, killer)`, which gives kill credit.
- **`run-local.ps1` has been proven** to boot the real server and to leave `acl.xml` stable on re-runs. The
  `function.loadstring` grant goes only to the listed resources and is documented as a security callout.
- **Re-applying without `--reset` is safe.** Migrations are version-skipped. Loot spawn ids come back the same after
  the seed re-runs, and `NOT EXISTS (items.loot_spawn_id)` stops duplicate rolls.
- **Deviations are recorded.** Each one is in the ledger with a ruling.

---

## Issues

### Critical (must fix)

**C1. Firearms are given with 0 ammo, so nobody can shoot (breaks checklist step 9 and the MVP goal "hold a weapon that
hurts other players").**
`items/server/hands.lua:71` runs `giveWeapon(player, w, tonumber(data.mag) or 0, true)`. Nothing in the codebase ever
writes `data.mag`: `/additem` and loot both pass `data = NULL`, and there is no ammo or reload system in the MVP. So an
M9 is held with 0 rounds, and GTA will not fire it. The plan had the same `data.mag or 0` line (plan line 3897), so the
bug was carried over from the plan. It was not introduced during implementation.
Fix: when `data.mag` is missing, fall back to the magazine size, e.g.
`tonumber(data.mag) or t.categoryData.magSize or 1`. Vanilla melee ids 1–15 always get 1. Firearms stay usable until a
real ammo model arrives, and the server-side wound check already refuses hits that the held item cannot justify.
Add a busted case for `setHeld` giving a non-zero amount.

**C2. The login prompt is sent on a 1 s timer after `onPlayerJoin`, before the client has necessarily started `auth`.
Nothing retries it (checklist step 2).**
`auth/server/main.lua:57-63` sends `onClientAuthPrompt` 1000 ms after `onPlayerJoin`. MTA drops a server-triggered
client event if the client has not yet added it ("Server triggered clientside event …, but event is not added
clientside"). That happens while the client is still downloading or starting `lib`, `data` (about 500 KB of Lua it
loads with `loadstring`), `ui` and `auth`. When the prompt is lost, the player sits on a black screen with no window
and no command to recover. The only workaround is to reconnect, which usually works once the files are cached. The same
race hits every player when `auth` restarts (`onResourceStart` → `prompt` → the client script has not restarted yet).
Fix: prompt from `onPlayerResourceStart` when the started resource is `auth`, or have the client send an
`onAuthRequestReady` event (registered as remote, handled through `net.handler`) from `onClientResourceStart`. Register
the new event in `events_registry.lua`.

### Important (should fix)

**I1. Held food cannot be eaten from the UI (checklist step 7 fails as written).**
The checklist says "`/additem HotDog`, **F**, **H** → **Eat**". But the list that **H** opens
(`items/server/containers.lua:83-126` and `items/client/inventory.lua:44-55`) shows only container contents, never the
held item. No key uses the held item either. The server's "use from hand" branch (`use.lua:38-41`) can therefore never
be reached from the client. Either add the held item as the first row (label `[hand] …`, actions Eat/Drop), or change
the checklist to "**Y**, **H** → Eat".

**I2. A worn bag is invisible (checklist step 6 says "visible on the back for B").**
`wearBag` (`containers.lua:32-51`) only changes `holder_kind` to `'bag'` and destroys the held object. Nothing attaches
a bag object to the player, not on wear, not on `rebuildHeld` and not after a restart. Either attach a server object at
a back offset (with `attachElements` to the player, and keep a per-player worn-object map that is rebuilt on
start/spawn), or drop "visible on the back" from the checklist and file it as a post-MVP issue.

**I2b (goes with I2). Wearing a second bag writes `ERROR` to scripts.log.**
The expected 1062 error for a second bag still goes through `db.lua`'s `poll`. That calls `outputDebugString(…, 1)`,
which writes `ERROR: … SQL error 1062` to scripts.log. The driver's `suppress=1062` does not stop this, because the
message comes from our own logging. Checklist steps 1 and 11 require an empty `rg ERROR`. Check for an existing worn bag
first, with `SELECT` or with a `NOT EXISTS` guard in the `UPDATE`, so that the refusal is `affected == 0` and never an
error.

**I3. Bleeding is cured by relogging or by `rr character`. This is deferred minor Task 8, promoted.**
`spawnFromRow` (`character/server/main.lua:40-50`) always sets `wounds = 0`. On the next tick, `survival.tick` sets
`bleed = 0` whenever `wounds == 0` (`survival.lua:41-48`). A player who was shot in step 9 can reconnect and be healed,
which is an obvious exploit in the core PvP loop. It also breaks the step 11 promise "`/stats` unchanged" whenever the
player is bleeding. The cheapest fix: on load, `wounds = (row.bleed > 0) and 1 or 0`. Persisting the count in
`character_flush` can come after the MVP.

### Minor (nice to have)

1. **Death-drop items float about 1 m above the ground.** `death.lua:7-8` passes the ped's centre `z` to
   `character_death_drop`, while `/additem` and item drop use `z - 0.9`.
2. **Corpse items never despawn.** `character_death_drop` leaves `despawn_at = NULL`, so every corpse's items stay
   forever. Set a despawn time (for example `loot.despawn_minutes`) in the procedure.
3. **A client can request a respawn when it has no loaded state.** The `onCharacterRequestRespawn` guard only refuses
   when `st.hp > 0`. If `st == nil` (for example during `loadOrCreate`, or after a failed `death_drop`), the request
   runs `character_create`, which retires the alive character without dropping its items, so they are orphaned. Only a
   malicious client can reach this; refuse unless `st` is nil because the last death finished.
4. **One account can be logged in from two clients.** Log in as "Bob", `/nick` to something else, then connect a
   second client as "Bob". Both clients load and control the same character. Refuse a login when the account already
   has a session.
5. **Login attempts reset on reconnect.** `MAX_ATTEMPTS` is counted per player element.
6. **auth calls `getPlayerIP`/`getPlayerSerial` after async bcrypt without an `isElement` check** (`accounts.lua:58,93`).
   If the player quits during hashing, this logs a bad-argument warning and writes `0` into `last_ip`.
7. **`share=1` never actually shares a connection.** The option string ends in `tag=<resource>`, so the full strings
   never match (the ledger says 5 connections). Ordering still works because `queue=game` puts every connection on one
   worker thread. CLAUDE.md, the plan and the spec still say "identical string so share=1 matches". Fix the wording, or
   move the tag out of the option string.
8. **The world sync assumes a sent event arrived.** `Items.sent` is updated when the event is sent. After `rr items`,
   the first sync (≤ 2 s) can arrive before the client has restarted `items`; the ids are then marked as sent while
   the client has no objects. This is the same race as C2, but less likely. A client "ready" event that resets `sent`
   would close it.
9. **`/rr`, `/additem` and `/sethp` are open to every player by default** (`dev` setting `*open=true`). This is fine for
   the local playtest, but add a line to server-config/README.md: never run `dev` with `open=true` on a reachable
   server.
10. **The death cause is often wrong.** `tick.lua:32` names the cause `starvation` only when `food <= 0`. Deaths while
    starving with food between 0 and 20 are reported as "bleeding".
11. **`character_flush` (the 10 s path) does not save interior or dimension.** Only `flushOne` on quit does.
12. **The HUD bars and key hints draw before login and on the death screen.**
13. **`net.buckets` entries are never removed on quit.** This is a small leak, and a new player whose element string
    happens to repeat an old one inherits its bucket.
14. **The first loot roll near a dense area can be a burst of several hundred `item_create` calls** on the single
    FIFO queue (`roll_batch = 300`). Expect the first pickup after `/rollloot` in Los Santos to lag. Consider a smaller
    batch.
15. **Docs:**
    - README step 4 says `.lua/bin/busted`. In Git Bash it is `.lua/bin/busted.bat`, as the ledger notes.
    - Checklist step 10 says "Drive ~500 m", but the MVP has no vehicles. Say "run".
    - The checklist should say that the two clients need different MTA nicknames, because the account name is the
      nickname.
16. **Test gaps that matter:**
    - No test covers `Items.setHeld` giving a weapon (C1 would have been caught).
    - Nothing tests the `Character` server flows: that `die` is idempotent, the respawn guard, and `applyWound` →
      `die`.
    - The weapons hit handler (`hitBleed` matching) is untested.
    - No test covers the bag container from `item_create_in_container` (already a deferred minor).
    - The SQL flush tests hand-write the `[[…]]` shape. That is acceptable, but a one-line busted test that the
      mocked `toJSON` wraps the table would pin the contract on the Lua side too.

---

## Deferred-minor triage

| Ledger line | Verdict |
|---|---|
| T1 pyproject.toml lacks `[build-system]` | fine to defer (pip works; egg-info is git-ignored) |
| T4 `net.issueToken` unseeded `math.random`, no sweep | fine to defer (tokens are unused in the MVP) |
| T6 list has no scrolling (≤ 25 rows) | fine to defer (inventory 6 + bag ≤ 14 rows) |
| T6 `progressStart(0)` NaN / `listOpen` over open list skips Closed / toast `colorCoded` / `maxVisible` unused | fine to defer (progress unused; reopen is intended; no `#` in item names) |
| T7 live check of `fileOpen` on `<file>` accounts.lua under `database_credentials_protection` | fine to defer (the setting is not enabled by run-local; smoke step 2 covers it) |
| T2 `container_put/take` lack `p_char_id IS NOT NULL` guard | fine to defer (every caller checks `charId` first) |
| T11 `(stats.bleed or 0)` guard; dead branch in `keys.lua` | fine to defer |
| T10 size > 6 capped instead of upstream re-roll 3..5 | fine to defer |
| T8 async `flushAll` on stop / `characters.wounds` not persisted / death-screen click checks only y | **fix before playtest: the wounds half (I3)**. Async stop flush and the y-only click are fine to defer (the 10 s flush bounds the loss) |
| T3 GasCan ammo+liquid; two Russian `%с` typos | fine to defer |
| T9 no SQL test for bag container in `item_create_in_container`; inventory always `listOpen` | fine to defer (add the test with the I2 fix if convenient) |
| T12 no `pcall` around exports in the hit handler; loss > 200 dropped; no kill credit for explosion/vehicle | fine to defer |
| T13 first post-boot run reformats `acl.xml` | fine to defer |

---

## Declined to judge

- **Balance numbers**, such as knife bleed 0.35 per stab (from upstream `muzzleVelocity`), food and regen rates, and
  loot weights. They are converted from upstream and are playtest tuning, not something the plan or spec fixes.
- **The `onPlayerWeaponFire` ring buffer, armour/shields, knockouts and the ammo bleed multiplier.** The plan lists
  these as known MVP gaps (Task 12).
- **One-shot tokens for mutating UI actions** (spec §Client/server split). No plan task wires them, and the MVP relies
  on rate limits and server-side ownership checks.
- **The spec's production server config**, such as `database_credentials_protection`, `minclientversion` and
  `bandwidth_reduction`. `run-local.ps1` targets a local dev server only.
- **Translations are loaded but not used in the UI** (toasts are hard-coded English). Multi-language UI is not in the
  MVP goal.
- **The GitHub side of Task 14** (labels, milestones, issues, project board). The controller verified it with `gh`, and
  it is not code on `main`.
- **`ST_Distance` pickup lookup scans every row** and does not use the spatial index. It is fine at MVP item counts; see
  the spec's "What to revisit as it grows".
- **CEGUI for the login window** instead of dx. The spec allows CEGUI for password forms.
- **Upstream map packs, the rotation spike and SA-MP-only model replacements**, beyond checking that the fallback
  mapping exists. Static world is out of the MVP.
- **Growth of the system-versioned tables, backups and NFR load targets.** These are post-MVP operations.

---

## Verdict

**Ready for the two-client playtest after fixing C1 and C2 and I1–I3 (including I2b).** C1 and C2 make checklist
steps 9 and 2 fail outright or unpredictably. I1 and I2 are checklist steps that fail as written; each can be fixed in
code or by changing the checklist. I3 is a cheap one-liner that closes the relog-heals-bleeding exploit, which step 9
invites. The architecture, the cross-resource contracts, the procedures and the tooling are sound. None of the Minor
items block the playtest.

---

## Follow-up (fixes after this review)

- **C1** `items/server/hands.lua`: a weapon without a stored `data.mag` gets `categoryData.magSize` rounds (vanilla
  melee 1..15 gets 1). Busted cases cover the firearm, melee and stored-magazine paths.
- **C2** `auth`: the client sends `onAuthRequestReady` (remote, through `net.handler`) from `onClientResourceStart`,
  and the server prompts only then. The `onPlayerJoin` timer and the `onResourceStart` prompt loop are gone, so
  `restart auth` is covered by the clients restarting the script.
- **I1** `items/client/inventory.lua`: the held item is the first row (`[hand] …`, **Eat** for food, **Drop**), and the
  list refreshes whenever the held item changes.
- **I2** `items/server/hands.lua`: `Items.setWorn`/`Items.rebuildWorn` attach the worn bag to the player's back (root
  offset). Rebuilt on start/spawn, removed on death, quit and stop.
- **I2b** `items/server/containers.lua`: the wear `UPDATE` has a `NOT EXISTS` guard, so a second bag is 0 affected
  rows and never a logged 1062.
- **I3** `character`: `survival.woundsOnLoad(bleed)` gives a loaded character one wound when its bleed is above the
  new-spawn token bleed (0.0001), so relogging no longer cures bleeding. Busted covers both sides.
- The checklist steps 6, 7, 9 and 11 now exercise these fixes.
- **Minor items**, second pass:
  - 1: death drop passes `z - 0.9`.
  - 2: `character_death_drop` sets `despawn_at` from `loot.despawn_minutes`.
  - 3: a respawn needs a committed `character_death_drop`.
  - 4: one session per account (`ALREADY_ONLINE`).
  - 5: failed logins are counted per serial for 10 minutes.
  - 6: register/login stop with `GONE` when the player quit during bcrypt.
  - 7: the `share=1` wording is fixed in CLAUDE.md, the spec and `db.lua`.
  - 8: the client sends `onItemsRequestReady` on start and gets a fresh sync plus its held item.
  - 9: server-config README warns about `dev.open`.
  - 10: `survival.deathCause`.
  - 11: `character_flush` saves interior and dimension.
  - 12: HUD is hidden before the first stats and while dead.
  - 13: `net` buckets are per player and dropped on quit.
  - 14: `loot.roll_batch` is 100.
  - 15: docs fixed.
  - 16: tests added for `setHeld` weapons, `Character` death/respawn flows and the bag container. The weapons hit
    handler and the `toJSON` wrapping are still untested.
