"""The items_world_pos_* triggers keep world_items_pos (the spatial mirror of items lying in the world) in step."""
from tests.sql.conftest import DB, call
from tests.sql.test_item_graph import RING, make_world_item

TRIGGERS_SQL = ("SELECT TRIGGER_NAME, EVENT_MANIPULATION, ACTION_TIMING FROM information_schema.TRIGGERS "
                "WHERE TRIGGER_SCHEMA=%s AND EVENT_OBJECT_TABLE='items' ORDER BY TRIGGER_NAME")
MISMATCH_SQL = ("SELECT COUNT(*) AS n FROM items i LEFT JOIN world_items_pos p ON p.item_id = i.id "
                "WHERE (i.x IS NULL) <> (p.item_id IS NULL)")


def pos(db, item):
    with db.cursor() as cur:
        cur.execute("SELECT ST_X(pos) AS px, ST_Y(pos) AS py FROM world_items_pos WHERE item_id=%s", (item,))
        r = cur.fetchone()
        return (r["px"], r["py"]) if r else None


def test_triggers_are_installed(db):
    with db.cursor() as cur:
        cur.execute(TRIGGERS_SQL, (DB,))
        rows = [(r["TRIGGER_NAME"], r["EVENT_MANIPULATION"], r["ACTION_TIMING"]) for r in cur.fetchall()]
    assert rows == [("items_world_pos_insert", "INSERT", "AFTER"), ("items_world_pos_update", "UPDATE", "AFTER")]


def test_create_in_world_mirrors_position(db):
    item = make_world_item(db, x=11.5, y=-22.25)
    assert pos(db, item) == (11.5, -22.25)


def test_create_off_world_has_no_row(db, character):
    ok, code, payload = call(db, "item_create_in_container", "T_Wrench", character["inventory_container_id"])
    assert code == "OK"
    assert pos(db, payload["item_id"]) is None


def test_pickup_removes_and_drop_restores(db, character):
    ch = character["character_id"]
    item = make_world_item(db, x=1.0, y=2.0)
    assert call(db, "item_pickup", item, ch)[1] == "OK"
    assert pos(db, item) is None
    assert call(db, "item_drop", item, ch, 7.5, 8.5, 3.0, 0.0, 0, 0)[1] == "OK"
    assert pos(db, item) == (7.5, 8.5)


def test_plain_move_updates_position(db):
    item = make_world_item(db, x=1.0, y=2.0)
    with db.cursor() as cur:
        cur.execute("UPDATE items SET x=%s, y=%s WHERE id=%s", (3.0, 4.0, item))
    assert pos(db, item) == (3.0, 4.0)
    with db.cursor() as cur:
        cur.execute("UPDATE items SET y=%s WHERE id=%s", (9.0, item))  # y alone moves it too
    assert pos(db, item) == (3.0, 9.0)


def test_data_only_update_leaves_the_row_alone(db):
    item = make_world_item(db, x=1.0, y=2.0)
    with db.cursor() as cur:
        # remove the mirror row by hand: an update that does not move the item must not write it back
        cur.execute("DELETE FROM world_items_pos WHERE item_id=%s", (item,))
        cur.execute("UPDATE items SET data='{\"rounds\":3}', hitpoints=2, z=9 WHERE id=%s", (item,))
    assert pos(db, item) is None
    with db.cursor() as cur:
        cur.execute("DELETE FROM items WHERE id=%s", (item,))


def test_death_drop_mirrors_dropped_items_and_clothes(db, character):
    ch, cid = character["character_id"], character["inventory_container_id"]
    a, b = make_world_item(db), make_world_item(db)
    call(db, "item_pickup", a, ch)
    call(db, "container_put", a, ch, cid)
    call(db, "item_pickup", b, ch)
    assert pos(db, a) is None and pos(db, b) is None
    ok, code, payload = call(db, "character_death_drop", ch, 100.0, 200.0, 5.0, 0, 0, RING, 4.2, 135.0)
    assert code == "OK" and payload["dropped"] == 2
    with db.cursor() as cur:
        for item in (a, b, payload["clothes_item_id"]):
            cur.execute("SELECT x, y FROM items WHERE id=%s", (item,))
            r = cur.fetchone()
            got = pos(db, item)
            assert got is not None and abs(got[0] - r["x"]) < 1e-3 and abs(got[1] - r["y"]) < 1e-3
    assert pos(db, payload["clothes_item_id"]) == (101.0, 200.0)


def test_transfer_with_delete_and_weapon_unload(db, character):
    ch = character["character_id"]
    wep = make_world_item(db, "T_Knife", 5.0, 6.0, 3.0)
    tin = make_world_item(db, "T_Wrench", 5.5, 6.0, 3.0)
    keep = make_world_item(db, "T_Wrench", 5.5, 7.0, 3.0)
    assert call(db, "item_pickup", wep, ch)[1] == "OK"
    assert pos(db, wep) is None
    ok, code, _ = call(db, "item_transfer_world", ch, wep, tin, '{"mag":10,"reserve":0}', '{"rounds":0}', 1, 0)
    assert code == "OK"
    assert pos(db, tin) is None
    # a transfer that keeps the world item only changes its data: its mirror row stays
    ok, code, _ = call(db, "item_transfer_world", ch, wep, keep, '{"mag":12,"reserve":0}', '{"rounds":1}', 0, 0)
    assert code == "OK"
    assert pos(db, keep) == (5.5, 7.0)
    args = (ch, wep, '{"mag":0,"reserve":0}', "T_Wrench", '{"rounds":10}', 5.0, 6.5, 3.0, 0.0, 0, 0)
    ok, code, payload = call(db, "weapon_unload", *args)
    assert code == "OK"
    assert pos(db, payload["ammo_item_id"]) == (5.0, 6.5)
    assert pos(db, wep) is None


def test_mirror_matches_items_in_world(db):
    # one mirror row per item lying in the world, none for an item anywhere else
    with db.cursor() as cur:
        cur.execute(MISMATCH_SQL)
        assert cur.fetchone()["n"] == 0
