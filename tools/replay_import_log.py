"""Backfill and tail replay_event from the game log (the /replay staff command, docs/superpowers/specs/2026-11-23-replay-design.md).

Usage: python -m tools.replay_import_log [--log PATH] [--state FILE] [--from-start] [--dry-run]
The prod server does not run `logs` (no Loki), so every game event is only a line of mods/deathmatch/logs/server.log:
`[yy-mm-dd HH:MM:SS] [resource] kind {json}`. This reads the kinds listed in
resources/[scavengesurvive]/replay/shared/logic/kinds.lua and writes them through `replay_event_save`. A row's `sig`
is the md5 of the line's time and JSON text, a unique key, so running it again (or twice at once) never doubles anything.
With --state the byte offset reached is kept in that file and the next run reads only the new lines (a smaller
or replaced file starts over); that is how the systemd timer in ops/replay keeps the table current.
Connection: the game's own *lib.db_* settings in mods/deathmatch/settings.xml (SSMTA_SETTINGS), else SSMTA_DB_USER /
SSMTA_DB_PASS / SSMTA_DB_HOST in the environment, else the client options in /root/.my.cnf (SSMTA_DB_CNF).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parents[1]
KINDS_FILE = ROOT / "resources" / "[scavengesurvive]" / "replay" / "shared" / "logic" / "kinds.lua"
DEFAULT_LOG = ROOT.parent / "mods" / "deathmatch" / "logs" / "server.log"
GAME_SETTINGS = ROOT.parent / "mods" / "deathmatch" / "settings.xml"
LINE = re.compile(r"^\[(\d\d)-(\d\d)-(\d\d) (\d\d:\d\d:\d\d)\] \[([^\]]+)\] ([A-Za-z0-9_.]+) (\{.*\})\s*$")
KIND_KEY = re.compile(r'^\s*\["([A-Za-z0-9_.]+)"\]\s*=\s*\{', re.M)
BATCH = 1500

# the character an event happened to, besides the one that did it (first one present wins)
OTHER_KEYS = ("to_character_id", "victim_character_id", "target_character_id", "killer_character_id")
# envelope keys that become columns; everything else lands in `data`
COLUMN_KEYS = {"level", "resource", "kind", "x", "y", "z", "int", "dim", "character_id", "account_id", "item_id",
               "vehicle_id", "player", "zone", "serial", "ip"}
SECRET_KEYS = {"passcode", "keypad", "token", "password", "serial", "ip", "pass", "code_text", "email", "combo"}


def load_kinds(path: Path = KINDS_FILE) -> set[str]:
    return set(KIND_KEY.findall(path.read_text(encoding="utf-8")))


def clean(value):
    """Drop anything secret from a nested value."""
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items() if k.lower() not in SECRET_KEYS}
    if isinstance(value, list):
        return [clean(v) for v in value]
    return value


def number(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def event_row(ts: str, kind: str, text: str):
    """One replay_event_save row from a log line's JSON, or None when it is not valid JSON."""
    try:
        fields = json.loads(text)
    except ValueError:
        return None
    if not isinstance(fields, dict):
        return None
    other = next((fields[k] for k in OTHER_KEYS if number(fields.get(k)) is not None), None)
    data = {k: clean(v) for k, v in fields.items() if k not in COLUMN_KEYS and k.lower() not in SECRET_KEYS}
    if "player" in fields:
        data["player"] = fields["player"]
    if fields.get("code") == "OK":
        data.pop("code", None)
    if fields.get("ok") is True:
        data.pop("ok", None)
    row = {
        "at": ts,
        "kind": kind,
        "char": number(fields.get("character_id")),
        "other": number(other),
        "account": number(fields.get("account_id")),
        "item": number(fields.get("item_id")),
        "vehicle": number(fields.get("vehicle_id")),
        "x": number(fields.get("x")),
        "y": number(fields.get("y")),
        "z": number(fields.get("z")),
        "int": number(fields.get("int")) or 0,
        "dim": number(fields.get("dim")) or 0,
        "sig": hashlib.md5(f"{ts} {text}".encode("utf-8")).hexdigest()[:16],
        "data": data or None,
    }
    return row


def game_settings(path: str) -> dict:
    """The *lib.db_* settings the game itself connects with (mods/deathmatch/settings.xml)."""
    import xml.etree.ElementTree as ET

    out = {}
    try:
        for el in ET.parse(path).getroot().iter("setting"):
            name = el.get("name", "")
            if name.startswith("*lib.db_"):
                out[name[len("*lib.db_"):]] = el.get("value", "")
    except (OSError, ET.ParseError):
        pass
    return out


def connect():
    user = os.environ.get("SSMTA_DB_USER")
    game = game_settings(os.environ.get("SSMTA_SETTINGS", str(GAME_SETTINGS)))
    if not user and game.get("user"):
        return pymysql.connect(host=game.get("host") or "127.0.0.1", user=game["user"], password=game.get("pass", ""),
                               database=game.get("name") or "scavengesurvive", autocommit=True, charset="utf8mb4")
    if user:
        return pymysql.connect(host=os.environ.get("SSMTA_DB_HOST", "127.0.0.1"), user=user,
                               password=os.environ.get("SSMTA_DB_PASS", ""), database="scavengesurvive",
                               autocommit=True, charset="utf8mb4")
    return pymysql.connect(read_default_file=os.environ.get("SSMTA_DB_CNF", "/root/.my.cnf"),
                           database="scavengesurvive", autocommit=True, charset="utf8mb4")


def read_state(path: Path | None, size: int, inode: int) -> int:
    if not path or not path.exists():
        return 0
    try:
        st = json.loads(path.read_text())
    except ValueError:
        return 0
    if st.get("inode") != inode or st.get("offset", 0) > size:
        return 0
    return int(st["offset"])


def run(args) -> int:
    kinds = load_kinds()
    log = Path(args.log)
    stat = log.stat()
    state = Path(args.state) if args.state else None
    start = 0 if args.from_start else read_state(state, stat.st_size, stat.st_ino)
    seen = kept = skipped = bad = 0
    rows: list[dict] = []
    conn = None if args.dry_run else connect()
    cur = conn.cursor() if conn else None
    saved = 0

    def flush():
        nonlocal rows, saved
        if rows and cur:
            cur.execute("CALL replay_event_save(%s)", (json.dumps([rows]),))
            cur.fetchall()
            while cur.nextset():
                pass
        saved += len(rows)
        rows = []

    with log.open("rb") as fh:
        fh.seek(start)
        offset = start
        for raw in fh:
            if not raw.endswith(b"\n"):  # a half-written last line is read next time
                break
            offset += len(raw)
            seen += 1
            m = LINE.match(raw.decode("utf-8", "replace"))
            if not m:
                continue
            yy, mo, dd, hms, _res, kind, text = m.groups()
            if kind not in kinds:
                skipped += 1
                continue
            row = event_row(f"20{yy}-{mo}-{dd} {hms}", kind, text)
            if not row:
                bad += 1
                continue
            rows.append(row)
            kept += 1
            if len(rows) >= BATCH:
                flush()
    flush()
    if state and not args.dry_run:
        state.write_text(json.dumps({"inode": stat.st_ino, "offset": offset}))
    print(f"read {seen} lines from byte {start}, {kept} replay events ({skipped} other kinds, {bad} unreadable)")
    if cur:
        cur.execute("SELECT COUNT(*), MIN(at), MAX(at) FROM replay_event")
        print("replay_event now: %s rows, %s .. %s" % cur.fetchone())
        conn.close()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--log", default=str(DEFAULT_LOG))
    p.add_argument("--state", help="file keeping the byte offset reached")
    p.add_argument("--from-start", action="store_true", help="ignore the saved offset")
    p.add_argument("--dry-run", action="store_true", help="parse only, write nothing")
    return run(p.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
