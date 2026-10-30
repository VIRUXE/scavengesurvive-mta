import pytest

from tools.convert import recipes
from tools.convert.common import UnparsedLine

UNAMES = {f"item_{u}": u for u in ("Knife", "Parachute", "ParaBag", "WoodLog", "Campfire", "FireLighter", "Battery",
                                   "Fusebox", "PowerSupply", "Screwdriver", "Crowbar", "PlotPole", "Sledgehammer",
                                   "LargeFrame", "RefinedMetal", "Key", "Motor")}

SRC = """
	// CRAFTING SET DEFINITIONS
	// items created by hand
	DefineItemCraftSet(item_ParaBag, item_Knife, true, item_Parachute, false);

	// items created by using a tool item on them in the world
	SetCraftSetConstructible(5000, item_FireLighter, DefineItemCraftSet(item_Campfire, item_WoodLog, false, item_WoodLog, false), .tweak = false);
	SetCraftSetConstructible(20000, item_Screwdriver, DefineItemCraftSet(item_PlotPole, item_Battery, false, item_Fusebox, false), item_Crowbar, 30000, false);
	SetCraftSetConstructible(18500, item_Screwdriver, DefineItemCraftSet(item_Key, item_Key, false, item_Key, true, item_Motor, false), .tweak = false);
	SetCraftSetConstructible(30000, item_Sledgehammer, DefineItemCraftSet(item_LargeFrame, item_RefinedMetal, false, item_RefinedMetal, false), item_Crowbar, 22000, .defence = true);

	// items created with a workbench
	SetConstructionSetWorkbench(SetCraftSetConstructible(12000, item_Screwdriver, DefineItemCraftSet(item_PowerSupply, item_Battery, false, item_Fusebox, false)));

	// Uncomment to write out crafting recipes in wikia format!
	//WriteAllCombosToFile();
"""


def test_parses_the_three_kinds_in_order():
    sets = recipes.parse_recipes(SRC, UNAMES)
    assert [(r["result"], r["kind"]) for r in sets] == [
        ("ParaBag", "combine"), ("Campfire", "construct"), ("PlotPole", "construct"), ("Key", "construct"),
        ("LargeFrame", "construct"), ("PowerSupply", "workbench")]
    assert sets[0]["ingredients"] == [{"uname": "Knife", "keep": True}, {"uname": "Parachute", "keep": False}]


def test_constructible_positional_and_named_args():
    sets = {r["result"]: r for r in recipes.parse_recipes(SRC, UNAMES)}
    camp = sets["Campfire"]
    assert (camp["buildTime"], camp["tool"], camp["tweak"], camp["defence"]) == (5000, "FireLighter", False, False)
    assert "removalTool" not in camp
    pole = sets["PlotPole"]
    assert (pole["removalTool"], pole["removalTime"], pole["tweak"]) == ("Crowbar", 30000, False)
    frame = sets["LargeFrame"]
    assert (frame["defence"], frame["tweak"], frame["removalTime"]) == (True, True, 22000)
    assert [i["keep"] for i in sets["Key"]["ingredients"]] == [False, True, False]
    ps = sets["PowerSupply"]
    assert (ps["tool"], ps["buildTime"], "removalTool" in ps) == ("Screwdriver", 12000, False)


def test_renders_lua():
    lua = recipes.render_lua(recipes.parse_recipes(SRC, UNAMES))
    assert lua.startswith("-- Derived from Southclaws/ScavengeSurvive")
    assert ('{ result = "PowerSupply", kind = "workbench", tool = "Screwdriver", buildTime = 12000, ingredients = '
            '{ { uname = "Battery", keep = false }, { uname = "Fusebox", keep = false } } },') in lua
    assert 'removalTool = "Crowbar", removalTime = 30000' in lua


def test_unknown_item_or_statement_fails_loudly():
    with pytest.raises(UnparsedLine):
        recipes.parse_recipes(SRC.replace("item_Parachute", "item_Nope"), UNAMES)
    with pytest.raises(UnparsedLine):
        recipes.parse_recipes(SRC.replace("// items created by hand", "DefineSomethingElse(1);"), UNAMES)
