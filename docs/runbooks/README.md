# Runbooks

Operational procedures for a Scavenge & Survive MTA server (local dev box today; the same steps apply to a
production host with the paths changed). Each runbook says when to use it, what you need, the steps, how to roll
back and who to escalate to. There is no CI and no deploy pipeline by project rule: releases are tags on `main`
cut after the local checks (`docs/runbooks/release.md`).

| Runbook | Use it when |
| --- | --- |
| [start-stop-restart.md](start-stop-restart.md) | bringing the server up or down, restarting one resource |
| [migrate-database.md](migrate-database.md) | a commit added a file under `sql/` |
| [backup-restore.md](backup-restore.md) | nightly backup, or restoring after data loss |
| [ban-appeal.md](ban-appeal.md) | a player asks why they cannot join, or asks to be unbanned |
| [incident-db-down.md](incident-db-down.md) | MariaDB is unreachable while the server runs |
| [release.md](release.md) | tagging a version from `main` |

Conventions: `$MTA` is the server directory (`C:\Program Files (x86)\MTA San Andreas 1.6\server`), `$DM` is
`$MTA\mods\deathmatch`, the repo is `scavengesurvive-mta`. `rcon.ps1` means `pwsh server-config/rcon.ps1`.
