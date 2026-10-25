"""loot_roll (one call per batch of loot rolls), item_data_flush (batched held-item data), item_types.container_size
and the item history purge event."""
import json
import uuid

import pytest

from tests.sql.conftest import DB, call
from tests.sql.test_item_graph import make_world_item
from tests.sql.test_world_items_pos import pos

TYPES_SQL = ("INSERT INTO item_types (uname,name,model,size,category,category_data) VALUES "
             "('T_Safe','Safebox',1271,6,'safebox','{\"size\":12}'),"
             "('T_Sack','Sack',1550,3,'bag','{}') ON DUPLICATE KEY UPDATE name=VALUES(name)")
SPAWN_SQL = ("INSERT INTO loot_spawns (x, y, z, table_name, weight, interior, dimension, zone, pos) "
             "VALUES (%s, %s, 3, 'world_civilian', 1, %s, %s, %s, POINT(%s, %s))")
BUDGET_SQL = "INSERT INTO world_budget (category, zone, cap, remainder, allowance) VALUES ('loot', %s, 100, 0, %s)"
COOLDOWN_SQL = "SELECT TIMESTAMPDIFF(SECOND, NOW(), next_roll_at) AS s FROM loot_spawn_state WHERE spawn_id=%s"
SPAWN_ITEMS_SQL = ("SELECT i.id, i.type_uname, i.hitpoints, i.data, i.x, i.y, i.z, i.rz, i.interior, i.dimension, "
                   "i.loot_zone, TIMESTAMPDIFF(MINUTE, NOW(), i.despawn_at) AS despawn_in, c.kind, c.size "
                   "FROM items i LEFT JOIN containers c ON c.owner_item_id = i.id "
                   "WHERE i.loot_spawn_id=%s ORDER BY i.id")
SIZES_SQL = ("SELECT uname, container_size FROM item_types WHERE uname IN ('T_Satchel','T_Safe','T_Sack','T_Wrench') "
             "ORDER BY uname")
EVENT_SQL = ("SELECT INTERVAL_VALUE, INTERVAL_FIELD, STATUS, EVENT_DEFINITION FROM information_schema.EVENTS "
             "WHERE EVENT_SCHEMA=%s AND EVENT_NAME='ev_item_history'")
# the statement vehicles/server/main.lua runs (DELETE_ABANDONED)
ABANDONED_SQL = ("DELETE FROM vehicles WHERE left_spawn = 1 "
                 "AND COALESCE(last_used_at, updated_at) < DATE_SUB(NOW(), INTERVAL %s DAY) RETURNING id")
VEHICLE_SQL = ("INSERT INTO vehicles (type_uname, model, x, y, z, left_spawn, last_used_at) "
               "VALUES ('Bobcat', 422, 0, 0, 0, %s, DATE_SUB(NOW(), INTERVAL %s DAY))")


@pytest.fixture(scope="module")
def types(db):
    with db.cursor() as cur:
        cur.execute(TYPES_SQL)


def spawn(db, allowance=10, x=500.0, y=600.0, interior=2, dimension=3):
    """A fresh loot point in its own zone (with a loot budget row), due now."""
    zone = uuid.uuid4().hex[:8]
    with db.cursor() as cur:
        cur.execute(SPAWN_SQL, (x, y, interior, dimension, zone, x, y))
        sid = cur.lastrowid
        cur.execute("INSERT INTO loot_spawn_state (spawn_id, next_roll_at) VALUES (%s, NOW())", (sid,))
        cur.execute(BUDGET_SQL, (zone, allowance))
    return sid, zone


def rolls(*entries):
    # MTA's toJSON wraps the table in an outer array
    return json.dumps([list(entries)])


def item(u, x=500.5, y=600.0, data=None):
    it = {"u": u, "x": x, "y": y, "z": 3.1032, "rz": 45}
    if data is not None:
        it["data"] = data
    return it


def allowance(db, zone):
    with db.cursor() as cur:
        cur.execute("SELECT allowance FROM world_budget WHERE category='loot' AND zone=%s", (zone,))
        return cur.fetchone()["allowance"]


def cooldown_left(db, sid):
    with db.cursor() as cur:
        cur.execute(COOLDOWN_SQL, (sid,))
        return cur.fetchone()["s"]


def spawn_items(db, sid):
    with db.cursor() as cur:
        cur.execute(SPAWN_ITEMS_SQL, (sid,))
        return cur.fetchall()


def test_loot_roll_places_items_spends_budget_and_cools(db, types):
    sid, zone = spawn(db, allowance=10)
    items = [
        item("T_Wrench"),
        item("T_Satchel", 499.5),
        item("T_Safe", 500.0, 600.5),
        item("T_Sack", 500.0, 599.5),
        item("NoSuchType"),
    ]
    ok, code, payload = call(db, "loot_roll", rolls({"s": sid, "cd": 3600, "items": items}), 120)
    assert (ok, code) == (1, "OK")
    assert payload == {"created": 4}
    rows = spawn_items(db, sid)
    assert [r["type_uname"] for r in rows] == ["T_Wrench", "T_Satchel", "T_Safe", "T_Sack"]
    for r in rows:
        assert (r["interior"], r["dimension"], r["loot_zone"], r["hitpoints"]) == (2, 3, zone, 5)
        assert 118 <= r["despawn_in"] <= 120
        assert r["rz"] == 45.0 and abs(r["z"] - 3.1032) < 1e-4
        got = pos(db, r["id"])  # the insert trigger mirrors every rolled item
        assert got is not None and abs(got[0] - r["x"]) < 1e-3 and abs(got[1] - r["y"]) < 1e-3
    assert [(r["kind"], r["size"]) for r in rows] == [(None, None), ("bag", 7), ("safebox", 12), ("bag", 8)]
    assert allowance(db, zone) == 6  # 4 created; the unknown type costs nothing
    assert 3590 <= cooldown_left(db, sid) <= 3600


def test_loot_roll_leaves_earlier_bags_without_a_container_alone(db, types):
    sid, _ = spawn(db)
    with db.cursor() as cur:
        cur.execute("INSERT INTO items (type_uname, loot_spawn_id, x, y, z) VALUES ('T_Satchel', %s, 500, 600, 3)", (sid,))
        old = cur.lastrowid
    ok, code, payload = call(db, "loot_roll", rolls({"s": sid, "cd": 60, "items": [item("T_Satchel", 499.5)]}), 30)
    assert (ok, code, payload) == (1, "OK", {"created": 1})
    rows = {r["id"]: r for r in spawn_items(db, sid)}
    assert rows[old]["kind"] is None
    assert [r["kind"] for i, r in rows.items() if i != old] == ["bag"]


def test_loot_roll_stores_data_text_as_json(db, types):
    sid, _ = spawn(db)
    items = [item("T_Knife", data='{"mag":3,"ammoItem":"Ammo9mm"}'), item("T_Wrench")]
    ok, code, payload = call(db, "loot_roll", rolls({"s": sid, "cd": 60, "items": items}), 30)
    assert code == "OK" and payload["created"] == 2
    rows = spawn_items(db, sid)
    assert json.loads(rows[0]["data"]) == {"mag": 3, "ammoItem": "Ammo9mm"}
    assert rows[1]["data"] is None
    with db.cursor() as cur:
        cur.execute("SELECT JSON_VALUE(data, '$.mag') AS mag, JSON_TYPE(data) AS t FROM items WHERE id=%s", (rows[0]["id"],))
        r = cur.fetchone()
        assert (r["mag"], r["t"]) == ("3", "OBJECT")


def test_loot_roll_empty_roll_still_cools_and_costs_nothing(db, types):
    a, zone_a = spawn(db, allowance=5)
    b, zone_b = spawn(db, allowance=5)
    empty = {"s": a, "cd": 900, "items": []}
    two = {"s": b, "cd": 1800, "items": [item("T_Wrench"), item("T_Wrench", 501.0)]}
    ok, code, payload = call(db, "loot_roll", rolls(empty, two), 60)
    assert code == "OK" and payload["created"] == 2
    assert spawn_items(db, a) == ()
    assert 890 <= cooldown_left(db, a) <= 900
    assert 1790 <= cooldown_left(db, b) <= 1800
    assert (allowance(db, zone_a), allowance(db, zone_b)) == (5, 3)


def test_loot_roll_allowance_never_goes_negative(db, types):
    sid, zone = spawn(db, allowance=1)
    items = [item("T_Wrench"), item("T_Wrench", 501.0), item("T_Wrench", 502.0)]
    ok, code, payload = call(db, "loot_roll", rolls({"s": sid, "cd": 60, "items": items}), 60)
    assert code == "OK" and payload["created"] == 3
    assert allowance(db, zone) == 0


def test_loot_roll_skips_unknown_spawn(db, types):
    ok, code, payload = call(db, "loot_roll", rolls({"s": 987654321, "cd": 60, "items": [item("T_Wrench")]}), 60)
    assert (ok, code, payload) == (1, "OK", {"created": 0})


def test_item_data_flush_updates_only_listed_items(db):
    a, b, c = make_world_item(db), make_world_item(db), make_world_item(db)
    with db.cursor() as cur:
        cur.execute("UPDATE items SET data='{\"mag\":9}' WHERE id=%s", (c,))
    rows = [{"id": a, "data": '{"mag":1,"reserve":4}'}, {"id": b, "data": '{"mag":2}'}, {"id": 987654321, "data": '{"mag":5}'}]
    ok, code, payload = call(db, "item_data_flush", json.dumps([rows]))
    assert (ok, code, payload) == (1, "OK", {"updated": 2})
    with db.cursor() as cur:
        cur.execute("SELECT id, data FROM items WHERE id IN (%s, %s, %s) ORDER BY id", (a, b, c))
        got = {r["id"]: json.loads(r["data"]) for r in cur.fetchall()}
    assert got == {a: {"mag": 1, "reserve": 4}, b: {"mag": 2}, c: {"mag": 9}}


def test_container_size_generated_from_category_data(db, types):
    with db.cursor() as cur:
        cur.execute(SIZES_SQL)
        got = {r["uname"]: r["container_size"] for r in cur.fetchall()}
    assert got == {"T_Satchel": 7, "T_Safe": 12, "T_Sack": None, "T_Wrench": None}


def test_container_size_holds_sizes_past_a_byte(db):
    insert = "INSERT INTO item_types (uname,name,model,size,category,category_data) VALUES ('T_Huge','Huge',1550,3,'bag','{\"bag_size\":200}')"
    with db.cursor() as cur:
        cur.execute(insert)
        cur.execute("SELECT container_size FROM item_types WHERE uname='T_Huge'")
        assert cur.fetchone()["container_size"] == 200
        cur.execute("DELETE FROM item_types WHERE uname='T_Huge'")


def test_item_create_sizes_containers_from_container_size(db, types, character):
    sizes = {}
    for uname in ("T_Satchel", "T_Safe", "T_Sack"):
        ok, code, payload = call(db, "item_create", uname, 5, None, 0.0, 0.0, 3.0, 0.0, 0, 0, None, None)
        assert code == "OK"
        with db.cursor() as cur:
            cur.execute("SELECT kind, size FROM containers WHERE id=%s", (payload["container_id"],))
            r = cur.fetchone()
            sizes[uname] = (r["kind"], r["size"])
    assert sizes == {"T_Satchel": ("bag", 7), "T_Safe": ("safebox", 12), "T_Sack": ("bag", 8)}


def test_item_history_event_purges_hourly(db):
    with db.cursor() as cur:
        cur.execute(EVENT_SQL, (DB,))
        r = cur.fetchone()
    assert r is not None
    assert (r["INTERVAL_VALUE"], r["INTERVAL_FIELD"], r["STATUS"]) == ("1", "HOUR", "ENABLED")
    assert "DELETE HISTORY FROM items" in r["EVENT_DEFINITION"] and "INTERVAL 7 DAY" in r["EVENT_DEFINITION"]


def test_abandoned_vehicles_retire_in_one_delete_returning(db):
    ids = {}
    with db.cursor() as cur:
        for name, left, used in (("old", 1, 5), ("recent", 1, 1), ("parked", 0, 5)):
            cur.execute(VEHICLE_SQL, (left, used))
            ids[name] = cur.lastrowid
        cur.execute("INSERT INTO containers (kind, size, owner_vehicle_id) VALUES ('vehicle', 4, %s)", (ids["old"],))
        trunk = cur.lastrowid
        cur.execute("INSERT INTO items (type_uname, container_id, slot) VALUES ('T_Wrench', %s, 0)", (trunk,))
        in_trunk = cur.lastrowid
        cur.execute(ABANDONED_SQL, (3,))
        returned = {r["id"] for r in cur.fetchall()}
        assert ids["old"] in returned and ids["recent"] not in returned and ids["parked"] not in returned
        cur.execute("SELECT id FROM vehicles WHERE id IN (%s, %s, %s)", tuple(ids.values()))
        assert {r["id"] for r in cur.fetchall()} == {ids["recent"], ids["parked"]}
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id=%s", (in_trunk,))
        assert cur.fetchone()["n"] == 0  # the trunk and its items go with the vehicle
        cur.execute("DELETE FROM vehicles WHERE id IN (%s, %s)", (ids["recent"], ids["parked"]))
