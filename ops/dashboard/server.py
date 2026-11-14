#!/usr/bin/env python3
"""Read-only JSON API behind the staff map (http://nasa/ssmta). Listens on 127.0.0.1 only; nginx proxies /ssmta/api/ here.

    live      the dashboard resource's live.json (positions once a second) plus each player's session start
    track     one character's or account's trail points from character_track
    sessions  past sessions from connection_log, with how many trail points each has
    loot      every outdoor loot spawn with its state and the items lying there, one compact row per spawn

Configuration (environment): SSMTA_DB_HOST, SSMTA_DB_PORT, SSMTA_DB_USER, SSMTA_DB_PASS, SSMTA_DB_NAME,
SSMTA_DB_DEFAULTS_FILE (a my.cnf-style file instead of user/pass), SSMTA_LIVE_FILE, SSMTA_PORT.
The database user only needs SELECT (see README.md). Serials and IPs are never selected.
"""
from __future__ import annotations

import gzip
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pymysql

ROOT = Path(__file__).resolve().parents[2]
LIVE_FILE = Path(os.environ.get("SSMTA_LIVE_FILE") or ROOT / "resources" / "[scavengesurvive]" / "dashboard" / "live.json")
PORT = int(os.environ.get("SSMTA_PORT", "8120"))
STALE_AFTER = 5  # seconds without a new snapshot before the page is told the server is not live
TRACK_LIMIT = 20000
LOOT_HISTORY_LIMIT = 60000

# state codes in /api/loot rows
READY, LYING, TAKEN, COOLDOWN, DISABLED = 0, 1, 2, 3, 4
STATE_NAMES = ["empty", "item lying", "taken", "cooldown", "disabled"]


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status, self.message = status, message


def connect():
    kwargs = dict(
        host=os.environ.get("SSMTA_DB_HOST", "127.0.0.1"),
        port=int(os.environ.get("SSMTA_DB_PORT", "3306")),
        database=os.environ.get("SSMTA_DB_NAME", "scavengesurvive"),
        charset="utf8mb4",
        connect_timeout=3,
        read_timeout=15,
        autocommit=True,
    )
    defaults = os.environ.get("SSMTA_DB_DEFAULTS_FILE")
    if defaults:
        kwargs["read_default_file"] = defaults
    else:
        kwargs["user"] = os.environ.get("SSMTA_DB_USER", "")
        kwargs["password"] = os.environ.get("SSMTA_DB_PASS", "")
    return pymysql.connect(**kwargs)


def query(sql: str, args=()):
    try:
        with connect() as c, c.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchall()
    except pymysql.MySQLError as e:
        raise ApiError(503, "database unavailable") from e


class Cache:
    """One value per key for `ttl` seconds; the lock keeps a burst of requests to one database query."""

    def __init__(self):
        self.lock = threading.Lock()
        self.items: dict = {}

    def get(self, key, ttl, make):
        with self.lock:
            hit = self.items.get(key)
            if hit and time.monotonic() - hit[0] < ttl:
                return hit[1]
            value = make()
            # History windows are user-selected; do not retain an unbounded number of large replays.
            if len(self.items) >= 32 and key not in self.items:
                del self.items[min(self.items, key=lambda k: self.items[k][0])]
            self.items[key] = (time.monotonic(), value)
            return value


cache = Cache()
last_good = {"snapshot": None}


def read_snapshot():
    """live.json as the game server writes it: [{"at": s, "players": [...]}] (toJSON's outer array). It is rewritten in
    place every second, so a reader can catch it half written: retry once, then serve the last snapshot that parsed."""
    for attempt in range(2):
        try:
            data = json.loads(LIVE_FILE.read_text(encoding="utf-8"))
            snap = data[0] if isinstance(data, list) else data
            if isinstance(snap, dict) and "players" in snap:
                if not isinstance(snap["players"], list):
                    snap["players"] = []
                last_good["snapshot"] = snap
                return snap
        except (OSError, ValueError, IndexError):
            pass
        if attempt == 0:
            time.sleep(0.05)
    return last_good["snapshot"]


def session_starts(char_ids):
    """char id -> unix time its account's open session began; {} when the database is down (positions still serve)."""
    if not char_ids:
        return {}
    marks = ",".join(["%s"] * len(char_ids))
    sql = (
        "SELECT c.id, UNIX_TIMESTAMP(MAX(l.joined_at)) FROM characters c "
        "JOIN connection_log l ON l.account_id = c.account_id AND l.left_at IS NULL "
        f"WHERE c.id IN ({marks}) GROUP BY c.id"
    )
    key = ("starts", tuple(sorted(char_ids)))
    try:
        rows = cache.get(key, 10, lambda: query(sql, tuple(char_ids)))
    except ApiError:
        return {}
    return {int(r[0]): int(r[1]) for r in rows}


def api_live(params):
    keep = clamp(params.get("trail"), 0, 3600, 300)
    snap = read_snapshot()
    if snap is None:
        return {"at": None, "live": False, "players": []}
    now = time.time()
    starts = session_starts([int(p["char"]) for p in snap["players"] if isinstance(p.get("char"), int)])
    for p in snap["players"]:
        p["sessionStart"] = starts.get(p.get("char"))
        p["trail"] = [pt for pt in p.get("trail", []) if len(pt) >= 7 and pt[6] >= now - keep]
    at = snap.get("at")
    return {"at": at, "live": at is not None and now - at <= STALE_AFTER, "players": snap["players"]}


def clamp(value, low, high, default):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return default
    return max(low, min(high, n))


def need_int(params, name):
    try:
        return int(params[name])
    except (KeyError, TypeError, ValueError):
        raise ApiError(400, f"{name} must be an integer")


def downsample(rows, limit):
    if len(rows) <= limit:
        return rows
    stride = -(-len(rows) // limit)
    out = rows[::stride]
    if out[-1] is not rows[-1]:
        out.append(rows[-1])
    return out


def sparse_points(who, who_id, start, end):
    """Where the database knows a character was when there is no full trail: each vehicle enter/exit (position and
    time) and the character's last saved position (where they logged off, or died). Rows are shaped like trail points
    plus a label: [x, y, z, interior, dimension, vehicle, unix, label]. Characters never moved from (0, 0) are skipped
    (a fresh row, not a place)."""
    cond = "c.id = %s" if who == "char_id" else "c.account_id = %s"
    sql = (
        "SELECT v.x, v.y, v.z, 0, 0, 0, UNIX_TIMESTAMP(v.at), CONCAT('vehicle ', v.action) AS label "
        "FROM vehicle_events v JOIN characters c ON c.id = v.character_id "
        f"WHERE {cond} AND v.at >= FROM_UNIXTIME(%s) AND v.at <= FROM_UNIXTIME(%s) "
        "UNION ALL "
        "SELECT c.x, c.y, c.z, c.interior, c.dimension, 0, UNIX_TIMESTAMP(c.updated_at), "
        "IF(c.alive = 1, 'last saved position', 'died here') FROM characters c "
        f"WHERE {cond} AND c.updated_at >= FROM_UNIXTIME(%s) AND c.updated_at <= FROM_UNIXTIME(%s) "
        "ORDER BY 7"
    )
    rows = query(sql, (who_id, start, end, who_id, start, end))
    return [
        [round(r[0], 1), round(r[1], 1), round(r[2], 1), r[3], r[4], r[5], float(r[6]), r[7]]
        for r in rows
        if abs(r[0]) > 0.5 or abs(r[1]) > 0.5
    ]


def api_track(params):
    start, end = need_int(params, "from"), need_int(params, "to")
    if end < start:
        raise ApiError(400, "to is before from")
    if "char" in params:
        who, who_id = "char_id", need_int(params, "char")
    else:
        who, who_id = "account_id", need_int(params, "account")
    sql = (
        "SELECT x, y, z, interior, dimension, COALESCE(vehicle, 0), UNIX_TIMESTAMP(at), vehicle_seat FROM character_track "
        f"WHERE {who} = %s AND at >= FROM_UNIXTIME(%s) AND at <= FROM_UNIXTIME(%s) ORDER BY at"
    )
    rows = [[round(r[0], 1), round(r[1], 1), round(r[2], 1), r[3], r[4], r[5], float(r[6]), r[7]] for r in query(sql, (who_id, start, end))]
    total = len(rows)
    return {"points": downsample(rows, TRACK_LIMIT), "total": total, "sparse": sparse_points(who, who_id, start, end)}


def like_prefix(text):
    return re.sub(r"([\\%_])", r"\\\1", text) + "%"


def api_sessions(params):
    days = clamp(params.get("days"), 1, 30, 7)
    name = (params.get("name") or "").strip()[:24]
    where, args = "l.joined_at >= NOW() - INTERVAL %s DAY", [days]
    if name:
        where += " AND l.name LIKE %s"
        args.append(like_prefix(name))
    sql = (
        "SELECT l.id, l.name, l.account_id, UNIX_TIMESTAMP(l.joined_at), UNIX_TIMESTAMP(l.left_at), "
        "COUNT(t.at), GROUP_CONCAT(DISTINCT t.char_id), "
        "(SELECT COUNT(*) FROM vehicle_events v JOIN characters c ON c.id = v.character_id "
        " WHERE c.account_id = l.account_id AND v.at >= l.joined_at AND v.at <= COALESCE(l.left_at, NOW())) + "
        "(SELECT COUNT(*) FROM characters c WHERE c.account_id = l.account_id AND (c.x <> 0 OR c.y <> 0) "
        " AND c.updated_at >= l.joined_at AND c.updated_at <= COALESCE(l.left_at, NOW())) AS known "
        "FROM connection_log l "
        "LEFT JOIN character_track t ON t.account_id = l.account_id AND t.at >= l.joined_at "
        "AND t.at <= COALESCE(l.left_at, NOW()) "
        f"WHERE {where} GROUP BY l.id ORDER BY l.joined_at DESC LIMIT 200"
    )
    out = []
    for r in query(sql, tuple(args)):
        out.append(
            {
                "id": r[0],
                "name": r[1],
                "accountId": r[2],
                "joinedAt": int(r[3]),
                "leftAt": int(r[4]) if r[4] is not None else None,
                "points": r[5],
                "known": int(r[7]),
                "charIds": [int(c) for c in r[6].split(",")] if r[6] else [],
            }
        )
    return out


# The per-spawn state mirrors loot/server/overlay.lua (disabled -> items out -> cooldown). Its fourth state, "no zone
# budget left", needs the game's in-memory allowance and is not shown here. One query: items are grouped once, not
# looked up per spawn.
LOOT_SQL = (
    "SELECT s.id, s.x, s.y, s.table_name, s.zone, s.enabled, TIMESTAMPDIFF(SECOND, NOW(), st.next_roll_at), "
    "COALESCE(o.total, 0), o.lying "
    "FROM loot_spawns s LEFT JOIN loot_spawn_state st ON st.spawn_id = s.id "
    "LEFT JOIN (SELECT loot_spawn_id, COUNT(*) AS total, "
    "GROUP_CONCAT(CASE WHEN holder_char_id IS NULL AND container_id IS NULL THEN type_uname END "
    "ORDER BY id SEPARATOR ', ') AS lying FROM items WHERE loot_spawn_id IS NOT NULL GROUP BY loot_spawn_id) o "
    "ON o.loot_spawn_id = s.id WHERE s.interior = 0 AND s.dimension = 0"
)


def loot_state(enabled, due, total, lying):
    if enabled != 1:
        return DISABLED
    if total > 0:
        return LYING if lying else TAKEN
    if (due or 0) > 0:
        return COOLDOWN
    return READY


def build_loot():
    spawns, counts = [], [0] * len(STATE_NAMES)
    for r in query(LOOT_SQL):
        state = loot_state(r[5], r[6], r[7], r[8])
        counts[state] += 1
        spawns.append([r[0], round(r[1], 1), round(r[2], 1), state, r[3], r[4], r[8] or ""])
    indoor = query("SELECT COUNT(*) FROM loot_spawns WHERE interior <> 0 OR dimension <> 0")[0][0]
    return {
        "states": STATE_NAMES,
        "counts": dict(zip(STATE_NAMES, counts)),
        "skippedIndoor": indoor,
        "spawns": spawns,
        "at": int(time.time()),
    }


def api_loot(_params):
    return cache.get("loot", 15, build_loot)


def api_loot_one(spawn_id):
    rows = query(
        "SELECT s.id, s.x, s.y, s.z, s.table_name, s.weight, s.size, s.zone, s.enabled, "
        "TIMESTAMPDIFF(SECOND, NOW(), st.next_roll_at) FROM loot_spawns s "
        "LEFT JOIN loot_spawn_state st ON st.spawn_id = s.id WHERE s.id = %s",
        (spawn_id,),
    )
    if not rows:
        raise ApiError(404, "no such loot spawn")
    s = rows[0]
    items = query(
        "SELECT id, type_uname, hitpoints, holder_char_id IS NULL AND container_id IS NULL FROM items "
        "WHERE loot_spawn_id = %s ORDER BY id",
        (spawn_id,),
    )
    lying = [{"id": i[0], "type": i[1], "hitpoints": i[2]} for i in items if i[3]]
    state = loot_state(s[8], s[9], len(items), bool(lying))
    return {
        "id": s[0],
        "x": round(s[1], 1),
        "y": round(s[2], 1),
        "z": round(s[3], 1),
        "table": s[4],
        "weight": s[5],
        "size": s[6],
        "zone": s[7],
        "state": STATE_NAMES[state],
        "cooldownSeconds": max(0, int(s[9] or 0)),
        "lying": lying,
        "takenCount": len(items) - len(lying),
    }


# The spawn link is cleared on pickup, but system-versioned items retain the original link. Join through that
# history so carried, stored, dropped and deleted loot remains traceable. No new game logging or DB writes.
LOOT_HISTORY_SQL = (
    "SELECT i.id, i.type_uname, origin.spawn_id, s.zone, i.loot_spawn_id, i.holder_char_id, i.container_id, "
    "i.x, i.y, i.interior, i.dimension, UNIX_TIMESTAMP(i.created_at), "
    "UNIX_TIMESTAMP(i.row_start), UNIX_TIMESTAMP(i.row_end) "
    "FROM items FOR SYSTEM_TIME ALL AS i "
    "JOIN (SELECT id, MIN(loot_spawn_id) AS spawn_id FROM items FOR SYSTEM_TIME ALL "
    "WHERE loot_spawn_id IS NOT NULL GROUP BY id) origin ON origin.id = i.id "
    "JOIN loot_spawns s ON s.id = origin.spawn_id "
    "WHERE s.interior = 0 AND s.dimension = 0 AND i.row_start <= FROM_UNIXTIME(%s) "
    "AND i.row_end >= FROM_UNIXTIME(%s) ORDER BY i.id, i.row_start "
    f"LIMIT {LOOT_HISTORY_LIMIT + 1}"
)


def history_location(row):
    """Only changes of location matter; HP/data/rotation updates are not loot movements."""
    if row[5] is not None:
        return {"place": "carried", "holder": row[5]}
    if row[6] is not None:
        return {"place": "stored", "container": row[6]}
    return {
        "place": "spawn" if row[4] is not None else "ground",
        "x": round(row[7], 2) if row[7] is not None else None,
        "y": round(row[8], 2) if row[8] is not None else None,
        "interior": row[9] or 0,
        "dimension": row[10] or 0,
    }


def history_action(previous, state):
    if state["place"] == "carried":
        return "transferred" if previous["place"] == "carried" else "picked up"
    if state["place"] == "stored":
        return "stored"
    return "dropped" if previous["place"] in ("carried", "stored") else "moved"


def build_loot_history(rows, start, end):
    items, initial, events = [], [], []
    previous, previous_end, item_id = None, None, None
    for row in rows:
        at, until = float(row[12]), float(row[13])
        state = history_location(row)
        if row[0] != item_id:
            if previous is not None and start < previous_end <= end:
                events.append({"at": previous_end, "item": item_id, "kind": "removed", "state": None})
            item_id, previous, previous_end = row[0], None, None
            items.append({"id": item_id, "type": row[1], "spawn": row[2], "zone": row[3]})
        if at <= start < until:
            initial.append({"item": item_id, "state": state})
        if start < at <= end:
            if previous is None:
                kind = "spawned" if abs(at - float(row[11])) < 2 else "first recorded"
            else:
                kind = history_action(previous, state)
            if previous != state:
                events.append({"at": at, "item": item_id, "kind": kind, "state": state})
        previous, previous_end = state, until
    if previous is not None and start < previous_end <= end:
        events.append({"at": previous_end, "item": item_id, "kind": "removed", "state": None})
    events.sort(key=lambda event: (event["at"], event["item"]))
    return {"from": start, "to": end, "items": items, "initial": initial, "events": events}


def api_loot_history(params):
    start, end = need_int(params, "from"), need_int(params, "to")
    if start < 0 or end <= start or end - start > 7 * 86400:
        raise ApiError(400, "choose a time window between 1 second and 7 days")
    end = min(end, int(time.time()))
    if end <= start:
        raise ApiError(400, "choose a time window in the past")

    def make():
        rows = query(LOOT_HISTORY_SQL, (end, start))
        if len(rows) > LOOT_HISTORY_LIMIT:
            raise ApiError(413, "too much history; choose a shorter time window")
        return build_loot_history(rows, start, end)

    return cache.get(("loot-history", start, end), 30, make)


ROUTES = {
    "/api/live": api_live, "/api/track": api_track, "/api/sessions": api_sessions,
    "/api/loot": api_loot, "/api/loot-history": api_loot_history,
}


class Handler(BaseHTTPRequestHandler):
    server_version = "ssmta-dashboard"

    def log_message(self, *_args):  # nginx has the access log; nothing here may carry a query string
        pass

    def reply(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        headers = {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"}
        if len(body) > 1024 and "gzip" in self.headers.get("Accept-Encoding", ""):
            body = gzip.compress(body, 5)
            headers["Content-Encoding"] = "gzip"
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        params = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            path = url.path.rstrip("/")
            match = re.fullmatch(r"/api/loot/(\d+)", path)
            if match:
                payload = api_loot_one(int(match.group(1)))
            elif path in ROUTES:
                payload = ROUTES[path](params)
            else:
                raise ApiError(404, "not found")
            self.reply(200, payload)
        except ApiError as e:
            self.reply(e.status, {"error": e.message})
        except Exception:  # never a stack trace to the browser
            self.reply(500, {"error": "internal error"})


def main():
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
