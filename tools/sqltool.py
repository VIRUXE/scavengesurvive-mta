"""Apply migrations, procedures, events and seeds to a MariaDB database.

Usage: python -m tools.sqltool --db NAME [--host H --port P --user U --password PW] [--reset] apply
Migrations/seeds are split on a semicolon that ends a line; procedure and event files are sent whole
(one CREATE OR REPLACE statement per file, no DELIMITER).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "sql"
SPLIT = re.compile(r";[ \t]*\r?\n")


def statements(text: str) -> list[str]:
    out = []
    for chunk in SPLIT.split(text):
        lines = [ln for ln in chunk.splitlines() if not ln.strip().startswith("--")]
        st = "\n".join(lines).strip()
        if st:
            out.append(st)
    return out


def connect(args, database):
    return pymysql.connect(host=args.host, port=args.port, user=args.user, password=args.password,
                           database=database, autocommit=True, charset="utf8mb4")


def apply(args) -> None:
    if args.reset:
        with connect(args, None) as c, c.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS `{args.db}`")
    with connect(args, None) as c, c.cursor() as cur:
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{args.db}` CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci")
    with connect(args, args.db) as c, c.cursor() as cur:
        for f in sorted((SQL / "migrations").glob("*.sql")):
            for st in statements(f.read_text(encoding="utf-8")):
                cur.execute(st)
        for sub in ("procedures", "events"):
            for f in sorted((SQL / sub).glob("*.sql")):
                cur.execute(f.read_text(encoding="utf-8").strip().rstrip(";"))
        for f in sorted((SQL / "seed").glob("*.sql")):
            for st in statements(f.read_text(encoding="utf-8")):
                cur.execute(st)
    print(f"applied to {args.db}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--db", required=True)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3306)
    p.add_argument("--user", default="root")
    p.add_argument("--password", default="")
    p.add_argument("--reset", action="store_true")
    p.add_argument("command", choices=["apply"])
    args = p.parse_args(argv)
    apply(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
