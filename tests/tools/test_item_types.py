from pathlib import Path

from tools.convert import item_types as it

FX = Path(__file__).parent / "fixtures"


def _load():
    src = (FX / "init_excerpt.pwn").read_bytes().decode("utf-8").replace("\r\n", "\n")
    bags = (FX / "bag_excerpt.pwn").read_bytes().decode("utf-8").replace("\r\n", "\n")
    types = it.parse_item_types(src)
    it.apply_categories(types, src, bags)
    return types


def test_parses_positional_and_named_args():
    types = _load()
    knife = types["Knife"]
    assert (knife["name"], knife["model"], knife["size"], knife["maxhitpoints"]) == ("Combat Knife", 335, 1, 1)
    assert knife["rotx"] == 90.0
    assert types["MediumBox"]["longpickup"] is True and types["MediumBox"]["usecarryanim"] is True
    assert types["Bottle"]["attx"] == 0.060376


def test_categories_are_attached():
    types = _load()
    assert types["M9Pistol"]["category"] == "weapon"
    cd = types["M9Pistol"]["categoryData"]
    assert cd["calibre"] == "9mm" and cd["magSize"] == 10 and cd["baseWeapon"] == 22 and cd["melee"] is False
    assert types["Wrench"]["categoryData"]["melee"] is True and types["Wrench"]["categoryData"]["bleed"] == 0.01
    assert types["Ammo9mm"]["categoryData"]["calibre"] == "9mm" and types["Ammo9mm"]["categoryData"]["rounds"] == 20
    assert types["HotDog"]["categoryData"] == {"maxBites": 4, "biteValue": 18.0, "canCook": True, "canRawInfect": True, "destroyOnEnd": True}
    assert types["Bottle"]["categoryData"]["capacity"] == 0.5 and types["Bottle"]["categoryData"]["liquids"][0] == ["Water", 100.0]
    assert types["Satchel"]["category"] == "bag" and types["Satchel"]["categoryData"]["bag_size"] == 7
    assert types["MediumBox"]["category"] == "safebox" and types["MediumBox"]["categoryData"]["size"] == 10
    assert types["_calibres"]["9mm"] == 0.25


def test_lua_and_sql_output_are_deterministic_and_complete():
    types = _load()
    lua, sql = it.render_lua(types), it.render_sql(types)
    assert lua == it.render_lua(types) and sql == it.render_sql(types)
    assert lua.startswith("-- Derived from Southclaws/ScavengeSurvive (MPL-2.0)")
    assert 'M.byUname.Knife = { attrx = 0.0' in lua and 'uname = "Knife"' in lua
    assert 'M.order = { "NULL", "Knife"' in lua
    # upstream: item_Satchel = DefineItemType("Small Bag", "Satchel", 363, 2, ..., .maxhitpoints = 2)
    assert "ON DUPLICATE KEY UPDATE" in sql and "('Satchel','Small Bag',363,2,2,'bag','{\"bag_name\": \"Small Bag\", \"bag_size\": 7}')" in sql


def test_calibres_with_the_same_display_name_stay_distinct():
    types = _load()
    # upstream: calibre_50cae = DefineAmmoCalibre(".50", 0.73); calibre_50bmg = DefineAmmoCalibre(".50", 0.63)
    assert types["_calibres"]["50cae"] == 0.73 and types["_calibres"]["50bmg"] == 0.63
    assert types["_calibre_names"]["50cae"] == ".50" and types["_calibre_names"]["9mm"] == "9mm"
    lua = it.render_lua(types)
    assert 'M.calibres = { ["50bmg"] = 0.63, ["50cae"] = 0.73, ["9mm"] = 0.25, fuel = 0.0 }' in lua
    assert "M.calibreNames = " in lua


def test_symbolic_weapon_flags_and_liquid_ammo():
    types = _load()
    # DefineItemTypeWeapon(item_Chainsaw, WEAPON_CHAINSAW, liquid_Petrol, ..., WEAPON_FLAG_ASSISTED_FIRE | WEAPON_FLAG_LIQUID_AMMO)
    cd = types["Chainsaw"]["categoryData"]
    assert cd["baseWeapon"] == 9 and cd["flags"] == 2 | 8 and cd["calibre"] is None and cd["liquid"] == "Petrol"
    # GasCan is defined as ammo and as a liquid container upstream; the container definition wins
    assert types["GasCan"]["category"] == "liquid"
