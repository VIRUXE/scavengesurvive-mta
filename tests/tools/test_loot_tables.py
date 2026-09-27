from pathlib import Path

from tools.convert import loot_tables as lt

FX = Path(__file__).parent / "fixtures"


def test_parses_header_comments_and_optional_columns():
    name, table = lt.parse_ltb((FX / "world_civilian.ltb").read_bytes())
    assert name == "world_civilian" and table["mult"] == 1.0
    assert table["entries"][0] == {"weight": 38.0, "uname": "Wrench", "perLimit": 3, "serverLimit": 0}
    assert table["entries"][2] == {"weight": 3.0, "uname": "SniperRifle", "perLimit": 1, "serverLimit": 0}
    assert len(table["entries"]) == 3


def test_render_is_sorted_lua():
    lua = lt.render_lua({"b": {"mult": 1.0, "entries": []}, "a": {"mult": 2.0, "entries": []}})
    assert lua.index("M.a =") < lua.index("M.b =")


def test_non_identifier_keys_are_bracketed():
    lua = lt.render_lua({"9lives": {"mult": 1.0, "entries": []}, "end": {"mult": 1.0, "entries": []}})
    assert 'M["9lives"] =' in lua and 'M["end"] =' in lua


def test_unames_resolve_case_insensitively_like_upstream():
    # upstream loot.pwn: GetItemTypeFromUniqueName(uname, true) ignores case; world_civilian.ltb has "1.0,	whisky"
    tables = {"t": {"mult": 1.0, "entries": [{"weight": 1.0, "uname": "whisky", "perLimit": 3, "serverLimit": 0},
                                             {"weight": 1.0, "uname": "Nope", "perLimit": 3, "serverLimit": 0}]}}
    unknown = lt.canonicalise(tables, ["Whisky", "Wrench"])
    assert tables["t"]["entries"] == [{"weight": 1.0, "uname": "Whisky", "perLimit": 3, "serverLimit": 0}]
    assert unknown == [("t", "Nope")]
