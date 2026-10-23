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
    offsets = types["Satchel"]["categoryData"]["bag_offsets"]
    assert offsets["60"][0] == -0.211999 and offsets["60"][8] == 1.356999  # the later line for skin 60 wins
    assert offsets["170"][3] == -9.900006 and len(offsets) == 2
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
    assert "ON DUPLICATE KEY UPDATE" in sql
    assert ("('Satchel','Small Bag',363,2,2,'bag','{\"bag_name\": \"Small Bag\", \"bag_offsets\": {\"170\": [-0.244999, "
            "-0.067, 0.007999, -9.900006, 5.099997, 1.5, 1.243002, 1.282998, 1.274001], \"60\": [-0.211999, -0.048999, "
            "-0.029, 0.0, -2.400002, 0.0, 1.148, 1.388001, 1.356999]}, \"bag_size\": 7}')") in sql


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


def _wear():
    read = lambda name: (FX / name).read_bytes().decode("utf-8").replace("\r\n", "\n")  # noqa: E731
    init = read("wear_excerpt.pwn")
    types = it.parse_item_types(init)
    it.apply_wear_offsets(types, init, read("wear_apparel_excerpt.pwn"), read("wear_armour_excerpt.pwn"))
    return types


def test_hat_rows_go_to_the_skin_they_were_tuned_for():
    hat = _wear()["HelmArmy"]["wearOffsets"]
    assert hat["60"] == [0.152291, 3e-05, -0.00579, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
    # skin_Civ2F's row says "// 93": upstream renumbered the female civilians after tuning, so it fits 93 (Civ1F)
    assert hat["93"][0] == 0.154
    # skin_Civ1F's row was tuned for 65, which is no clothes type any more; 294 is commented out upstream
    assert sorted(hat) == ["60", "93"]


def test_rows_without_a_model_comment_stay_on_their_symbol():
    bandana = _wear()["BandanaBl"]["wearOffsets"]
    assert bandana["93"][0] == 0.064999 and bandana["60"][8] == 0.914


def test_armour_rows_follow_their_skin_tag_not_their_index():
    armour = _wear()["Armour"]["wearOffsets"]
    assert armour["90"][0] == 0.117 and armour["60"][5] == 4.400002
    assert "131" not in armour  # skin_IndiF is not defined in the excerpt
    assert "wearOffsets" in it.render_lua(_wear()) and "wearOffsets" not in it.render_sql(_wear())
