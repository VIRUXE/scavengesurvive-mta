import json

from tests.sql.conftest import call
from tests.sql.test_cooking import item_data, item_row, make_world_item

IDLE = '{"machine":{"fuel":20}}'
COOKING = '{"machine":{"fuel":20,"cooking":{"at":1,"ms":2}}}'
DONE = '{"machine":{"fuel":13}}'


def machine_with_container(db, data=COOKING):
    machine = make_world_item(db, "ScrapMachine", data=data)
    with db.cursor() as cur:
        cur.execute("INSERT INTO containers (kind, size, owner_item_id) VALUES ('safebox', 12, %s)", (machine,))
        container = cur.lastrowid
    return machine, container


def contents(db, container):
    with db.cursor() as cur:
        cur.execute("SELECT id, type_uname, slot, data FROM items WHERE container_id=%s ORDER BY slot", (container,))
        return cur.fetchall()


def test_finish_swaps_the_contents_in_slot_order(db):
    machine, container = machine_with_container(db)
    for _ in range(2):
        assert call(db, "item_create_in_container", "Wrench", container)[1] == "OK"
    results = json.dumps([{"uname": "ScrapMetal", "data": ""}, {"uname": "Bottle", "data": '{"amount":0.3,"liquid":"Water"}'}])
    ok, code, payload = call(db, "machine_finish", machine, COOKING, DONE, container, results)
    assert (ok, code, payload) == (1, "OK", {"removed": 2, "created": 2})
    rows = contents(db, container)
    assert [(r["type_uname"], r["slot"]) for r in rows] == [("ScrapMetal", 0), ("Bottle", 1)]
    assert rows[0]["data"] is None
    assert json.loads(rows[1]["data"]) == {"amount": 0.3, "liquid": "Water"}
    assert item_data(db, machine) == {"machine": {"fuel": 13}}


def test_finish_with_nothing_inside_and_no_results_only_writes_the_machine(db):
    machine, container = machine_with_container(db)
    assert call(db, "machine_finish", machine, COOKING, DONE, container, "[]") == (1, "OK", {"removed": 0, "created": 0})
    assert contents(db, container) == []


def test_finish_with_stale_machine_data_is_busy_and_keeps_the_contents(db):
    machine, container = machine_with_container(db)
    assert call(db, "item_create_in_container", "Wrench", container)[1] == "OK"
    assert call(db, "machine_finish", machine, IDLE, DONE, container, '[{"uname":"ScrapMetal","data":""}]')[:2] == (0, "BUSY")
    assert [r["type_uname"] for r in contents(db, container)] == ["Wrench"]
    assert json.loads(item_row(db, machine)["data"]) == json.loads(COOKING)


def test_finish_refuses_a_container_the_machine_does_not_own(db):
    machine, _ = machine_with_container(db)
    other, other_container = machine_with_container(db, data=IDLE)
    assert call(db, "machine_finish", machine, COOKING, DONE, other_container, "[]")[:2] == (0, "NOT_OWNER")
    assert json.loads(item_row(db, machine)["data"]) == json.loads(COOKING)
    assert json.loads(item_row(db, other)["data"]) == json.loads(IDLE)
