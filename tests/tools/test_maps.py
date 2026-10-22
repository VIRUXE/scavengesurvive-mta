from pathlib import Path

import pytest

from tools import gen_vanilla_objects
from tools.convert import maps

FX = Path(__file__).parent / "fixtures"


def read_raw(path):
    with path.open(encoding="utf-8", newline="") as f:
        return f.read()


def parsed():
    return maps.parse_map(maps.read_text(FX / "map_excerpt.map"), "LS/Excerpt.map")


def test_create_forms_and_file_defaults():
    p = parsed()
    objs = p["objects"]
    # plain 7-arg CreateObject takes the file defaults (-1, -1, 350)
    assert objs[0] == [11692, 199.344, 1943.79, 18.2031, 0, 0, 0, -1, -1, 350.0]
    # options() changes the defaults for the lines after it
    assert objs[1][7:] == [0, 0, 350.0]
    # 11-arg CreateDynamicObject: explicit world/interior/range; -1 world falls back to the file default
    assert objs[2] == [3168, -640.5, 2717.2, 71.4, 0.0, 0.0, 42.0, 0, 0, 7.0]
    # 8-arg form: the trailing number is the draw distance, not the world (upstream mis-read it)
    assert objs[3] == [2938, 2527.4, -1683.4, 1014.4, 0.0, 270.0, 90.0, 0, 0, 7.0]
    assert p["counts"]["eight_arg"] == 1


def test_second_statement_on_a_line_is_dropped_like_upstream():
    p = parsed()
    assert p["counts"]["dropped_tail"] == 2  # "...);CreateObject(...)" and "...);0, 0, 6000"
    assert len(p["objects"]) == 6


def test_removals_materials_and_ignored_lines():
    p = parsed()
    assert p["removals"] == [[16203, 199.344, 1943.79, 18.2031, 250.0], [16590, 199.344, 1943.79, 18.2031, 250.0]]
    assert p["materials"] == [{"object": 6, "call": "SetObjectMaterial", "args": 'objectid, 0, 5145, "docks_las2", "dockwall1", 0xFFFFFFFF'}]
    assert p["counts"]["legacy_header"] == 1
    assert p["counts"]["ignored_calls"] == 2  # SetDynamicObjectMaterial(, ...) and objmat(...)


def test_unknown_call_is_an_error():
    with pytest.raises(maps.UnparsedLine):
        maps.parse_map("Frobnicate(1, 2, 3)\n", "x.map")
    with pytest.raises(maps.UnparsedLine):
        maps.parse_map("CreateObject(1, 2, 3)\n", "x.map")


def test_crlf_input_is_normalised(tmp_path):
    crlf = tmp_path / "a.map"
    crlf.write_bytes(b"CreateObject(1234, 1, 2, 3, 0, 0, 90);\r\nCreateObject(1235, 1, 2, 3, 0, 0, 90);\r\n")
    assert len(maps.parse_map(maps.read_text(crlf), "a.map")["objects"]) == 2


def test_zone_lua_is_loadable_shape_and_header():
    p = parsed()
    lua = maps.render_zone_lua("LS", ["Excerpt.map"], p["objects"], p["removals"], p["materials"])
    assert lua.startswith(maps.MAPS_HEADER)
    assert "CC BY-SA 4.0" in lua and "MPL" not in lua
    assert "{ 11692, 199.344, 1943.79, 18.2031, 0, 0, 0, -1, -1, 350.0 }," in lua
    assert lua.count("{ 16203, ") == 1


def test_classification_uses_vanilla_list_and_samp_ide():
    vanilla, samp = gen_vanilla_objects.load(), maps.load_samp_ids()
    assert maps.classify(3168, vanilla, samp) == "vanilla"
    assert maps.classify(19312, vanilla, samp) == "samp"
    assert maps.classify(11692, vanilla, samp) == "samp"
    assert maps.classify(18631 + 20000, vanilla, samp) == "samp_unknown"
    assert maps.classify(20000, vanilla, samp) in ("samp", "samp_unknown")
    assert maps.classify(342, vanilla, samp) == "vanilla"  # grenade: weapon models are placeable objects
    assert maps.classify(0, vanilla, samp) == "unknown"


def test_vanilla_ranges_round_trip(tmp_path):
    ids = {321, 322, 323, 400, 18630}
    text = gen_vanilla_objects.render(gen_vanilla_objects.to_ranges(ids))
    assert "321-323" in text and "400" in text
    f = tmp_path / "v.txt"
    f.write_text(text, encoding="utf-8")
    assert gen_vanilla_objects.load(f) == ids
    assert gen_vanilla_objects.parse_object_ids("objs\n5390, a, b, 150, 0\nend\ncars\n400, x\nend\ntobj\n1, t, t, 100, 0, 20, 6\nend\n") == {5390, 1}


def test_parse_regions_strips_closing_point_and_winds_ccw():
    raw = '''{
        "LS": [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
        "SF": [[0, 0], [0, 10], [10, 10], [10, 0], [0, 0]],
        "FC_East": [[1, 1], [2, 1], [2, 2], [1, 1]]
    }'''
    polys = maps.parse_regions(raw)
    assert set(polys) == {"ls", "sf"}
    assert len(polys["ls"]) == 4 and len(polys["sf"]) == 4
    assert maps.signed_area(polys["ls"]) > 0
    assert maps.signed_area(polys["sf"]) > 0
    lua = maps.render_zones_lua(polys)
    assert lua.startswith(maps.ZONES_HEADER) and "ls = {" in lua and "sf = {" in lua


def test_convert_writes_zone_files_meta_and_census(tmp_path):
    src = tmp_path / "upstream" / "scriptfiles" / "maps"
    (src / "LS").mkdir(parents=True)
    (src / "LS" / "A.map").write_text(read_raw(FX / "map_excerpt.map"), encoding="utf-8")
    (src / "LS" / "B.map").write_text("CreateObject(1234, 1, 2, 3, 0, 0, 90);\n", encoding="utf-8")
    (src / "_").mkdir()  # upstream skips a directory named "_"
    (src / "_" / "C.map").write_text("CreateObject(1234, 1, 2, 3, 0, 0, 90);\n", encoding="utf-8")
    out = tmp_path / "maps"
    report = tmp_path / "census.md"
    zones = maps.convert(tmp_path / "upstream", out, report)
    assert list(zones) == ["LS"] and zones["LS"]["files"] == ["LS/A.map", "LS/B.map"]
    assert len(zones["LS"]["objects"]) == 7
    assert (out / "data" / "LS.lua").is_file() and (out / "data" / "index.lua").is_file()
    assert (out / "data" / "zones.lua").is_file()
    meta = (out / "meta.xml").read_text()
    assert '<file src="data/LS.lua"/>' in meta and '<export function="getZoneAt" type="server"/>' in meta
    text = report.read_text(encoding="utf-8")
    assert "| LS | 2 | 7 |" in text and "| 11692 |" in text
