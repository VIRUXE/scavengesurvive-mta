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
        # corpse items despawn like loot (seeded loot.despawn_minutes, default 120)
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id IN (%s,%s) AND despawn_at > NOW() + INTERVAL 1 MINUTE",
                    (a, b))
        assert cur.fetchone()["n"] == 2


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


def test_create_bag_in_container_gets_its_own_container(db, character):
    cid = character["inventory_container_id"]
    ok, code, payload = call(db, "item_create_in_container", "T_Satchel", cid)
    assert code == "OK"
    with db.cursor() as cur:
        cur.execute("SELECT kind, size FROM containers WHERE owner_item_id=%s", (payload["item_id"],))
        assert cur.fetchone() == {"kind": "bag", "size": 7}
