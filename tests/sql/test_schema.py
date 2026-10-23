import pymysql
import pytest

from tests.sql.conftest import call


def test_migration_recorded(db):
    with db.cursor() as cur:
        cur.execute("SELECT version, name FROM schema_migrations ORDER BY version")
        assert [r["name"] for r in cur.fetchall()] == ["init", "vehicle_spawns", "vehicles", "vehicle_m5", "crafting_building_m6", "staff_m7"]


def test_vehicle_spawns_seeded_from_every_vpl(db):
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n, COUNT(DISTINCT file) AS files, SUM(type_name IS NOT NULL) AS typed "
                    "FROM vehicle_spawns")
        row = cur.fetchone()
        assert row["n"] == 2017 and row["files"] == 73 and row["typed"] == 48  # 2018 upstream lines minus 'Coach'
        cur.execute("SELECT ST_X(pos) AS x, x AS cx FROM vehicle_spawns LIMIT 1")
        r = cur.fetchone()
        assert abs(r["x"] - r["cx"]) < 1e-3


def test_items_exactly_one_location_enforced(db):
    with db.cursor() as cur, pytest.raises(pymysql.err.OperationalError):
        cur.execute("INSERT INTO items (type_uname, x, y, z, container_id) VALUES ('T_Wrench', 1, 2, 3, 1)")


def test_only_one_alive_character_per_account(db, account, character):
    ok, code, payload = call(db, "character_create", account, 0, 0.0, 0.0, 3.0, 0.0, 100.0, 40.0, 0.0)
    assert ok == 1
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n FROM characters WHERE account_id=%s AND alive=1", (account,))
        assert cur.fetchone()["n"] == 1
