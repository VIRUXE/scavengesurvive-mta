# Capture slow database queries

On nasa, enabled 2026-11-04 in `/etc/mysql/mariadb.conf.d/99-scavengesurvive-slow.cnf`:

```ini
[mariadb]
slow_query_log = ON
slow_query_log_file = /var/log/mysql/scavengesurvive-slow.log
long_query_time = 0.05
log_output = FILE
log_slow_verbosity = query_plan,explain
log_slow_disabled_statements =
log_slow_rate_limit = 1
min_examined_row_limit = 0
```

The same settings were applied globally without restarting MariaDB. A fresh connection's 75 ms
`SELECT SLEEP` was recorded with execution time, lock time, rows examined and EXPLAIN output.
MariaDB's configuration parser accepted the file. Existing `/etc/logrotate.d/mariadb` covers this
path (verified with logrotate's debug mode).

Session settings are inherited on connection creation. Game connections already open at activation
retain their previous settings until they reconnect. No connections were killed and no game resources
were restarted. Allow the next scheduled server restart to establish full gameplay capture; enabling
the global flag alone does not prove existing sessions are recording at 50 ms.

After representative gameplay with new connections:

```sh
sudo mariadb-dumpslow -s t -t 20 /var/log/mysql/scavengesurvive-slow.log
sudo mariadb-dumpslow -s c -t 20 /var/log/mysql/scavengesurvive-slow.log
```

Inspect frequent expensive statements, rows examined and query plans before proposing indexes. Calls
and their inner statements can both appear: do not add their timings together. Game `db.callFinished`
timings include the shared MTA queue wait; SQL log timings help distinguish database work from that wait.
The log may include query arguments, so keep its mysql-only permissions and avoid publishing raw records.

To disable capture immediately, run `SET GLOBAL slow_query_log=OFF;` and remove the config file to keep
it disabled on the next restart. Existing sessions with their own enabled setting may also require
reconnection. Performance Schema remains disabled; this capture uses the file log.
