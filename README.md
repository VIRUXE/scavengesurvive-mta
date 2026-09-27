# scavengesurvive-mta
Scavenge & Survive — the SA-MP PvP survival gamemode — rebuilt for MTA:SA 1.6 with MariaDB.
Status: MVP in progress. Design: `docs/superpowers/specs/`. Plan: `docs/superpowers/plans/`.

## Quick start (Windows)
1. `pwsh tools/setup-dev.ps1`
2. MariaDB 12.x running locally; MTA:SA 1.6 client + server installed.
3. `pwsh server-config/run-local.ps1`, then connect to `127.0.0.1:22003`.

## Toolchain notes
`setup-dev.ps1` builds Lua 5.1.5 with hererocks' default target, which picks MSVC (`--target vs`) when Visual Studio
C++ Build Tools are installed (verified with Visual Studio Community 2026). Without MSVC, install a MinGW toolchain
(`winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT`) and run
`python -m hererocks .lua -l 5.1.5 -r latest --target mingw` before `setup-dev.ps1`.
