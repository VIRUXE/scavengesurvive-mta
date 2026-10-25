import json

from tests.sql.conftest import call

FIRE = '{"fuel":3}'
LOGS = json.dumps([{"x": 50.5, "y": 60.0, "z": 3.0, "rz": 10.0}, {"x": 49.5, "y": 60.0, "z": 3.0, "rz": 200.0}])


def make_world_item(db, uname, x=50.0, y=60.0, z=3.0, data=None, interior=0, dimension=0):
    ok, code, payload = call(db, "item_create", uname, 5, data, x, y, z, 0.0, interior, dimension, None, None)
    assert code == "OK", code
    return payload["item_id"]


def held_meat(db, ch):
    meat = make_world_item(db, "Meat", 51.0, 61.0)
    assert call(db, "item_pickup", meat, ch)[1] == "OK"
    return meat


def item_row(db, item):
    with db.cursor() as cur:
        cur.execute("SELECT * FROM items WHERE id=%s", (item,))
        return cur.fetchone()


def item_data(db, item):
    data = item_row(db, item)["data"]
    return json.loads(data) if data else None


def test_put_food_moves_held_meat_onto_campfire(db, character):
    ch = character["character_id"]
    fire = make_world_item(db, "Campfire", interior=3, dimension=7)
    meat = held_meat(db, ch)
    ok, code, payload = call(db, "cooker_put_food", ch, meat, fire, "", FIRE, 50.2, 60.1, 3.4, 45.0)
    assert (ok, code, payload) == (1, "OK", {"item_id": meat})
    row = item_row(db, meat)
    assert (row["x"], row["y"], round(row["z"], 2), row["rz"]) == (50.2, 60.1, 3.4, 45.0)
    assert (row["interior"], row["dimension"], row["holder_char_id"], row["holder_kind"]) == (3, 7, None, None)
    assert item_data(db, fire) == {"fuel": 3}


def test_put_food_with_stale_cooker_data_is_busy(db, character):
    ch = character["character_id"]
    fire = make_world_item(db, "Campfire", data=FIRE)
    meat = held_meat(db, ch)
    assert call(db, "cooker_put_food", ch, meat, fire, "", '{"fuel":9}', 50.2, 60.1, 3.4, 0.0)[:2] == (0, "BUSY")
    row = item_row(db, meat)
    assert (row["holder_char_id"], row["holder_kind"], row["x"]) == (ch, "held", None)
    assert item_data(db, fire) == {"fuel": 3}


def test_put_food_not_held_rolls_back_cooker(db, character):
    ch = character["character_id"]
    fire = make_world_item(db, "Campfire")
    meat = make_world_item(db, "Meat", 52.0, 62.0)
    assert call(db, "cooker_put_food", ch, meat, fire, "", FIRE, 50.2, 60.1, 3.4, 0.0)[:2] == (0, "NOT_HELD")
    assert item_row(db, fire)["data"] is None
    assert item_row(db, meat)["x"] == 52.0


def test_cook_marks_nearby_listed_foods(db, character):
    ch = character["character_id"]
    fire = make_world_item(db, "Campfire", data=FIRE)
    plain = make_world_item(db, "Meat", 50.5, 60.5)
    obj = make_world_item(db, "Meat", 49.5, 59.5, data='{"bites":2}')
    wrapped = make_world_item(db, "Meat", 50.0, 60.8, data='[ { "a": 1 } ]')
    far = make_world_item(db, "Meat", 55.0, 60.0)
    unlisted = make_world_item(db, "Meat", 50.1, 60.1)
    held = held_meat(db, ch)
    foods = json.dumps([plain, obj, wrapped, far, held])
    ok, code, payload = call(db, "cooker_cook", fire, FIRE, '{"fuel":2}', foods, 1.0)
    assert (ok, code, payload) == (1, "OK", {"cooked": 3})
    assert item_data(db, plain) == {"cooked": 1}
    assert item_data(db, obj) == {"bites": 2, "cooked": 1}
    assert item_data(db, wrapped) == [{"a": 1, "cooked": 1}]
    assert [item_data(db, i) for i in (far, unlisted, held)] == [None, None, None]
    assert item_data(db, fire) == {"fuel": 2}


def test_cook_with_stale_cooker_data_is_busy(db):
    fire = make_world_item(db, "Campfire", data=FIRE)
    meat = make_world_item(db, "Meat", 50.5, 60.5)
    assert call(db, "cooker_cook", fire, "", '{"fuel":2}', json.dumps([meat]), 1.0)[:2] == (0, "BUSY")
    assert item_data(db, meat) is None
    assert item_data(db, fire) == {"fuel": 3}


def test_burn_out_turns_campfire_into_logs(db):
    fire = make_world_item(db, "Campfire", interior=2, dimension=4)
    ok, code, payload = call(db, "campfire_burn_out", fire, "BurntLog", LOGS)
    assert (ok, code, payload) == (1, "OK", {"logs": 2})
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id=%s", (fire,))
        assert cur.fetchone()["n"] == 0
        cur.execute("SELECT COUNT(*) AS n FROM world_items_pos WHERE item_id=%s", (fire,))
        assert cur.fetchone()["n"] == 0
        cur.execute("SELECT id, type_uname, x, y, rz, interior, dimension FROM items WHERE id > %s ORDER BY id", (fire,))
        logs = cur.fetchall()
        got = [(r["type_uname"], r["x"], r["y"], r["rz"], r["interior"], r["dimension"]) for r in logs]
        assert got == [("BurntLog", 50.5, 60.0, 10.0, 2, 4), ("BurntLog", 49.5, 60.0, 200.0, 2, 4)]
        ids = tuple(r["id"] for r in logs)
        cur.execute("SELECT COUNT(*) AS n FROM world_items_pos WHERE item_id IN (%s,%s)", ids)
        assert cur.fetchone()["n"] == 2
    assert call(db, "campfire_burn_out", fire, "BurntLog", LOGS)[:2] == (0, "NOT_IN_WORLD")
