# Project instructions

Use only `server-config/rcon.ps1` for RCON commands. Do not use custom HTTP clients, curl, or alternative RCON wrappers.

On this server, invoke it with the live settings file:

```bash
pwsh -NoProfile -File server-config/rcon.ps1 -Settings /gta/sa/mta/servers/scavengesurvive/mods/deathmatch/settings.xml <command>
```
