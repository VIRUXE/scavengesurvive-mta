from pathlib import Path

import pytest

from tools.convert import zones

FX = Path(__file__).parent / "fixtures"


def test_parses_five_and_six_argument_forms():
    rows = zones.parse_zone((FX / "zone_excerpt.pwn").read_text(newline=""), zone="ls")
    assert rows[0] == {"x": 2241.932128, "y": -1258.510009, "z": 22.936239, "table": "world_civilian",
                       "weight": 20.0, "size": 3, "zone": "ls", "dimension": 0, "interior": 0}
    assert rows[1]["size"] == -1 and rows[1]["weight"] == 20.0
    assert rows[2]["weight"] == 30.0 and rows[2]["size"] == 5


def test_sql_seed_chunks_and_point():
    rows = zones.parse_zone((FX / "zone_excerpt.pwn").read_text(newline=""), zone="ls")
    sql = zones.render_sql(rows)
    assert "POINT(2241.932128, -1258.510009)" in sql and sql.count("INSERT INTO loot_spawns") == 1
    assert "INSERT INTO loot_spawn_state" in sql


def test_unparsed_line_is_an_error():
    with pytest.raises(zones.UnparsedLine):
        zones.parse_zone("\tCreateStaticLootSpawn(1, 2, 3, someVar, 20);\n", zone="ls")


def test_block_comments_are_ignored():
    src = '/*\n\tCreateStaticLootSpawn(1.0, 2.0, 3.0,\tGetLootIndexFromName("world_medical"), 30.0);\n*/\n'
    assert zones.parse_zone(src, zone="ls") == []
