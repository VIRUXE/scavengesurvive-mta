from tests.sql.conftest import call


def _loot_spawn(db):
    with db.cursor() as cur:
        cur.execute("SELECT id, zone FROM loot_spawns ORDER BY id LIMIT 1")
        r = cur.fetchone()
        return r["id"], r["zone"]


def test_world_budget_upsert_keeps_allowance_but_recomputes_cap(db):
    with db.cursor() as cur:
        cur.execute("DELETE FROM world_budget WHERE category='t'")
        cur.execute("INSERT INTO world_budget (category, zone, cap, remainder, allowance) VALUES ('t', 'z', 100, 0.25, 40)")
        cur.execute("INSERT INTO world_budget (category, zone, cap, remainder, allowance) VALUES ('t', 'z', 30, 0, 30) "
                    "ON DUPLICATE KEY UPDATE cap = VALUES(cap), allowance = LEAST(allowance, VALUES(cap))")
        cur.execute("SELECT cap, remainder, allowance FROM world_budget WHERE category='t' AND zone='z'")
        r = cur.fetchone()
        assert (r["cap"], round(r["remainder"], 2), r["allowance"]) == (30, 0.25, 30)
        cur.execute("DELETE FROM world_budget WHERE category='t'")


def test_vehicle_spawn_state_follows_its_point(db):
    with db.cursor() as cur:
        cur.execute("INSERT INTO vehicle_spawns (x, y, z, rz, group_name, categories, sizes, file, pos) "
                    "VALUES (1, 2, 3, 0, 'Civilian', 'CT', 'SM', 'test', POINT(1, 2))")
        sid = cur.lastrowid
        cur.execute("INSERT INTO vehicle_spawn_state (spawn_id, next_roll_at) VALUES (%s, DATE_ADD(NOW(), INTERVAL 1 HOUR))", (sid,))
        cur.execute("SELECT COUNT(*) AS n FROM vehicle_spawn_state WHERE spawn_id=%s AND next_roll_at > NOW()", (sid,))
        assert cur.fetchone()["n"] == 1
        cur.execute("DELETE FROM vehicle_spawns WHERE id=%s", (sid,))
        cur.execute("SELECT COUNT(*) AS n FROM vehicle_spawn_state WHERE spawn_id=%s", (sid,))
        assert cur.fetchone()["n"] == 0


def test_vehicles_start_on_their_point_and_unused(db):
    with db.cursor() as cur:
        cur.execute("SELECT id FROM vehicle_spawns ORDER BY id LIMIT 1")
        sid = cur.fetchone()["id"]
        cur.execute("INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz) VALUES (%s, 'Bobcat', 422, 0, 0, 0, 0)", (sid,))
        vid = cur.lastrowid
        cur.execute("SELECT left_spawn, last_used_at FROM vehicles WHERE id=%s", (vid,))
        r = cur.fetchone()
        assert (r["left_spawn"], r["last_used_at"]) == (0, None)
        cur.execute("DELETE FROM vehicles WHERE id=%s", (vid,))


def test_item_create_records_the_loot_zone_and_pickup_keeps_it(db, character):
    sid, zone = _loot_spawn(db)
    ok, code, payload = call(db, "item_create", "T_Wrench", None, None, 1.0, 2.0, 3.0, 0.0, 0, 0, sid, None)
    assert ok == 1 and code == "OK", code
    item = payload["item_id"]
    with db.cursor() as cur:
        cur.execute("SELECT loot_zone FROM items WHERE id=%s", (item,))
        assert cur.fetchone()["loot_zone"] == zone
    ok, code, _ = call(db, "item_pickup", item, character["character_id"])
    assert ok == 1 and code == "OK", code
    with db.cursor() as cur:
        cur.execute("SELECT loot_spawn_id, loot_zone, holder_char_id FROM items WHERE id=%s", (item,))
        r = cur.fetchone()
        assert (r["loot_spawn_id"], r["loot_zone"], r["holder_char_id"]) == (None, zone, character["character_id"])
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE loot_zone=%s AND (1 = 1 OR holder_char_id IS NULL)", (zone,))
        assert cur.fetchone()["n"] >= 1
        cur.execute("SELECT COUNT(*) AS n FROM items WHERE id=%s AND loot_zone=%s AND (0 = 1 OR holder_char_id IS NULL)", (item, zone))
        assert cur.fetchone()["n"] == 0  # count_carried = 0 leaves carried items out


def test_item_without_a_loot_point_has_no_zone(db):
    ok, code, payload = call(db, "item_create", "T_Wrench", None, None, 1.0, 2.0, 3.0, 0.0, 0, 0, None, None)
    assert ok == 1 and code == "OK", code
    with db.cursor() as cur:
        cur.execute("SELECT loot_zone FROM items WHERE id=%s", (payload["item_id"],))
        assert cur.fetchone()["loot_zone"] is None


def test_reroll_setting_is_gone_and_budget_settings_seeded(db):
    with db.cursor() as cur:
        cur.execute("SELECT skey FROM settings WHERE skey IN ('loot.reroll_minutes', 'loot.cap_multiplier', "
                    "'vehicles.cooldown_hours', 'world.refill_interval_s') ORDER BY skey")
        assert [r["skey"] for r in cur.fetchall()] == ["loot.cap_multiplier", "vehicles.cooldown_hours", "world.refill_interval_s"]
