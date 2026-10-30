from pathlib import Path

import pytest

from tools.convert import zones

FX = Path(__file__).parent / "fixtures"


def read_raw(path):
    # keep the fixture's line endings as-is (Path.read_text(newline=...) needs Python 3.13; pyproject allows 3.11)
    with path.open(encoding="utf-8", newline="") as f:
        return f.read()


def test_parses_five_and_six_argument_forms():
    rows = zones.parse_zone(read_raw(FX / "zone_excerpt.pwn"), zone="ls")
    assert rows[0] == {"x": 2241.932128, "y": -1258.510009, "z": 22.936239, "table": "world_civilian",
                       "weight": 20.0, "size": 3, "zone": "ls", "dimension": 0, "interior": 0}
    assert rows[1]["size"] == -1 and rows[1]["weight"] == 20.0
    assert rows[2]["weight"] == 30.0 and rows[2]["size"] == 5


def test_sql_seed_chunks_and_point():
    rows = zones.parse_zone(read_raw(FX / "zone_excerpt.pwn"), zone="ls")
    sql = zones.render_sql(rows)
    assert "POINT(2241.932128, -1258.510009)" in sql and sql.count("INSERT INTO loot_spawns") == 1
    assert "INSERT INTO loot_spawn_state" in sql


def test_unparsed_line_is_an_error():
    with pytest.raises(zones.UnparsedLine):
        zones.parse_zone("\tCreateStaticLootSpawn(1, 2, 3, someVar, 20);\n", zone="ls")


def test_block_comments_are_ignored():
    src = '/*\n\tCreateStaticLootSpawn(1.0, 2.0, 3.0,\tGetLootIndexFromName("world_medical"), 30.0);\n*/\n'
    assert zones.parse_zone(src, zone="ls") == []


def test_parses_supply_drop_and_weapon_cache_points():
    supply, caches = zones.parse_drop_points(read_raw(FX / "zone_excerpt.pwn"), zone="bc")
    assert supply == [{"name": "Fort Carson", "x": 7.24142, "y": 959.9455, "z": 18.55249, "zone": "bc"}]
    assert caches == [{"x": -2016.65759, "y": -1053.53784, "z": 32.10938, "zone": "bc"}]
    sql = zones.render_drop_points_sql(supply, caches)
    assert "DELETE FROM supply_drop_points;" in sql and "('Fort Carson',7.24142,959.9455,18.55249,'bc')" in sql
    assert "INSERT INTO weapon_cache_points (x,y,z,zone) VALUES\n(-2016.65759,-1053.53784,32.10938,'bc');" in sql


def test_unparsed_drop_point_is_an_error():
    with pytest.raises(zones.UnparsedLine):
        zones.parse_drop_points('\tDefineSupplyDropPos("X", a, b, c);\n', zone="ls")


def test_parses_ladders_and_multi_line_ziplines():
    from tools.convert import features
    ladders, ziplines = features.parse_features(read_raw(FX / "zone_excerpt.pwn"), zone="fc")
    assert ladders == [{"x": -1056.0153, "y": -628.1323, "base": 32.0012, "top": 130.1213, "angle": 180.0, "zone": "fc"}]
    assert ziplines == [{"x1": 2159.08, "y1": -986.47, "z1": 70.59, "x2": 2063.3, "y2": -993.57, "z2": 59.38, "zone": "fc"}]
    lua = features.render_lua(ladders, ziplines)
    assert '{ -1056.0153, -628.1323, 32.0012, 130.1213, 180.0, "fc" },' in lua
    assert '{ 2159.08, -986.47, 70.59, 2063.3, -993.57, 59.38, "fc" },' in lua
    with pytest.raises(features.UnparsedLine):
        features.parse_features("CreateLadder(1.0, 2.0);", zone="fc")


def test_parses_fixed_items():
    from tools.convert import features
    src = ("\tCreateItem(item_Workbench, 318.60028, 1145.81543, 7.54844, 0.0, 0.0, -181.56007);\n"
           "\t// CreateItem(item_Medkit, 1.0, 2.0, 3.0);\n"
           "\tCreateItem(item_Barbecue, -2701.1328, 845.7422, 70.3828, 171.0);\n"
           "\tCreateItem(ItemType:2, 1.0, 2.0, 3.0, 66.0, 4.0, 0.0);\n")
    rows = features.parse_fixtures(src, zone="sf", unames=["NULL", "Knuckles", "GolfClub"])
    assert rows == [
        {"uname": "Workbench", "x": 318.60028, "y": 1145.81543, "z": 7.54844, "rz": -181.56007, "zone": "sf"},
        {"uname": "Barbecue", "x": -2701.1328, "y": 845.7422, "z": 70.3828, "rz": 171.0, "zone": "sf"},
        {"uname": "GolfClub", "x": 1.0, "y": 2.0, "z": 3.0, "rz": 0.0, "zone": "sf"},
    ]
    assert '{ "Workbench", 318.60028, 1145.81543, 7.54844, -181.56007, "sf" },' in features.render_lua([], [], rows)
    with pytest.raises(features.UnparsedLine):
        features.parse_fixtures("CreateItem(item_Medkit);", zone="sf")
