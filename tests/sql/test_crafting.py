import json

from tests.sql.conftest import call


def ids(*items):
    return json.dumps([list(items)])  # MTA's toJSON wraps the list in an outer array


def in_container(db, uname, container):
    ok, code, payload = call(db, "item_create_in_container", uname, container)
    assert code == "OK", code
    return payload["item_id"]


def world_item(db, uname, x=50.0, y=60.0, z=3.0):
    ok, code, payload = call(db, "item_create", uname, 5, None, x, y, z, 0.0, 0, 0, None, None)
    assert code == "OK", code
    return payload


def row(db, item):
    with db.cursor() as cur:
        cur.execute("SELECT * FROM items WHERE id=%s", (item,))
        return cur.fetchone()


def contents(db, container):
    with db.cursor() as cur:
        cur.execute("SELECT type_uname, slot FROM items WHERE container_id=%s ORDER BY slot", (container,))
        return [(r["type_uname"], r["slot"]) for r in cur.fetchall()]


def test_combine_consumes_and_keeps_and_closes_up_slots(db, character):
    ch, inv = character["character_id"], character["inventory_container_id"]
    knife = in_container(db, "Knife", inv)
    in_container(db, "Battery", inv)
    clothes = in_container(db, "Clothes", inv)  # 5 of the inventory's 6 units
    ok, code, payload = call(db, "craft_combine", ch, None, ids(clothes), ids(knife), "Bandage", None, inv)
    assert (ok, code, payload["held"]) == (1, "OK", 0)
    assert row(db, clothes) is None and row(db, knife)["container_id"] == inv
    assert contents(db, inv) == [("Knife", 0), ("Battery", 1), ("Bandage", 2)]


def test_combine_bag_result_gets_its_container(db, character):
    ch = character["character_id"]
    box = world_item(db, "Workbench")["container_id"]
    knife, chute = in_container(db, "Knife", box), in_container(db, "Parachute", box)
    ok, code, payload = call(db, "craft_combine", ch, box, ids(chute), ids(knife), "ParaBag", None, box)
    assert code == "OK" and payload["container_id"]


def test_combine_refuses_items_it_cannot_reach(db, character):
    ch, inv = character["character_id"], character["inventory_container_id"]
    lock = in_container(db, "WheelLock", inv)
    kit = world_item(db, "LocksmithKit")["item_id"]
    assert call(db, "craft_combine", ch, None, ids(lock, kit), None, "WheelLock", None, inv)[:2] == (0, "ITEMS_MOVED")
    assert row(db, lock) is not None and row(db, kit) is not None


def test_combine_from_an_open_container_and_into_the_hands(db, character):
    ch = character["character_id"]
    box = world_item(db, "Workbench")["container_id"]
    bottle, bandage = in_container(db, "Bottle", box), in_container(db, "Bandage", box)
    ok, code, payload = call(db, "craft_combine", ch, box, ids(bottle, bandage), None, "MolotovEmpty", None, None)
    assert (ok, code, payload["held"]) == (1, "OK", 1)
    held = row(db, payload["item_id"])
    assert (held["holder_char_id"], held["holder_kind"], held["type_uname"]) == (ch, "held", "MolotovEmpty")
    assert contents(db, box) == []


def test_combine_into_full_container_counts_the_freed_units(db, character):
    ch = character["character_id"]
    box = world_item(db, "Workbench")["container_id"]  # 16 units, all used: 6 * 2 + 1 + 3
    for _ in range(6):
        in_container(db, "Battery", box)
    lock, kit = in_container(db, "WheelLock", box), in_container(db, "LocksmithKit", box)
    assert call(db, "item_create_in_container", "Knife", box)[1] == "CONTAINER_FULL"
    ok, code, _ = call(db, "craft_combine", ch, box, ids(lock, kit), None, "WheelLock", '{"cut":true}', box)
    assert code == "OK"
    assert contents(db, box)[-1] == ("WheelLock", 6)
    with db.cursor() as cur:
        cur.execute("SELECT data FROM items WHERE container_id=%s AND type_uname='WheelLock'", (box,))
        assert json.loads(cur.fetchone()["data"]) == {"cut": True}


def test_combine_into_hands_refuses_when_hands_full(db, character):
    ch, inv = character["character_id"], character["inventory_container_id"]
    hammer = world_item(db, "Hammer")["item_id"]
    assert call(db, "item_pickup", hammer, ch)[1] == "OK"
    bottle, bandage = in_container(db, "Bottle", inv), in_container(db, "Bandage", inv)
    assert call(db, "craft_combine", ch, None, ids(bottle, bandage), None, "MolotovEmpty", None, None)[1] == "HANDS_FULL"
    assert row(db, bottle) is not None


def test_build_on_the_ground_needs_every_ingredient_still_there(db, character):
    ch = character["character_id"]
    logs = [world_item(db, "WoodLog", 50.0 + i)["item_id"] for i in range(3)]
    assert call(db, "item_pickup", logs[2], ch)[1] == "OK"
    args = (ch, None, ids(*logs), None, "Campfire", None, 51.0, 60.0, 3.0, 0.0, 0, 0)
    assert call(db, "craft_build", *args)[:2] == (0, "ITEMS_MOVED")
    assert all(row(db, i) is not None for i in logs)


def test_build_key_copy_keeps_one_key_and_copies_its_data(db, character):
    ch = character["character_id"]
    cut, blank, motor = (world_item(db, u)["item_id"] for u in ("Key", "Key", "Motor"))
    ok, code, payload = call(db, "craft_build", ch, None, ids(blank, motor), ids(cut), "Key", '{"code":42}',
                             50.0, 60.0, 3.0, 0.0, 0, 0)
    assert code == "OK"
    assert row(db, cut) is not None and row(db, blank) is None and row(db, motor) is None
    assert json.loads(row(db, payload["item_id"])["data"]) == {"code": 42}


def test_build_at_workbench_needs_the_contents_unchanged(db, character):
    ch = character["character_id"]
    bench = world_item(db, "Workbench")["container_id"]
    battery, fuse = in_container(db, "Battery", bench), in_container(db, "Fusebox", bench)
    in_container(db, "Timer", bench)
    args = (ch, bench, ids(battery, fuse), None, "PowerSupply", None, 50.0, 60.0, 3.95, 0.0, 0, 0)
    assert call(db, "craft_build", *args)[:2] == (0, "ITEMS_MOVED")
    with db.cursor() as cur:
        cur.execute("DELETE FROM items WHERE container_id=%s AND type_uname='Timer'", (bench,))
    ok, code, payload = call(db, "craft_build", *args)
    assert code == "OK" and contents(db, bench) == []
    built = row(db, payload["item_id"])
    assert (built["type_uname"], round(built["z"], 2), built["container_id"]) == ("PowerSupply", 3.95, None)


def test_build_safebox_result_gets_its_container(db, character):
    ch = character["character_id"]
    parts = [world_item(db, u)["item_id"] for u in ("MetalFrame", "MetalFrame", "RefinedMetal")]
    ok, code, payload = call(db, "craft_build", ch, None, ids(*parts), None, "Locker", None, 50.0, 60.0, 3.0, 0.0, 0, 0)
    assert code == "OK" and payload["container_id"]


def test_deconstruct_returns_the_ingredients(db, character):
    built = world_item(db, "Desk")["item_id"]
    back = [{"uname": "RefinedMetal", "x": 50.1, "y": 60.2, "z": 3.0, "rz": 10.0},
            {"uname": "WoodLog", "x": 50.3, "y": 60.4, "z": 3.0, "rz": 20.0}]
    assert call(db, "craft_deconstruct", built, "Table", json.dumps([back]), 0, 0)[:2] == (0, "ITEMS_MOVED")
    ok, code, payload = call(db, "craft_deconstruct", built, "Desk", json.dumps([back]), 0, 0)
    assert (code, payload) == ("OK", {"returned": 2}) and row(db, built) is None
    with db.cursor() as cur:
        cur.execute("SELECT type_uname FROM items WHERE x BETWEEN 50.05 AND 50.35 AND y BETWEEN 60.15 AND 60.45")
        assert sorted(r["type_uname"] for r in cur.fetchall()) == ["RefinedMetal", "WoodLog"]
