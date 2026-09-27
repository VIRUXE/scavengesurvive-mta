import argparse
import os

import pymysql

from tests.sql.conftest import ARGS
from tools import sqltool

DB = os.environ.get("SS_TEST_DB", "scavengesurvive_test") + "_sqltool"


def _args(reset):
    return argparse.Namespace(db=DB, host=ARGS.host, port=ARGS.port, user=ARGS.user, password=ARGS.password,
                              reset=reset)


def test_apply_twice_without_reset_keeps_data():
    sqltool.apply(_args(reset=True))
    conn = pymysql.connect(host=ARGS.host, port=ARGS.port, user=ARGS.user, password=ARGS.password, database=DB,
                           autocommit=True, charset="utf8mb4")
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO accounts (name, password_hash) VALUES ('keepme', REPEAT('x', 60))")
        sqltool.apply(_args(reset=False))
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM accounts WHERE name='keepme'")
            assert cur.fetchone()[0] == 1
            cur.execute("SELECT version FROM schema_migrations ORDER BY version")
            assert [r[0] for r in cur.fetchall()] == [1]
    finally:
        with conn.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS `{DB}`")
        conn.close()
