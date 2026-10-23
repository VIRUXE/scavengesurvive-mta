from tests.sql.conftest import call


def _spawn_id(db):
    with db.cursor() as cur:
        cur.execute("SELECT id FROM vehicle_spawns ORDER BY id LIMIT 1")
        return cur.fetchone()["id"]


def test_vehicle_flush_updates_live_rows(db):
    with db.cursor() as cur:
        cur.execute("INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, health, fuel, locked, damage) "
                    "VALUES (%s, 'Bobcat', 422, 1, 2, 3, 90, 450, 0.5, 0, '[{\"doors\":[0,1,0,0]}]')", (_spawn_id(db),))
        vid = cur.lastrowid
    rows = f'[[{{"id":{vid},"x":10,"y":20,"z":30,"rz":180,"health":321.5,"fuel":12.25,"locked":1}}]]'
    ok, code, payload = call(db, "vehicle_flush", rows)
    assert ok == 1 and code == "OK" and payload["updated"] == 1
    with db.cursor() as cur:
        cur.execute("SELECT x, rz, health, fuel, locked, damage FROM vehicles WHERE id=%s", (vid,))
        r = cur.fetchone()
        assert (r["x"], r["rz"], round(r["health"], 1), round(r["fuel"], 2), r["locked"]) == (10.0, 180.0, 321.5, 12.25, 1)
        assert '"doors"' in r["damage"]  # untouched by the flush


def test_vehicle_keeps_row_when_its_spawn_point_is_reseeded(db):
    sid = _spawn_id(db)
    with db.cursor() as cur:
        cur.execute("INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz) VALUES (%s, 'Sabre', 475, 0, 0, 0, 0)", (sid,))
        vid = cur.lastrowid
        cur.execute("DELETE FROM vehicle_spawns WHERE id=%s", (sid,))
        cur.execute("SELECT spawn_id FROM vehicles WHERE id=%s", (vid,))
        assert cur.fetchone()["spawn_id"] is None


def test_vehicle_trunk_container_and_trailer_fk(db, character):
    sid = _spawn_id(db)
    with db.cursor() as cur:
        cur.execute("INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, key_code, locked) "
                    "VALUES (%s, 'Bobcat', 422, 0, 0, 0, 0, 98765, 2)", (sid,))
        vid = cur.lastrowid
        # Create vehicle container
        cur.execute("INSERT INTO containers (kind, size, owner_vehicle_id) VALUES ('vehicle', 40, %s)", (vid,))
        cid = cur.lastrowid

    # Character puts held item into trunk container
    char_id = character["character_id"]
    ok, code, payload = call(db, "item_create_held", "Wrench", char_id)
    assert ok == 1
    item_id = payload["item_id"]

    ok, code, payload = call(db, "container_put", item_id, char_id, cid)
    assert ok == 1 and code == "OK" and payload["container_id"] == cid

    # Character takes item back out of trunk container
    ok, code, payload = call(db, "container_take", item_id, char_id)
    assert ok == 1 and code == "OK" and payload["item_id"] == item_id

    # Trailer FK: attach trailer, delete trailer, verify trailer_id becomes NULL
    with db.cursor() as cur:
        cur.execute("INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz) VALUES (%s, 'Trailer', 611, 0, 0, 0, 0)", (sid,))
        tid = cur.lastrowid
        cur.execute("UPDATE vehicles SET trailer_id=%s WHERE id=%s", (tid, vid))
        cur.execute("SELECT trailer_id FROM vehicles WHERE id=%s", (vid,))
        assert cur.fetchone()["trailer_id"] == tid
        cur.execute("DELETE FROM vehicles WHERE id=%s", (tid,))
        cur.execute("SELECT trailer_id FROM vehicles WHERE id=%s", (vid,))
        assert cur.fetchone()["trailer_id"] is None

        # Verify deleting vehicle cascades and deletes its trunk container
        cur.execute("DELETE FROM vehicles WHERE id=%s", (vid,))
        cur.execute("SELECT COUNT(*) AS n FROM containers WHERE id=%s", (cid,))
        assert cur.fetchone()["n"] == 0
