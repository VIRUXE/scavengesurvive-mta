from pathlib import Path

import pytest

from tools.convert import vspawn

FX = Path(__file__).parent / "fixtures"

INIT = """
	veht_Bobcat		= DefineVehicleType(422, "Bobcat",			vgroup_Civilian,	VEHICLE_CATEGORY_TRUCK,			VEHICLE_SIZE_MEDIUM,	60.0,		16.0,	"vehicle_industrial",		40,		76.0);
	veht_MountBike	= DefineVehicleType(510, "Mountain Bike",	vgroup_Civilian,	VEHICLE_CATEGORY_PUSHBIKE,		VEHICLE_SIZE_SMALL,		0.0,		0.0,	"vehicle_civilian",			2,		8.0,	VEHICLE_FLAG_NOT_LOCKABLE | VEHICLE_FLAG_NO_ENGINE);
	veht_Rhino		= DefineVehicleType(432, "Rhino",			vgroup_Military,	VEHICLE_CATEGORY_TRUCK,			VEHICLE_SIZE_LARGE,		1900.0,		392.0,	"vehicle_military",			12,		0.01);
	veht_Police1	= DefineVehicleType(596, "Police Car",		vgroup_Police,		VEHICLE_CATEGORY_CAR,			VEHICLE_SIZE_MEDIUM,	78.0,		12.5,	"vehicle_police",			42,		80.0);
	veht_Police2	= DefineVehicleType(597, "Police Car",		vgroup_Police,		VEHICLE_CATEGORY_CAR,			VEHICLE_SIZE_MEDIUM,	70.0,		13.0,	"vehicle_police",			42,		80.0);
	veht_BfInject	= DefineVehicleType(424, "BF Injection",	vgroup_Civilian,	VEHICLE_CATEGORY_TRUCK,			VEHICLE_SIZE_MEDIUM,	40.0,		8.0,	"vehicle_civilian",			24,		15.0,	VEHICLE_FLAG_NOT_LOCKABLE);

	SetVehicleTypeTrailerHitch(veht_Bobcat,		VEHICLE_SIZE_SMALL);
"""


def types():
    return vspawn.parse_vehicle_types(INIT)


def names():
    out = {}
    for t in types():
        out.setdefault(t["name"].lower(), t["uname"])
    return out


def test_vehicle_types_positional_fields_flags_and_hitch():
    ts = types()
    assert [t["uname"] for t in ts] == ["Bobcat", "MountBike", "Rhino", "Police1", "Police2", "BfInject"]
    bobcat = ts[0]
    assert bobcat["model"] == 422 and bobcat["name"] == "Bobcat" and bobcat["group"] == "Civilian"
    assert bobcat["category"] == "truck" and bobcat["size"] == "medium"
    assert bobcat["maxFuel"] == 60.0 and bobcat["fuelConsumption"] == 16.0 and bobcat["lootTable"] == "vehicle_industrial"
    assert bobcat["trunkSize"] == 40 and bobcat["spawnChance"] == 76.0 and bobcat["flags"] == 0
    assert bobcat["trailerHitch"] == "small" and "trailerHitch" not in ts[2]
    bike = ts[1]
    assert bike["flags"] == 3 and bike["notLockable"] and bike["noEngine"] and not bike["trailer"] and not bike["canSurf"]
    assert ts[2]["spawnChance"] == 0.01


def test_types_lua_first_name_wins_and_is_shaped_for_the_data_api():
    lua = vspawn.render_types_lua(types())
    assert lua.startswith(vspawn.HEADER)
    assert 'M.order = { "Bobcat", "MountBike", "Rhino", "Police1", "Police2", "BfInject" }' in lua
    assert 'M.byUname.Police2 = {' in lua and '"police car"] = "Police1"' in lua
    assert 'trailerHitch = "small"' in lua


def test_vpl_defaults_groups_types_and_overrides():
    raw = (FX / "vspawn_excerpt.vpl").read_bytes()
    assert b"\r\n" in raw  # upstream .vpl files are CRLF
    rows, dropped = vspawn.parse_vpl(vspawn.read_text(FX / "vspawn_excerpt.vpl"), "X.vpl", names())
    assert dropped == ["X.vpl:9: unknown vehicle type 'Coach'"]
    assert len(rows) == 7  # the ";"-commented Hydra line is skipped like upstream
    assert [r["group"] for r in rows] == ["Civilian", "Civilian", "Medical", None, None, "Civilian", "Civilian"]
    assert rows[0] == {"x": -615.67517, "y": 1807.696533, "z": 0.101, "rz": 261.713989, "group": "Civilian",
                       "type": None, "categories": "CT", "sizes": "SM", "file": "X.vpl"}
    assert rows[1]["rz"] == 412.055419  # kept as upstream wrote it (> 360)
    assert rows[2]["categories"] == "CT" and rows[2]["sizes"] == "SM"  # explicit group, defaults for the letters
    assert rows[3]["type"] == "Rhino" and rows[3]["categories"] == ""
    assert rows[4]["type"] == "BfInject"  # case-insensitive display-name lookup
    assert rows[5]["categories"] == "MB" and rows[5]["sizes"] == "S"
    assert rows[6]["categories"] == "CT" and rows[6]["sizes"] == "L"  # "_" keeps the default categories


def test_invalid_letters_and_unknown_calls_are_errors():
    with pytest.raises(vspawn.UnparsedLine):
        vspawn.parse_vpl("Defaults(Civilian, CX, SM)\n", "x.vpl", names())
    with pytest.raises(vspawn.UnparsedLine):
        vspawn.parse_vpl("Vehicle(1, 2, 3, 4)\n", "x.vpl", names())  # no Defaults yet
    with pytest.raises(vspawn.UnparsedLine):
        vspawn.parse_vpl("Spawn(1, 2, 3, 4)\n", "x.vpl", names())


def test_sql_seed_has_point_nulls_and_chunks():
    rows, _ = vspawn.parse_vpl(vspawn.read_text(FX / "vspawn_excerpt.vpl"), "X.vpl", names())
    sql = vspawn.render_sql(rows)
    assert sql.count("INSERT INTO vehicle_spawns") == 1 and "DELETE FROM vehicle_spawns;" in sql
    assert "POINT(-615.67517, 1807.696533)" in sql
    assert ",'Civilian',NULL,'CT','SM','X.vpl'," in sql and ",NULL,'Rhino','','','X.vpl'," in sql
