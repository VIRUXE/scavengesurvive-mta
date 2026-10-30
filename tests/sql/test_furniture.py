from tests.sql.conftest import call
from tests.sql.test_cooking import item_data, item_row, make_world_item


def held(db, ch, uname):
    item = make_world_item(db, uname, 51.0, 61.0)
    assert call(db, "item_pickup", item, ch)[1] == "OK"
    return item


def test_put_shows_the_held_item_in_the_case(db, character):
    ch = character["character_id"]
    case = make_world_item(db, "GunCase")
    knife = held(db, ch, "Knife")
    assert call(db, "furniture_display_put", ch, knife, case, 5) == (1, "OK", {"display": "Knife"})
    row = item_row(db, knife)
    assert row["holder_char_id"] is None and row["container_id"] is not None and row["slot"] == 0
    assert item_data(db, case) == {"display": "Knife"}


def test_put_into_a_case_that_shows_an_item_is_refused(db, character):
    ch = character["character_id"]
    case = make_world_item(db, "Cupboard")
    assert call(db, "furniture_display_put", ch, held(db, ch, "Knife"), case, 5)[1] == "OK"
    second = held(db, ch, "Wrench")
    assert call(db, "furniture_display_put", ch, second, case, 5)[:2] == (0, "OCCUPIED")
    assert item_row(db, second)["holder_kind"] == "held"


def test_put_of_an_item_too_big_says_how_many_slots_are_missing(db, character):
    ch = character["character_id"]
    case = make_world_item(db, "GunCase")
    desk = held(db, ch, "Desk")
    assert call(db, "furniture_display_put", ch, desk, case, 5) == (0, "CONTAINER_FULL", {"required": 9})
    assert item_row(db, desk)["holder_kind"] == "held"
    assert item_data(db, case) is None


def test_put_only_into_a_gun_case_or_cupboard(db, character):
    ch = character["character_id"]
    desk = make_world_item(db, "Desk")
    assert call(db, "furniture_display_put", ch, held(db, ch, "Knife"), desk, 5)[:2] == (0, "NOT_FOUND")


def test_take_gives_the_shown_item_back_and_empties_the_case(db, character):
    ch = character["character_id"]
    case = make_world_item(db, "GunCase")
    knife = held(db, ch, "Knife")
    assert call(db, "furniture_display_put", ch, knife, case, 5)[1] == "OK"
    assert call(db, "furniture_display_take", ch, case) == (1, "OK", {"item_id": knife})
    row = item_row(db, knife)
    assert row["holder_char_id"] == ch and row["holder_kind"] == "held" and row["container_id"] is None
    assert item_data(db, case) == {}
    assert call(db, "furniture_display_take", ch, case)[:2] == (0, "EMPTY")


def test_take_with_full_hands_is_refused(db, character):
    ch = character["character_id"]
    case = make_world_item(db, "GunCase")
    knife = held(db, ch, "Knife")
    assert call(db, "furniture_display_put", ch, knife, case, 5)[1] == "OK"
    held(db, ch, "Wrench")
    assert call(db, "furniture_display_take", ch, case)[:2] == (0, "HANDS_FULL")
    assert item_row(db, knife)["container_id"] is not None
    assert item_data(db, case) == {"display": "Knife"}
