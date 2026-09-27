import pymysql
import pytest

from tests.sql.conftest import call


def test_migration_recorded(db):
    with db.cursor() as cur:
        cur.execute("SELECT version, name FROM schema_migrations ORDER BY version")
        assert [r["name"] for r in cur.fetchall()] == ["init"]


def test_items_exactly_one_location_enforced(db):
    with db.cursor() as cur, pytest.raises(pymysql.err.OperationalError):
        cur.execute("INSERT INTO items (type_uname, x, y, z, container_id) VALUES ('T_Wrench', 1, 2, 3, 1)")


def test_only_one_alive_character_per_account(db, account, character):
    ok, code, payload = call(db, "character_create", account, 0, 0.0, 0.0, 3.0, 0.0, 100.0, 40.0, 0.0)
    assert ok == 1
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n FROM characters WHERE account_id=%s AND alive=1", (account,))
        assert cur.fetchone()["n"] == 1
