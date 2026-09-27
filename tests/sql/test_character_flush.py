from tests.sql.conftest import call


def test_character_flush_updates_rows(db, character):
    ch = character["character_id"]
    rows = f'[[{{"id":{ch},"hp":55.5,"food":33.25,"bleed":0.125,"x":1,"y":2,"z":3,"rz":4}}]]'
    ok, code, payload = call(db, "character_flush", rows)
    assert code == "OK" and payload["updated"] == 1
    with db.cursor() as cur:
        cur.execute("SELECT hp, food, x FROM characters WHERE id=%s", (ch,))
        r = cur.fetchone()
        assert (round(r["hp"], 2), round(r["food"], 2), r["x"]) == (55.5, 33.25, 1.0)


def test_character_flush_ignores_dead(db, character):
    ch = character["character_id"]
    call(db, "character_death_drop", ch, 0.0, 0.0, 3.0, 0, 0)
    ok, code, payload = call(db, "character_flush", f'[[{{"id":{ch},"hp":99,"food":99,"bleed":0,"x":0,"y":0,"z":0,"rz":0}}]]')
    assert payload["updated"] == 0
