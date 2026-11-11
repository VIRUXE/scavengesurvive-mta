# Staff map dashboard (http://nasa/ssmta)

LAN-only map of San Andreas: live players with their trails, past sessions with a scrubber, and every outdoor loot
spawn with whether an item lies there and which. Read-only; nothing here writes to the game or the database.

## Parts
- `resources/[scavengesurvive]/dashboard` (game server): writes `live.json` once a second with each spawned
  character's place and the last five minutes of trail. A file, not an HTTP export, because `dev`'s rcon trusts every
  account allowed to call exports.
- `character/server/tick.lua` + `character_flush`: record trail points into `character_track` (kept 30 days, purged
  by `ev_character_track_purge`) for the past-session view.
- `server.py`: JSON API on 127.0.0.1:8120 (`/api/live`, `/api/track`, `/api/sessions`, `/api/loot`, `/api/loot/<id>`).
- `web/`: the page (Leaflet from cdnjs, fonts and the radar image are local).

## Install
1. A SELECT-only database user:
   `CREATE USER 'ssmta_ro'@'127.0.0.1' IDENTIFIED BY '…';`
   `GRANT SELECT ON scavengesurvive.character_track, scavengesurvive.connection_log, scavengesurvive.characters,
   scavengesurvive.loot_spawns, scavengesurvive.loot_spawn_state, scavengesurvive.items TO 'ssmta_ro'@'127.0.0.1';`
2. `/etc/ssmta-dashboard.env` (mode 0640, group mta): `SSMTA_DB_USER=ssmta_ro`, `SSMTA_DB_PASS=…`.
3. `cp ssmta-dashboard.service /etc/systemd/system/ && systemctl enable --now ssmta-dashboard`.
4. nginx, inside the `server` blocks that answer to `nasa`:
   ```
   location /ssmta/       { allow 127.0.0.1; allow 192.168.0.0/16; allow 10.0.0.0/8; deny all;
                            alias /gta/sa/mta/servers/scavengesurvive/scavengesurvive-mta/ops/dashboard/web/; }
   location /ssmta/api/   { allow 127.0.0.1; allow 192.168.0.0/16; allow 10.0.0.0/8; deny all;
                            proxy_pass http://127.0.0.1:8120/api/; }
   location /ssmta/tiles/ { allow 127.0.0.1; allow 192.168.0.0/16; allow 10.0.0.0/8; deny all;
                            alias /var/www/nasa/ssmta/tiles/; expires 7d; }
   ```
   Reload with `nginx -t && systemctl reload nginx`.

## Terrain base map
Optional. Put a tile pyramid in `/var/www/nasa/ssmta/tiles/{z}/{x}/{y}.png`: zoom 0..4, 256 px tiles, the 6000 m
world square, row 0 along the north edge. Until it exists the page labels the option "Terrain (not installed)".

## Local check
`SSMTA_PORT=8121 SSMTA_DB_DEFAULTS_FILE=~/.my.cnf python3 server.py`; set `SSMTA_LIVE_FILE` to try other positions.
The loot state "no zone budget left" from the in-game overlay is not shown: it needs the game's in-memory allowance.
