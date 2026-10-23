import json

from tests.sql.conftest import call


def make_clothes(db, character, held=True):
    ok, code, payload = call(db, "item_create_held", "Clothes", character["character_id"])
    assert code == "OK", code
    item = payload["item_id"]
    if not held:
        assert call(db, "container_put", item, character["character_id"], character["inventory_container_id"])[1] == "OK"
    return item


def skin_and_data(db, character, item):
    with db.cursor() as cur:
        cur.execute("SELECT skin FROM characters WHERE id=%s", (character["character_id"],))
        skin = cur.fetchone()["skin"]
        cur.execute("SELECT data FROM items WHERE id=%s", (item,))
        data = cur.fetchone()["data"]
    return skin, json.loads(data) if data else None


def test_swap_puts_the_old_skin_in_the_item(db, character):
    item = make_clothes(db, character)
    ok, code, payload = call(db, "clothes_swap", item, character["character_id"], 285)
    assert (ok, code) == (1, "OK")
    assert payload == {"item_id": item, "old_skin": 0, "new_skin": 285}
    assert skin_and_data(db, character, item) == (285, {"skin": 0})
    # and back: the item now holds the first skin
    assert call(db, "clothes_swap", item, character["character_id"], 0)[2]["old_skin"] == 285
    assert skin_and_data(db, character, item) == (0, {"skin": 285})


def test_swap_from_the_inventory(db, character):
    item = make_clothes(db, character, held=False)
    assert call(db, "clothes_swap", item, character["character_id"], 60)[1] == "OK"
    assert skin_and_data(db, character, item) == (60, {"skin": 0})


def test_swap_refuses_other_items_and_strangers(db, character):
    _, _, payload = call(db, "item_create", "T_Wrench", 5, None, 1.0, 2.0, 3.0, 0.0, 0, 0, None, None)
    world_item = payload["item_id"]
    assert call(db, "clothes_swap", world_item, character["character_id"], 60)[1] == "NOT_OWNED"
    item = make_clothes(db, character)
    assert call(db, "clothes_swap", item, None, 60)[1] == "NO_CHARACTER"
    assert skin_and_data(db, character, item) == (0, None)
