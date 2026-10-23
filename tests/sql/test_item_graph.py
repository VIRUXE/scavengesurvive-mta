import json
import threading

import pymysql

from tests.sql.conftest import ARGS, DB, call


def make_world_item(db, uname="T_Wrench", x=10.0, y=20.0, z=3.0):
    ok, code, payload = call(db, "item_create", uname, 5, None, x, y, z, 0.0, 0, 0, None, None)
    assert code == "OK"
    return payload["item_id"]


def test_pickup_moves_item_to_hand(db, character):
    item = make_world_item(db)
    ok, code, _ = call(db, "item_pickup", item, character["character_id"])
    assert (ok, code) == (1, "OK")
    with db.cursor() as cur:
        cur.execute("SELECT x, holder_char_id, holder_kind FROM items WHERE id=%s", (item,))
        row = cur.fetchone()
        assert row["x"] is None and row["holder_char_id"] == character["character_id"] and row["holder_kind"] == "held"
        cur.execute("SELECT COUNT(*) AS n FROM world_items_pos WHERE item_id=%s", (item,))
        assert cur.fetchone()["n"] == 0


def test_pickup_with_full_hands_refused(db, character):
    a, b = make_world_item(db), make_world_item(db)
    assert call(db, "item_pickup", a, character["character_id"])[1] == "OK"
    assert call(db, "item_pickup", b, character["character_id"])[1] == "HANDS_FULL"


def test_drop_returns_item_to_world_with_position(db, character):
    item = make_world_item(db)
    call(db, "item_pickup", item, character["character_id"])
    ok, code, _ = call(db, "item_drop", item, character["character_id"], 1.5, 2.5, 3.5, 90.0, 0, 0)
    assert code == "OK"
    with db.cursor() as cur:
        cur.execute("SELECT ST_X(pos) AS px, ST_Y(pos) AS py FROM world_items_pos WHERE item_id=%s", (item,))
        row = cur.fetchone()
        assert (row["px"], row["py"]) == (1.5, 2.5)


def test_put_and_take_inventory_respects_capacity(db, character):
    cid, ch = character["inventory_container_id"], character["character_id"]
    items = [make_world_item(db) for _ in range(7)]
    for i, item in enumerate(items[:6]):
        assert call(db, "item_pickup", item, ch)[1] == "OK"
        ok, code, payload = call(db, "container_put", item, ch, cid)
        assert code == "OK" and payload["slot"] == i
    assert call(db, "item_pickup", items[6], ch)[1] == "OK"
    assert call(db, "container_put", items[6], ch, cid)[1] == "CONTAINER_FULL"
    assert call(db, "item_drop", items[6], ch, 0, 0, 3, 0, 0, 0)[1] == "OK"
    assert call(db, "container_take", items[2], ch)[1] == "OK"
    with db.cursor() as cur:
        cur.execute("SELECT slot FROM items WHERE container_id=%s ORDER BY slot", (cid,))
        assert [r["slot"] for r in cur.fetchall()] == [0, 1, 2, 3, 4]


def test_cannot_put_bag_inside_itself(db, character):
    ch = character["character_id"]
    ok, code, payload = call(db, "item_create", "T_Satchel", 5, None, 0.0, 0.0, 3.0, 0.0, 0, 0, None, None)
    bag, bag_container = payload["item_id"], payload["container_id"]
    assert bag_container is not None
    assert call(db, "item_pickup", bag, ch)[1] == "OK"
    assert call(db, "container_put", bag, ch, bag_container)[1] == "SELF_CONTAINMENT"


def test_wear_bag_refuses_a_second_one_without_an_error(db, character):
    ch = character["character_id"]
    bags = [make_world_item(db, "T_Satchel") for _ in range(2)]
    assert call(db, "bag_wear", bags[0], ch)[1] == "NOT_HELD"
    assert call(db, "item_pickup", bags[0], ch)[1] == "OK"
    assert call(db, "bag_wear", bags[0], ch)[1] == "OK"
    assert call(db, "item_pickup", bags[1], ch)[1] == "OK"
    assert call(db, "bag_wear", bags[1], ch)[1] == "BAG_SLOT_USED"
    with db.cursor() as cur:
        cur.execute("SELECT holder_kind FROM items WHERE id IN (%s,%s) ORDER BY id", tuple(bags))
        assert [r["holder_kind"] for r in cur.fetchall()] == ["bag", "held"]


def test_other_characters_inventory_refused(db, character):
    ch = character["character_id"]
    with db.cursor() as cur:
        cur.execute("INSERT INTO accounts (name, password_hash) VALUES (CONCAT('o', UUID_SHORT()), REPEAT('x', 60))")
        other = call(db, "character_create", cur.lastrowid, 0, 0.0, 0.0, 3.0, 0.0, 100.0, 80.0, 0.0)[2]
    mine, theirs = make_world_item(db), make_world_item(db)
    assert call(db, "item_pickup", mine, ch)[1] == "OK"
    assert call(db, "container_put", mine, ch, other["inventory_container_id"])[1] == "NOT_OWNER"
    assert call(db, "item_pickup", theirs, other["character_id"])[1] == "OK"
    assert call(db, "container_put", theirs, other["character_id"], other["inventory_container_id"])[1] == "OK"
    assert call(db, "item_drop", mine, ch, 0, 0, 3, 0, 0, 0)[1] == "OK"
    assert call(db, "container_take", theirs, ch)[1] == "NOT_OWNER"
    with db.cursor() as cur:
        cur.execute("SELECT container_id FROM items WHERE id=%s", (theirs,))
        assert cur.fetchone()["container_id"] == other["inventory_container_id"]


def test_death_drops_everything_and_marks_dead(db, character):
    ch, cid = character["character_id"], character["inventory_container_id"]
    a, b = make_world_item(db), make_world_item(db)
    call(db, "item_pickup", a, ch)
    call(db, "container_put", a, ch, cid)
    call(db, "item_pickup", b, ch)
    ok, code, payload = call(db, "character_death_drop", ch, 100.0, 200.0, 5.0, 0, 0)
    assert code == "OK" and payload["dropped"] == 2
    with db.cursor() as cur:
        cur.execute("SELECT alive FROM characters WHERE id=%s", (ch,))
        assert cur.fetchone()["alive"] == 0
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id IN (%s,%s) AND x IS NOT NULL", (a, b))
        assert cur.fetchone()["n"] == 2
        # upstream death.pwn: a Clothes item with the dead character's skin, 1 m east of the body
        cur.execute("SELECT type_uname, data, x, y FROM items WHERE id=%s", (payload["clothes_item_id"],))
        row = cur.fetchone()
        assert row["type_uname"] == "Clothes" and json.loads(row["data"]) == {"skin": 0}
        assert (row["x"], row["y"]) == (101.0, 200.0)


def test_concurrent_pickup_exactly_one_winner(db):
    # Several rounds, both workers released together by a barrier: the first round on a near-empty
    # items table is serialised by a full-scan row lock, later rounds use uq_items_holder_kind (gap locks).
    for _ in range(10):
        results, chars = [], []
        for _ in range(2):
            with db.cursor() as cur:
                cur.execute("INSERT INTO accounts (name, password_hash) VALUES (CONCAT('c', UUID_SHORT()), REPEAT('x', 60))")
                acc = cur.lastrowid
            chars.append(call(db, "character_create", acc, 0, 0.0, 0.0, 3.0, 0.0, 100.0, 80.0, 0.0)[2]["character_id"])
        item = make_world_item(db)
        start = threading.Barrier(len(chars))

        def worker(ch):
            conn = pymysql.connect(host=ARGS.host, port=ARGS.port, user=ARGS.user, password=ARGS.password, database=DB,
                                   autocommit=True, charset="utf8mb4", cursorclass=pymysql.cursors.DictCursor)
            start.wait()
            for _ in range(20):
                try:
                    results.append(call(conn, "item_pickup", item, ch)[1])
                except pymysql.err.MySQLError as e:
                    results.append(f"ERROR {e.args[0]}")
            conn.close()

        threads = [threading.Thread(target=worker, args=(c,)) for c in chars]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert results.count("OK") == 1 and set(results) <= {"OK", "NOT_IN_WORLD", "HANDS_FULL"}, results


def test_create_in_container_and_destroy(db, character):
    ch, cid = character["character_id"], character["inventory_container_id"]
    ok, code, payload = call(db, "item_create_in_container", "T_Knife", cid)
    assert code == "OK" and payload["slot"] == 0
    assert call(db, "item_create_in_container", "Nope", cid)[1] == "UNKNOWN_TYPE"
    assert call(db, "item_destroy", payload["item_id"], 999999)[1] == "NOT_OWNED"
    assert call(db, "item_destroy", payload["item_id"], ch)[1] == "OK"
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id=%s", (payload["item_id"],))
        assert cur.fetchone()["n"] == 0


def test_transfer_world_and_weapon_unload(db, character):
    ch = character["character_id"]
    wep = make_world_item(db, "T_Knife", 5.0, 6.0, 3.0)
    tin = make_world_item(db, "T_Wrench", 5.5, 6.0, 3.0)
    assert call(db, "item_pickup", wep, ch)[1] == "OK"
    ok, code, payload = call(
        db,
        "item_transfer_world",
        ch,
        wep,
        tin,
        '{"mag":10,"reserve":0,"ammoItem":"Ammo9mm"}',
        '{"rounds":0}',
        1,
        0,
    )
    assert (ok, code) == (1, "OK") and payload["deleted_world"] == 1
    with db.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id=%s", (tin,))
        assert cur.fetchone()["n"] == 0
        cur.execute("SELECT COUNT(*) AS n FROM world_items_pos WHERE item_id=%s", (tin,))
        assert cur.fetchone()["n"] == 0

    ok_u, code_u, payload_u = call(
        db,
        "weapon_unload",
        ch,
        wep,
        '{"mag":0,"reserve":0}',
        "T_Wrench",
        '{"rounds":10}',
        5.0,
        6.5,
        3.0,
        0.0,
        0,
        0,
    )
    assert (ok_u, code_u) == (1, "OK")
    ammo_id = payload_u["ammo_item_id"]
    with db.cursor() as cur:
        cur.execute("SELECT data FROM items WHERE id=%s", (wep,))
        assert "0" in cur.fetchone()["data"]
        cur.execute("SELECT type_uname, x FROM items WHERE id=%s", (ammo_id,))
        row = cur.fetchone()
        assert row["type_uname"] == "T_Wrench" and row["x"] == 5.0


def test_disarm_and_create_held(db, character):
    ch = character["character_id"]
    with db.cursor() as cur:
        cur.execute("INSERT INTO accounts (name, password_hash) VALUES (CONCAT('d', UUID_SHORT()), REPEAT('x', 60))")
        other = call(db, "character_create", cur.lastrowid, 0, 0.0, 0.0, 3.0, 0.0, 100.0, 80.0, 0.0)[2]["character_id"]
    ok_c, code_c, payload_c = call(db, "item_create_held", "T_Knife", other)
    assert (ok_c, code_c) == (1, "OK")
    knife_id = payload_c["item_id"]
    assert call(db, "item_create_held", "T_Knife", other)[1] == "HANDS_FULL"

    ok_d, code_d, _ = call(db, "item_disarm", ch, other, knife_id)
    assert (ok_d, code_d) == (1, "OK")
    with db.cursor() as cur:
        cur.execute("SELECT holder_char_id, holder_kind FROM items WHERE id=%s", (knife_id,))
        row = cur.fetchone()
        assert row["holder_char_id"] == ch and row["holder_kind"] == "held"


def test_gear_wear_and_unwear(db, character):
    ch = character["character_id"]
    inv = character["inventory_container_id"]
    hat1 = make_world_item(db, "T_Wrench")
    hat2 = make_world_item(db, "T_Wrench")

    # Pickup hat1 into hands
    assert call(db, "item_pickup", hat1, ch)[1] == "OK"

    # Wear hat1
    ok, code, payload = call(db, "item_wear", hat1, ch, "hat")
    assert (ok, code) == (1, "OK")
    assert payload["slot"] == "hat"
    with db.cursor() as cur:
        cur.execute("SELECT holder_char_id, holder_kind FROM items WHERE id=%s", (hat1,))
        r = cur.fetchone()
        assert r["holder_char_id"] == ch and r["holder_kind"] == "hat"

    # Hands are now free. Pickup hat2 into hands.
    assert call(db, "item_pickup", hat2, ch)[1] == "OK"

    # Wear hat2 -> should swap with hat1 (hat1 goes back to held)
    ok_sw, code_sw, payload_sw = call(db, "item_wear", hat2, ch, "hat")
    assert (ok_sw, code_sw) == (1, "OK")
    assert payload_sw["swapped_id"] == hat1
    with db.cursor() as cur:
        cur.execute("SELECT holder_kind FROM items WHERE id=%s", (hat1,))
        assert cur.fetchone()["holder_kind"] == "held"
        cur.execute("SELECT holder_kind FROM items WHERE id=%s", (hat2,))
        assert cur.fetchone()["holder_kind"] == "hat"

    # Drop held hat1
    assert call(db, "item_drop", hat1, ch, 0, 0, 3, 0, 0, 0)[1] == "OK"

    # Hands are empty: unwear hat2 -> goes to held
    ok_un, code_un, payload_un = call(db, "item_unwear", ch, "hat")
    assert (ok_un, code_un) == (1, "OK")
    assert payload_un["destination"] == "held"
    with db.cursor() as cur:
        cur.execute("SELECT holder_kind FROM items WHERE id=%s", (hat2,))
        assert cur.fetchone()["holder_kind"] == "held"

    # Put hat2 in inventory container slot 0
    assert call(db, "container_put", hat2, ch, inv)[1] == "OK"

    # Wear directly from inventory
    ok_w_inv, code_w_inv, _ = call(db, "item_wear", hat2, ch, "hat")
    assert (ok_w_inv, code_w_inv) == (1, "OK")
    with db.cursor() as cur:
        cur.execute("SELECT holder_kind, container_id FROM items WHERE id=%s", (hat2,))
        r2 = cur.fetchone()
        assert r2["holder_kind"] == "hat" and r2["container_id"] is None


def test_safebox_and_tent_containers(db, character):
    ch = character["character_id"]
    box = make_world_item(db, "T_Wrench")
    with db.cursor() as cur:
        cur.execute("INSERT INTO containers (kind, size, owner_item_id) VALUES ('safebox', 10, %s)", (box,))
        box_cont = cur.lastrowid

    it = make_world_item(db, "T_Wrench")
    assert call(db, "item_pickup", it, ch)[1] == "OK"

    # Put into world container
    ok, code, _ = call(db, "container_put", it, ch, box_cont)
    assert (ok, code) == (1, "OK")
    with db.cursor() as cur:
        cur.execute("SELECT container_id, slot FROM items WHERE id=%s", (it,))
        r = cur.fetchone()
        assert r["container_id"] == box_cont and r["slot"] == 0

    # Take back from world container
    ok_take, code_take, _ = call(db, "container_take", it, ch)
    assert (ok_take, code_take) == (1, "OK")
    with db.cursor() as cur:
        cur.execute("SELECT holder_char_id, holder_kind, container_id FROM items WHERE id=%s", (it,))
        r2 = cur.fetchone()
        assert r2["holder_char_id"] == ch and r2["holder_kind"] == "held" and r2["container_id"] is None
