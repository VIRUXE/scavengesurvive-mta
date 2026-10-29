import json
from tests.sql.conftest import call
from tests.sql.test_item_graph import make_world_item


def test_explosion_damage_damages_and_destroys_world_items(db):
    # Create two world items (each starts with 5 HP from make_world_item)
    it1 = make_world_item(db, "T_Wrench")  # 5 HP
    it2 = make_world_item(db, "T_Knife")   # 5 HP

    # Apply 2 damage to it1 (survives with 3 HP) and 5 damage to it2 (destroyed)
    rows = f'[[{{"id":{it1},"dmg":2}},{{"id":{it2},"dmg":5}}]]'
    ok, code, payload = call(db, "explosion_damage", rows)

    assert ok == 1 and code == "OK"
    assert len(payload["damaged"]) == 1
    assert payload["damaged"][0]["id"] == it1
    assert payload["damaged"][0]["hp"] == 3

    assert len(payload["destroyed"]) == 1
    assert payload["destroyed"][0]["id"] == it2
    assert payload["destroyed"][0]["uname"] == "T_Knife"

    # Verify database state
    with db.cursor() as cur:
        cur.execute("SELECT hitpoints FROM items WHERE id=%s", (it1,))
        r1 = cur.fetchone()
        assert r1["hitpoints"] == 3

        cur.execute("SELECT id FROM items WHERE id=%s", (it2,))
        assert cur.fetchone() is None

        # Verify world_items_pos was cleaned up for it2
        cur.execute("SELECT item_id FROM world_items_pos WHERE item_id=%s", (it2,))
        assert cur.fetchone() is None


def test_explosion_damage_ignores_held_or_container_items(db, character):
    ch = character["character_id"]
    # Held item
    held = call(db, "item_create_held", "T_Wrench", ch)[2]["item_id"]

    rows = f'[[{{"id":{held},"dmg":5}}]]'
    ok, code, payload = call(db, "explosion_damage", rows)

    assert ok == 1 and code == "OK"
    assert len(payload["damaged"]) == 0
    assert len(payload["destroyed"]) == 0

    with db.cursor() as cur:
        cur.execute("SELECT hitpoints FROM items WHERE id=%s", (held,))
        assert cur.fetchone()["hitpoints"] == 5
