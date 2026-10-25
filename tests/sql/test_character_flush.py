from tests.sql.conftest import call
from tests.sql.test_item_graph import CLOTHES, RING


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
    call(db, "character_death_drop", ch, 0.0, 0.0, 3.0, 0, 0, RING, CLOTHES)
    ok, code, payload = call(db, "character_flush", f'[[{{"id":{ch},"hp":99,"food":99,"bleed":0,"x":0,"y":0,"z":0,"rz":0}}]]')
    assert payload["updated"] == 0


def test_character_flush_writes_skills_only_when_sent(db, character):
    ch = character["character_id"]
    skills = '[[\\"Repair\\",0.020000]]'
    rows = f'[[{{"id":{ch},"hp":50,"food":50,"bleed":0,"x":0,"y":0,"z":0,"rz":0,"skills":"{skills}"}}]]'
    call(db, "character_flush", rows)
    call(db, "character_flush", f'[[{{"id":{ch},"hp":40,"food":40,"bleed":0,"x":0,"y":0,"z":0,"rz":0}}]]')
    with db.cursor() as cur:
        cur.execute("SELECT JSON_VALUE(skills, '$[0][0]') AS name, JSON_VALUE(skills, '$[0][1]') AS amount FROM characters WHERE id=%s", (ch,))
        r = cur.fetchone()
        assert r["name"] == "Repair" and float(r["amount"]) == 0.02


def test_character_flush_writes_infection_and_drugs(db, character):
    ch = character["character_id"]
    drugs = '[[\\"Morphine\\",245000]]'
    rows = f'[[{{"id":{ch},"hp":50,"food":50,"bleed":0,"x":0,"y":0,"z":0,"rz":0,"infection":3,"drugs":"{drugs}"}}]]'
    call(db, "character_flush", rows)
    call(db, "character_flush", f'[[{{"id":{ch},"hp":40,"food":40,"bleed":0,"x":0,"y":0,"z":0,"rz":0}}]]')
    with db.cursor() as cur:
        cur.execute("SELECT infection, JSON_VALUE(drugs, '$[0][0]') AS name, JSON_VALUE(drugs, '$[0][1]') AS ms FROM characters WHERE id=%s", (ch,))
        r = cur.fetchone()
        assert r["infection"] == 3 and r["name"] == "Morphine" and int(r["ms"]) == 245000
