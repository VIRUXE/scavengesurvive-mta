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
