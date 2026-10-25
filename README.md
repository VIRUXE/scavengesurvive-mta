# Scavenge & Survive for MTA:SA

**PvP survival on a decayed San Andreas.** [Scavenge & Survive](https://github.com/Southclaws/ScavengeSurvive), the
SA-MP gamemode by Southclaws, rebuilt for MTA:SA 1.6 in Lua on MariaDB: one alive character, everything is a
physical item on the ground, wounds bleed, and death drops it all.

![MTA:SA 1.6](https://img.shields.io/badge/MTA%3ASA-1.6-2b5797?style=flat-square)
![Lua 5.1](https://img.shields.io/badge/Lua-5.1-000080?style=flat-square&logo=lua)
![MariaDB 13](https://img.shields.io/badge/MariaDB-13.0-003545?style=flat-square&logo=mariadb)
![Milestone](https://img.shields.io/badge/milestone-M9%20Live%20economy%20%26%20release-brightgreen?style=flat-square)
![Code: Unlicense](https://img.shields.io/badge/code-Unlicense-lightgrey?style=flat-square)
![Data: MPL-2.0 · Maps: CC BY-SA 4.0](https://img.shields.io/badge/data-MPL--2.0%20%C2%B7%20CC%20BY--SA%204.0-orange?style=flat-square)

![Fort Defiance around Grove Street in a sandstorm](docs/images/fort-defiance-sandstorm.jpg)

## What works today

| Milestone | Status | What you get |
| --- | :---: | --- |
| M0 Bootstrap & Data | ✅ | 302 item types, 15 loot tables, 11,062 loot points, 10 languages, 66 vehicle types and 2,017 vehicle points converted from upstream; schema, procedures and seeds applied by one script |
| M1 Auth & Character | ✅ | Register/login, permadeath, spawn skins rolled from upstream's 29 clothes types, hunger and bleeding ticks, death drops, anti-combat-log, SA-MP HUD (watch, hunger bar, key actions, brightness overlay, death screen) |
| M2 Items & Inventory | ✅ | Hands, 6-slot inventory, bags worn on the back, containers, food, SA-MP list dialogs; held items and bags on real bones with the SA-MP models |
| M3 Loot & World | ✅ | Loot rolling near players, all 221 upstream maps built client-side (23,211 objects), 7 server zone colshapes (`getZoneAt`, `playerZoneEntered/Left`), weather and a real-time clock (wild trees deferred) |
| M4 Weapons & Damage | ✅ | Server-authoritative wound model with calibre, ammo-type and distance falloff, magazines, reload (`R`) and hold-`N` unload, 3D bullet tracers, knockouts, handcuffs and disarm, anti-combat-log |
| M5 Vehicles | ✅ | Fuel simulation and drain, driver controls (Y engine, N lights), locks, crowbar lock-breaking, locksmith key cutting, bonnet repair stages, petrol can refuelling, trunk container dialogs, and trailers via /tow |
| M6 Crafting, Building, Apparel | ✅ | Apparel bone attachment (hats, masks, armour, holster), nine hats cut from the headgear skins as loot items worn on any skin ([review](docs/reviews/2026-10-25-cut-hats.md)), clothes items that change the skin, body preview & 6 gear tiles with live 3D item previews in the inventory UI, safebox & tent persistent containers, in-hand combine, ground construction, workbench crafting, defences with door swing poses, 12-key dx keypad with 4-digit code and plot pole 20m claimed territory protection |
| M7 Staff & Ops | ✅ | Staff levels 1-5 with 38 commands (`/acmds`), reports, mutes, freeze, spectate, duty, MariaDB bans by name/IP/serial, whitelist, action log, runbooks. Live-checked with one client (`docs/reviews/2026-10-23-m7-live.md`); the two-client steps (mute seen by the other player, online ban and kick, spectate, kick request) are pending |
| M8 Content & Polish | 🔶 | Done: supply drops and weapons caches (upstream's crate objects and 32-slot containers, persisted across restarts), chat modes (local 40 m / global / radio by frequency / admin) with the dx radio panel, house loot in the hollow houses, ziplines and ladders, character skills (saved per character, shorten crafting, construction and repair holds, Skills row in the inventory), ten languages with English fallback. Live-checked with one client (`docs/reviews/2026-10-23-m8-live.md`); open: the two-client parts (automatic drops, who hears what, relog persistence), the hand-held ladder climb and balancing |
| M9 Live economy & release | 🔶 | Done: scarcity-driven respawn for loot and vehicles (ADR 0001, #67: carrying capacity per category and zone, deficit-proportional refill, jittered cooldowns, no respawn near players, carried loot counts). Open: the two-client live checks (combat log #26, smoke steps 12 and 22-28; #55 is answered by measurement), balancing on the playtest, `v1.0.0` |

Progress is tracked in the [issues](https://github.com/VIRUXE/scavengesurvive-mta/issues) and the
[project board](https://github.com/users/VIRUXE/projects/3); each milestone is an epic there.

| ![A battered loot vehicle](docs/images/loot-vehicle-blista.jpg) | ![A world item with its label](docs/images/world-item-hotdog.jpg) |
| :---: | :---: |
| Loot vehicles spawn smoking, half-wrecked and almost out of fuel | Every item is an object on the ground, SA-MP models included |
| ![A hollow house replacing the vanilla one](docs/images/hollow-house-replacement.jpg) | ![The 14 spawn skins in body armour, pistol holstered](docs/images/apparel-body-threequarter.jpg) |
| Upstream's hollow houses replace the sealed vanilla models | The 14 spawn skins in body armour, each with its own upstream fit |

![Captain's cap across upstream's 14 spawn skins](docs/images/apparel-captainscap.jpg)

![The nine hats cut off the headgear skins, worn](docs/images/cut-hats.jpg)

Apparel is checked in the green-screen studio (`docs/dev-studio.md`): one ped, a fixed camera, every skin in a row.

## How it is built

- **One MTA resource per domain**, no prefix: `lib`, `data`, `models`, `maps`, `ui`, `auth`, `character`, `items`,
  `loot`, `vehicles`, `crafting`, `building`, `world`, `weapons`, `chat`, `hud`, `staff`, `dev`, `attachedit`. They
  share state only through MariaDB, so any resource can restart alone and rebuild from the database.
- **MariaDB does the heavy lifting.** Every item-graph move (pickup, drop, container put/take, death drop) is a
  stored procedure that returns `ok, code, payload`; positions are `POINT` columns with spatial indexes. The schema
  is one `sql/schema.sql` dumped from the database; there are no migration files.
- **Scarcity is a budget, not a timer.** Loot and vehicles have a carrying capacity (per zone for loot) that refills
  in proportion to what is missing, with per-point cooldowns and nothing respawning within 150 m of a player. What
  players carry still counts, so hoarding slows the whole server down (ADR 0001).
- **The dev server is driven from the shell.** `rcon.ps1` runs commands and key presses as any player, Lua,
  screenshots and the chat lines a client received (screenshots omit the chat box) over the `dev` resource's HTTP
  export; `/studio` puts a ped alone on a chroma-green set and
  `attachedit` tunes attachment offsets in game.
- **Static world on the client.** The 221 upstream map files become `createBuilding` calls spread over frames
  (about 1.3 s on join), with the 209 SA-MP-only object models shipped in the `models` resource.
- **Damage is server-authoritative.** The victim's client reports a hit; the server checks the shooter's held weapon,
  range and rate, computes the wound and applies it.
- **Pure logic is testable.** Formulas live in `shared/logic/*.lua` with no MTA calls, so busted runs them on plain
  Lua 5.1; converters and SQL procedures have pytest coverage, the SQL tests against a live MariaDB.

Design: `docs/superpowers/specs/` (Appendix A is upstream behaviour, Appendix B the verified MTA facts).
Decisions: `docs/adr/`. Conventions every contributor and agent follows: `CLAUDE.md`.

## Quick start (Windows)

1. `pwsh tools/setup-dev.ps1` — Lua 5.1 toolchain, stylua, Python deps.
2. MariaDB 13.0 as a local service (root, no password) and MTA:SA 1.6 client + server installed.
3. `pwsh server-config/run-local.ps1` — creates the database, applies `sql/schema.sql`, procedures, triggers, events and seeds, links the resources into the server
   and starts it. Connect to `127.0.0.1:22003`.
4. Give yourself staff rights: `mariadb -u root scavengesurvive -e "UPDATE accounts SET admin_level = 5 WHERE name = 'You'"`,
   relog, `/acmds` (`docs/staff-commands.md`).
5. Drive the running server without touching the console: `pwsh server-config/rcon.ps1 help` (players, resource
   restarts, chat commands and bound keys as any player, Lua, screenshots, `chat <player>` to read a client's replies).
   Details in `server-config/README.md`.

Before committing, the four local checks must pass (there is no CI; commits land on `main`):

```
.lua\bin\busted.bat tests/lua
.lua\bin\luacheck.bat resources
stylua --check resources
pytest -q
```

## Documentation map

| Where | What |
| --- | --- |
| `CLAUDE.md` | Conventions and rules (events, DB, state, style) |
| `docs/superpowers/specs/` | The port design, upstream digest and MTA facts |
| `docs/superpowers/plans/2026-09-27-mvp.md` | The MVP plan as executed |
| `docs/adr/` | Architecture decisions (0001: scarcity-driven respawn, accepted and implemented in #67) |
| `docs/reviews/` | Review and live-check records with what was found and fixed |
| `docs/mvp-smoke-checklist.md` | The playtest checklist, extended as features land |
| `docs/maps-census.md` | Generated: every upstream map object classified vanilla / SA-MP-only |
| `docs/ui-reference-samp.md` | Every SA-MP UI element with upstream geometry, footage evidence and its MTA recipe; gap list vs the current resources |
| `docs/languages-qa.md` | Generated per-language coverage: missing keys, untranslated values, placeholder mismatches; `/lang <code>` picks a language |
| `docs/staff-commands.md` | Staff levels, every command, upstream rules kept and deviations |
| `docs/dev-studio.md` | The green-screen studio: presets, rcon usage, how the apparel sheets are taken |
| `docs/PROJECT_README.md` | The GitHub project board: fields, views and how issues flow through milestones |
| `docs/runbooks/` | Start/stop/restart, schema changes, backup/restore, ban appeal, DB-down incident, release |
| `server-config/README.md` | Local server setup, HTTP rcon, dev and staff commands |
| `THIRD_PARTY_NOTICES.md` | Upstream data (MPL-2.0), maps (CC BY-SA 4.0), SA-MP models |

## Toolchain notes

`setup-dev.ps1` builds Lua 5.1.5 with hererocks' default target, which picks MSVC (`--target vs`) when Visual Studio
C++ Build Tools are installed (verified with Visual Studio Community 2026). Without MSVC, install a MinGW toolchain
(`winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT`), put its `mingw64\bin` on `PATH`, and run
`python -m hererocks .lua -l 5.1.5 -r latest --target mingw` before `setup-dev.ps1` (the script then switches
LuaRocks from hererocks' `MSVCR80` link default to `ucrt`; a native rock that still imports `MSVCR80.dll` fails to
load with "The specified module could not be found" — rebuild it with `.lua/bin/luarocks.bat build <rock> --force`).
MariaDB installs as a Windows service from winget: `winget install -e --id MariaDB.Server --override "/qn
SERVICENAME=MariaDB ADDLOCAL=ALL PORT=3306"` (root with no password, which is the project default). The MSI does not add
its `bin` to `PATH`; add it, since `run-local.ps1` and the smoke checklist call `mariadb` by name.

## Credits and licences

Scavenge & Survive is Copyright (C) Barnaby "Southclaws" Keene and the community that built its maps from 2008 to
2017. New code here is released under the Unlicense; converted upstream data stays MPL-2.0 and the map placements
CC BY-SA 4.0; the SA-MP object models belong to the SA-MP team. See `THIRD_PARTY_NOTICES.md`.
