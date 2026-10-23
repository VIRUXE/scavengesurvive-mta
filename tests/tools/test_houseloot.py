import math

from tools.convert import houseloot


def test_offsets_follow_the_house_rotation():
    # no rotation: the offset is added as is
    x, y, z = houseloot.attached_pos(100, 200, 10, 0, 0, 0, 1, 2, 3)
    assert (x, y, z) == (101, 202, 13)
    # 90 degrees around z (SA-MP rotation): +x offset turns into +y
    x, y, z = houseloot.attached_pos(0, 0, 0, 0, 0, 90, 1, 0, 0)
    assert math.isclose(x, 0, abs_tol=1e-9) and math.isclose(y, 1, abs_tol=1e-9) and math.isclose(z, 0, abs_tol=1e-9)


def test_half_the_houses_are_selected_deterministically():
    assert houseloot.selected(10.00, 20.00) is True
    assert houseloot.selected(10.01, 20.00) is False
    assert houseloot.selected(10.00, 20.00) == houseloot.selected(10.00, 20.00)


def test_house_spawns_use_the_upstream_tables_and_offsets():
    objects = {
        "SF": [
            [19490, 10.0, 20.0, 5.0, 0.0, 0.0, 0.0, -1, -1, 350.0],  # selected: 4 points
            [19494, 10.01, 20.0, 5.0, 0.0, 0.0, 0.0, -1, -1, 350.0],  # not selected
            [1234, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1, -1, 350.0],  # not a house
        ],
        "LS": [[19496, 30.0, 40.0, 5.0, 0.0, 0.0, 180.0, -1, -1, 350.0]],  # selected: 3 points
    }
    rows = houseloot.house_spawns(objects)
    assert len(rows) == 7
    first = [r for r in rows if r["zone"] == "sf"][0]
    assert (first["x"], first["y"], first["z"]) == (10.0 - 3.73, 20.0 - 3.33, 5.0 - 0.42)
    ls = [r for r in rows if r["zone"] == "ls"][0]
    assert math.isclose(ls["x"], 30.0 + 2.29, abs_tol=1e-3) and math.isclose(ls["y"], 40.0 + 0.57, abs_tol=1e-3)
    sql = houseloot.render_sql(rows)
    assert sql.count("'world_civilian',20.0,3,0,0,") == 7
    assert "INSERT IGNORE INTO loot_spawn_state" in sql
    assert "POINT(6.27, 16.67)" in sql
