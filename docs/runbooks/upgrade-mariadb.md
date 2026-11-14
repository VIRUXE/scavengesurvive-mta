# Upgrade MariaDB

**When:** moving the server to a newer MariaDB than its package source offers. Production and the dev box run
MariaDB 13.2.0 since 2026-11-14, a preview for which MariaDB publishes neither a Debian package nor a Windows MSI:
production runs the official Linux tarball, the dev box a build from source. The schema itself still loads on 13.1.1
(`item_create_many` needs 13.1's `JSON_TABLE ... FORMAT JSON`), so the version is a server choice, not a code
requirement, until a commit adopts 13.2-only syntax.

**Why 13.2:** MDEV-38975 keeps internal temporary tables that carry TEXT/JSON columns (`items.data`) in memory
instead of spilling them to Aria on disk. On 13.1 the inventory load (`items/server/containers.lua` `INVENTORY_SQL`)
and `item_data_flush` wrote a temp table to disk on every call (84% of production's temp tables went to disk).
Measured on a synthetic world of production's size (13.8k items, 3.9k containers), median ms:

| operation | dev box 13.1 → 13.2 | production 13.1 → 13.2 |
| --- | --- | --- |
| inventory load | 4.0 → 0.82 | 1.20 → 0.98 |
| `item_data_flush` x20 | 5.9 → 2.6 | 4.37 → 4.02 |
| everything else (world sync, drop/pickup, put/take, `item_world_move`) | unchanged | 4–8% faster |

Production gains less because Linux's page cache made the Aria spills cheap; what dominates there is the commit's
log flush (~2.8 ms per commit on its SSD).

**Prerequisites:** the new server's release checksum (`https://downloads.mariadb.org/rest-api/mariadb/<version>/`);
disk space for a full dump plus a cold copy of the datadir.

## Steps (Linux production, tarball)

1. Download the `linux-systemd-x86_64` tarball next to the old one, check its sha256 against the REST API, extract it
   under `/opt` and point `/opt/mariadb` at it (`ln -sfn`). `ldd /opt/mariadb/bin/mariadbd | grep 'not found'` must
   print nothing, and `lib/plugin` must hold every `provider_*` plugin the config loads (`provider_*.cnf`).
2. Check the config parses: `/opt/mariadb/bin/mariadbd --basedir=/opt/mariadb --lc-messages-dir=/opt/mariadb/share
   --plugin-dir=/opt/mariadb/lib/plugin --help --verbose` shows the expected `datadir`, `socket`, `event-scheduler`.
3. Full dump: `mariadb-dump --all-databases --routines --triggers --events --single-transaction > backup-<old>.sql`.
4. The systemd drop-in `/etc/systemd/system/mariadb.service.d/13.2-tarball.conf` blanks and replaces `ExecStart`
   with `/opt/mariadb/bin/mariadbd --basedir=/opt/mariadb --lc-messages-dir=/opt/mariadb/share
   --plugin-dir=/opt/mariadb/lib/plugin $MYSQLD_OPTS`, and blanks `ExecStartPost` (Debian's `debian-start` runs the
   packaged, older `mariadb-upgrade`). Hold the packaged server so apt does not restart it: `apt-mark hold
   mariadb-server mariadb-server-core mariadb-server-compat`.
5. Warn players (`say`): the game server keeps running. `lib/modules/db.lua` connects with `autoreconnect=1`, so a
   database restart costs ~30 s of refused item actions and `dbPoll failed; Lost connection` warnings, then every
   resource reconnects on its next query.
6. `systemctl stop mariadb`, `cp -a /var/lib/mysql /var/lib/mysql.<old>-backup`, `systemctl daemon-reload`,
   `systemctl start mariadb` (34 s in all on 2026-11-14).
7. `/opt/mariadb/bin/mariadb-upgrade`, then verify: `SELECT VERSION(), @@event_scheduler` (`ON`), no `[ERROR]` in
   `journalctl -u mariadb`, no new warning in `scripts.log` after the restart, and recent `characters.updated_at`.

## Steps (Windows dev box, from source)

1. Visual Studio with the C++ workload (its bundled CMake and Ninja do), and Bison:
   `winget install WinFlexBison.win_flex_bison`. Pass CMake the real `win_bison.exe` under
   `%LOCALAPPDATA%\Microsoft\WinGet\Packages\WinFlexBison*`: the WinGet `Links` shim cannot find Bison's `data/`.
2. From a VS developer shell: `cmake -S mariadb-<v> -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
   "-DCMAKE_INSTALL_PREFIX=C:/Program Files/MariaDB <major.minor>" -DWITH_UNIT_TESTS=OFF -DPLUGIN_DUCKDB=NO
   -DPLUGIN_ROCKSDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_CONNECT=NO -DPLUGIN_SPIDER=NO -DPLUGIN_COLUMNSTORE=NO`, then
   `cmake --build build` and, elevated, `cmake --install build`.
3. Dump every database, then, elevated, `mariadb-upgrade-service.exe --service=MariaDB` from the new `bin`: it
   repoints the existing service at the new binaries and upgrades its datadir in place. The datadir stays where the
   first install put it (`C:\Program Files\MariaDB 12.2\data` on the dev box), so never uninstall that version.

## Rollback

Production: delete the drop-in, `systemctl daemon-reload`, `apt-mark unhold` the server packages, stop MariaDB, move
the cold datadir copy back over `/var/lib/mysql`, start. Rows written since the upgrade are lost unless they are
replayed from a dump taken before the rollback. Dev box: `mariadb-upgrade-service` cannot go down a version; reinstall
the old server and restore the dump.

## Escalation

Repository owner: the database server, its config and the backups.
