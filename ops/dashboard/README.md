# Staff map dashboard (http://nasa/ssmta)

LAN-only map of San Andreas: live players with their trails, past sessions with a scrubber, outdoor loot spawns,
and a replay of what happened to their items. Read-only; nothing here writes to the game or the database.

## Parts
- `resources/[scavengesurvive]/dashboard` (game server): writes `live.json` once a second with each spawned
  character's place and the last five minutes of trail. A file, not an HTTP export, because `dev`'s rcon trusts every
  account allowed to call exports.
- `character/server/tick.lua` + `character_flush`: record trail points into `character_track` (kept 30 days, purged
  by `ev_character_track_purge`) for the past-session view.
- `server.py`: JSON API on 127.0.0.1:8120 (`/api/live`, `/api/track`, `/api/sessions`, `/api/loot`, `/api/loot/<id>`,
  `/api/loot-history?from=<unix>&to=<unix>`).
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

## Terrain base map (satellite)
Optional; the page makes it the default base map once `tiles/0/0/0.jpg` exists, and labels the option "Terrain (not
installed)" until then. `make_tiles.py` builds the pyramid (zoom 0..5, 256 px JPEG, row 0 north) from the
`satellite_tiles` folder of github.com/interactive-game-maps/grand_theft_auto_san_andreas, which is a fan render of
the game's art with no licence of its own, so keep the output on the LAN and out of git:

```
git clone --depth 1 --filter=blob:none --sparse <that repo> src && git -C src sparse-checkout set satellite_tiles
python3 -I ops/dashboard/make_tiles.py --source-tiles src/satellite_tiles --out /var/www/nasa/ssmta/tiles
```
Checked against the radar (docs/images/map/base.png): roads and coastlines coincide at zero offset.

## Player traces
Live trails and recorded sessions use cyan for on foot, yellow for driving, lime for riding (bikes, motorbikes,
quads and passengers), and pink for flying (all aircraft occupants). Lines have a dark outline, stay above loot
markers, and fade with age without changing their travel colour. Player dots and the session scrubber use the
same colours; the layer panel includes a key.

New points record the vehicle seat as well as its model, including stationary vehicle/seat changes. Live and
session points are `[x, y, z, interior, dimension, vehicleModel, unix, seat]`; seat 0 is the driver, positive seats
are passengers, and -1/null means no recorded seat. Older car/boat traces appear in bone as **Seat unknown**;
bikes and aircraft can still be identified by model. Sparse historical stops retain their existing labels.

Existing databases need `ALTER TABLE character_track ADD COLUMN vehicle_seat TINYINT UNSIGNED NULL AFTER vehicle`
and the updated `character_flush` procedure from `sql/schema.sql` before restarting the API and the `character`
and `dashboard` resources. The column is nullable so earlier traces remain readable.

## Loot timeline
Open **History → Loot timeline**, or click a loot point and choose **View loot timeline**. Choose a 1-hour,
6-hour, 24-hour or 7-day window ending at any past time, then play or drag the slider. Zone and spawn filters
restrict both the map and the event list; the event-type filter restricts the list. Clicking an event seeks to its
time and focuses its recorded outdoor ground position, or its original spawn when it has no known ground position.
The list shows up to 60 recent events plus upcoming events around the cursor. The chart shows spawns above the
line and removals below it; hover for counts or click a bar to seek.

`items FOR SYSTEM_TIME ALL` supplies the baseline and location transitions. The original spawn link is recovered
from earlier versions, so items remain traceable after pickup clears `loot_spawn_id`. Playback needs no further
database requests. Yellow points have loot at their original spawn; orange dots are dropped loot. Totals distinguish
items at their spawn, held by a character, in a container, and dropped elsewhere (including indoors). Items inside
a carried bag count as in a container, since ownership of containers is not versioned. This covers items originally
created at outdoor loot points, not vending stock, map boxes, supply drops, or their generated contents.

Historical cooldowns, empty rolls, deletion reasons, and carriers' positions are not recorded and are not inferred.
Empty replay points mean no recorded loot at that time, not that they were eligible to roll. Spawn geometry and
zone labels come from the current catalogue. “First recorded” distinguishes history beginning after an item's
creation from a known spawn. The endpoint rejects windows over 7 days or over 60,000 item versions rather than
silently truncating them. History cache entries are bounded; the existing SELECT-only DB account is sufficient.

## Local check
`SSMTA_PORT=8121 SSMTA_DB_DEFAULTS_FILE=~/.my.cnf python3 server.py`; set `SSMTA_LIVE_FILE` to try other positions.
The loot state "no zone budget left" from the in-game overlay is not shown: it needs the game's in-memory allowance.

Run replay boundary and API validation tests with `python3 -m unittest discover -s ops/dashboard -p 'test_*.py'`
from the repository root. Restart `ssmta-dashboard` after changing `server.py`; nginx serves `web/` directly.
