# Separate Thirst Implementation Plan
**Goal:** Independent thirst and hunger with blue thirst above green hunger.
**Architecture:** Extend character survival/state/sync, drinking, MariaDB create/flush and HUD.
**Tech Stack:** Lua 5.1, MTA, MariaDB.
**Spec:** docs/superpowers/specs/2026-11-15-separate-thirst-design.md
- [x] Extend survival defaults, tick, death cause, character stat API, sync and save.
- [x] Route positive drinks to thirst; preserve negative food effects; hydrate tutorial starts.
- [x] Draw thirst and hunger beneath stock health.
- [x] Alter local characters table and create/flush routines, then dump schema.
- [x] Direct Lua checks, SQL rollback checks, luacheck and formatting.
Review focus: old character defaults, respawn persistence, duty/reauth protections, independent consumption and bar spacing. No test files per project instruction. RCON requires the specified live settings path.

Validation: direct Lua survival/drinking/geometry checks and SQL stored-procedure checks using temporary tables passed. Changed-file formatting passed; existing lint warnings remain (restartCharacter and four vehicle API references). Global formatting has preexisting failures in loot/staff. No RCON restart performed: the mandated /gta/sa/mta/servers/scavengesurvive/mods/deathmatch/settings.xml is absent on this Windows workspace.

Database rollout on other installations: stop character writes, back up, run ALTER TABLE characters ADD COLUMN IF NOT EXISTS thirst FLOAT NOT NULL DEFAULT 80 AFTER food; apply the updated character_create and character_flush routines from sql/schema.sql, then restart character, items, tutorial and hud together. Existing-table columns are not added by sqltool apply. Local database already updated.
