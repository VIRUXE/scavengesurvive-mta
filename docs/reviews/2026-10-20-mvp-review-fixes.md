# Fixes for the MVP final review (2026-10-20)

Closes the five items the [final review](2026-09-27-mvp-final-review.md) listed as blocking the two-client playtest.
Each entry names the ruling where the review offered a choice.

| Item | Fix | Test |
| --- | --- | --- |
| C1 firearms held with 0 ammo | `Items.ammoFor`: `data.mag` when present, else the type's `magSize`, else 1; vanilla melee ids 1–15 always 1. No ammo model yet, so a firearm is a full magazine until one exists. | `items_server_spec` "gives a held firearm a full magazine" |
| C2 login prompt lost in the join race | The prompt is sent from `onPlayerResourceStart` for `auth` (also fires for every connected player when `auth` restarts), replacing the 1 s timer and the `onResourceStart` loop. No new event. | smoke step 2 |
| I1 held food not usable from **H** | Ruling: code, not checklist. The list leads with a `[hand]` row (Eat for food, Put away, Drop). The client re-requests the list when the held item changes while a list is open. | smoke step 7 |
| I2 worn bag invisible | Ruling: code. `Items.setWorn` attaches the bag model at a player-relative back offset; `Items.rebuildCarried` restores held + bag on spawn and restart; cleared on death, quit and stop. Bone attachment stays post-MVP. | smoke step 6 |
| I2b second bag logs `ERROR` 1062 | New `bag_wear` procedure (READ COMMITTED, `FOR UPDATE` on the worn row) returns `BAG_SLOT_USED` / `NOT_HELD` instead of tripping `uq_items_holder_kind`. | `test_item_graph.py::test_wear_bag_refuses_a_second_one_without_an_error` |
| I3 relog cures bleeding | `survival.loadWounds(bleed, isNew)`: a loaded row with `bleed > 0` starts with one wound; a new character's seed bleed is not a wound. Persisting the count stays post-MVP. | `character_survival_spec` "keeps a loaded character bleeding" |

## Toolchain

- `tests/tools/test_zones.py` used `Path.read_text(newline=...)`, which is Python 3.13 only while `pyproject.toml` allows
  3.11; it now opens the fixture with `newline=""` through `Path.open`.
- `setup-dev.ps1` sets `variables.MSVCRT = ucrt` for MinGW builds (see README "Toolchain notes").
- Verified against MariaDB 13.0.2 (the current release) as well as the 12.2 the spec names.

## Docs

- `CLAUDE.md` names MariaDB 13.0 (the current release; 12.2 also passes the SQL tests) and the `.bat` check commands.
- Smoke checklist: step 10 says "run" (no vehicles in the MVP) and the setup line says the two clients need different
  MTA nicknames, since the account name is the nickname (review minor 15).
- Not touched: the spec and plan still carry the original `data.mag or 0` line and the "share=1 matches" wording the
  review called stale; they are the historical record and this file is the correction.

## Live playtest, 2026-10-21 (one client, driven through `rcon.ps1`)

| Check | Result |
| --- | --- |
| Step 1 boot | `212 loaded, 0 failed`, ready, no `ERROR`, 5 DB connections |
| Step 2 login prompt (C2) | window arrived on first join and on every rejoin |
| C1 ammo | held M9: weapon 22, 10 rounds in clip |
| I2 / I2b bag | `Satchel=bag` in DB, model 363 attached at the back offset (screenshot), second bag never needed |
| I1 eat from hand | `[hand] Hot Dog` → Eat: item destroyed, food 77.4 → 100 |
| I3 bleeding survives reload | `rr character`: 0.298 → 0.297 with `wounds = 1`; real relog: 0.277 → 0.273 with `wounds = 1` |

Found and fixed on the way:

- **Y also opened team chat.** MTA binds `y` to `chatbox teamsay` by default and `hud` only binds `putaway` when the key is
  free, so one press did both. `hud` now unbinds the chat on start and restores it on stop (the gamemode has no teams).
- `rcon screenshot <player>` was added for the bag check. Two lessons: the function is `takePlayerScreenShot` (capital S;
  a wrong name made the server file a *pending, denying* `aclrequest` that outlived the typo), and its default upload cap
  is 5 kB/s, so a 1080p frame took a minute until the call passed a higher bandwidth. `run-local.ps1` grants the right
  in the `ScavengeSurvive` ACL so no request is ever pending.
- The HUD draws on the black screen before the camera fades in (review minor 12), seen in a screenshot taken 9 s after
  join. Still open.
- **Attached item models are not at their correct offsets (open, next up).** `items/server/hands.lua` attaches the held
  object and the worn bag to the *player element* (`attachElements` with a fixed `HAND_OFFSET` / `BACK_OFFSET`), so items
  float beside the hip instead of sitting in the hand or on the back, and they do not follow animations. Upstream
  positions every item with SA-MP bone attachments, and the converted data already carries `boneid`, `attx/y/z` and
  `attrx/y/z` per type (the spec's "apparel via bone attach", M6). Plan: client-side bone attachment driven by
  `getElementBoneMatrix` (MTA 1.6, `onClientPedsProcessed`), server publishing attachment details to clients; map
  SA-MP bone ids to GTA bone ids; worn bags on the spine with their own offsets.
