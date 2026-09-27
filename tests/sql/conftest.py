import json
import os

import pymysql
import pytest

from tools import sqltool

DB = os.environ.get("SS_TEST_DB", "scavengesurvive_test")
ARGS = type("A", (), dict(
    db=DB, host=os.environ.get("SS_DB_HOST", "127.0.0.1"), port=int(os.environ.get("SS_DB_PORT", "3306")),
    user=os.environ.get("SS_DB_USER", "root"), password=os.environ.get("SS_DB_PASSWORD", ""), reset=True))


def _connect():
    return pymysql.connect(host=ARGS.host, port=ARGS.port, user=ARGS.user, password=ARGS.password, database=DB,
                           autocommit=True, charset="utf8mb4", cursorclass=pymysql.cursors.DictCursor)


@pytest.fixture(scope="session")
def db():
    sqltool.apply(ARGS)
    conn = _connect()
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO item_types (uname,name,model,size,category,category_data) VALUES "
            "('T_Knife','Combat Knife',335,1,'weapon','{\"baseWeapon\":4}'),"
            "('T_Satchel','Small Bag',1550,3,'bag','{\"bag_size\":7}'),"
            "('T_Wrench','Wrench',18633,1,'generic',NULL) ON DUPLICATE KEY UPDATE name=VALUES(name)")
    yield conn
    conn.close()


def call(conn, proc, *params):
    with conn.cursor() as cur:
        cur.callproc(proc, params)
        row = cur.fetchone()
        while cur.nextset():
            pass
    payload = json.loads(row["payload"]) if row and row["payload"] else None
    return row["ok"], row["code"], payload


@pytest.fixture
def account(db):
    with db.cursor() as cur:
        cur.execute("INSERT INTO accounts (name, password_hash) VALUES (CONCAT('t', UUID_SHORT()), REPEAT('x', 60))")
        return cur.lastrowid


@pytest.fixture
def character(db, account):
    ok, code, payload = call(db, "character_create", account, 0, 0.0, 0.0, 3.0, 0.0, 90.0, 80.0, 0.0001)
    assert ok == 1 and code == "OK", code
    return payload
