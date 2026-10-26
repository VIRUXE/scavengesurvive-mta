-- Tests for the crafting recipe engine (in-hand combine, ground construct, workbench, deconstruction).
local craft = loadfile("resources/[scavengesurvive]/crafting/shared/logic/craft.lua")()

describe("crafting logic", function()
    describe("in-hand combine", function()
        it("combines Knife + Clothes into Bandage, keeping the Knife", function()
            local res = craft.matchCombine("Knife", "Clothes")
            assert.is_not_nil(res)
            assert.are.equal("Bandage", res.recipe.result.uname)
            assert.is_false(res.consumeA) -- Knife kept
            assert.is_true(res.consumeB) -- Clothes consumed
        end)

        it("combines Clothes + Knife regardless of order", function()
            local res = craft.matchCombine("Clothes", "Knife")
            assert.is_not_nil(res)
            assert.are.equal("Bandage", res.recipe.result.uname)
            assert.is_true(res.consumeA) -- Clothes consumed
            assert.is_false(res.consumeB) -- Knife kept
        end)

        it("combines Bottle + Bandage into MolotovEmpty consuming both", function()
            local res = craft.matchCombine("Bottle", "Bandage")
            assert.is_not_nil(res)
            assert.are.equal("MolotovEmpty", res.recipe.result.uname)
            assert.is_true(res.consumeA)
            assert.is_true(res.consumeB)
        end)

        it("combines Knife + Parachute into ParaBag", function()
            local res = craft.matchCombine("Knife", "Parachute")
            assert.is_not_nil(res)
            assert.are.equal("ParaBag", res.recipe.result.uname)
            assert.is_false(res.consumeA)
            assert.is_true(res.consumeB)
        end)

        it("returns nil for non-matching items", function()
            assert.is_nil(craft.matchCombine("Knife", "Hammer"))
            assert.is_nil(craft.matchCombine("WoodLog", "Bottle"))
        end)
    end)

    describe("ground construction", function()
        it("matches Campfire when 2x WoodLog and FireLighter held", function()
            local ground = { WoodLog = 2 }
            local matches = craft.matchGround(ground, "FireLighter")
            assert.are.equal(1, #matches)
            assert.are.equal("Campfire", matches[1].name)
            assert.are.equal(3000, matches[1].buildTime)
        end)

        it("refuses Campfire if not holding FireLighter", function()
            local ground = { WoodLog = 2 }
            local matches = craft.matchGround(ground, "Hammer")
            assert.are.equal(1, #matches)
            assert.are.equal("SmallBox", matches[1].name) -- matches SmallBox instead!
        end)

        it("matches Barricade when 3x WoodLog and Hammer held", function()
            local ground = { WoodLog = 3 }
            local matches = craft.matchGround(ground, "Hammer")
            -- both SmallBox (needs 2) and Barricade (needs 3) are valid with 3 logs
            local foundBarricade, foundSmallBox = false, false
            for _, m in ipairs(matches) do
                if m.name == "Barricade" then
                    foundBarricade = true
                end
                if m.name == "SmallBox" then
                    foundSmallBox = true
                end
            end
            assert.is_true(foundBarricade)
            assert.is_true(foundSmallBox)
        end)

        it("matches Workbench with 2x WoodLog, 2x CorPanel, and Hammer", function()
            local ground = { WoodLog = 2, CorPanel = 2 }
            local matches = craft.matchGround(ground, "Hammer")
            local foundWorkbench = false
            for _, m in ipairs(matches) do
                if m.name == "Workbench" then
                    foundWorkbench = true
                end
            end
            assert.is_true(foundWorkbench)
        end)

        it("returns empty list if ingredients missing", function()
            local ground = { WoodLog = 1 }
            local matches = craft.matchGround(ground, "Hammer")
            assert.are.equal(0, #matches)
        end)
    end)

    describe("workbench crafting", function()
        it("matches LocksmithKit with CorPanel, Screwdriver, Hammer in container and Wrench held", function()
            local container = { CorPanel = 1, Screwdriver = 1, Hammer = 1 }
            local matches = craft.matchWorkbench(container, "Wrench")
            assert.are.equal(1, #matches)
            assert.are.equal("LocksmithKit", matches[1].name)
        end)

        it("matches Keypad with Battery and CorPanel in container and Screwdriver held", function()
            local container = { Battery = 1, CorPanel = 1 }
            local matches = craft.matchWorkbench(container, "Screwdriver")
            assert.are.equal(1, #matches)
            assert.are.equal("Keypad", matches[1].name)
        end)

        it("matches Armour with 3x CorPanel and 2x Clothes with Hammer held", function()
            local container = { CorPanel = 3, Clothes = 2 }
            local matches = craft.matchWorkbench(container, "Hammer")
            assert.are.equal(1, #matches)
            assert.are.equal("Armour", matches[1].name)
        end)

        it("refuses craft if tool is wrong", function()
            local container = { Battery = 1, CorPanel = 1 }
            local matches = craft.matchWorkbench(container, "Hammer")
            assert.are.equal(0, #matches)
        end)
    end)

    describe("deconstruction", function()
        it("returns deconstruct info for Workbench with Crowbar", function()
            local info = craft.getDeconstructInfo("Workbench", "Crowbar")
            assert.is_not_nil(info)
            assert.are.equal("Crowbar", info.tool)
            assert.are.equal(8000, info.duration)
            assert.are.equal(2, #info.ingredients)
            assert.are.equal("WoodLog", info.ingredients[1].uname)
            assert.are.equal("CorPanel", info.ingredients[2].uname)
        end)

        it("refuses deconstruction without Crowbar", function()
            local info = craft.getDeconstructInfo("Workbench", "Hammer")
            assert.is_nil(info)
        end)

        it("returns nil for items that cannot be deconstructed", function()
            assert.is_nil(craft.getDeconstructInfo("Bandage", "Crowbar"))
            assert.is_nil(craft.getDeconstructInfo("Knife", "Crowbar"))
        end)

        it("lists all constructed item types a Crowbar can deconstruct (#97)", function()
            assert.same(
                { "Campfire", "Barricade", "SmallBox", "Workbench", "LargeFrame", "Door", "MetalGate", "PlotPole" },
                craft.deconstructables("Crowbar")
            )
        end)
    end)
end)

describe("crafting logic: ground tools", function()
    it("lists the tools the ground recipes are built with", function()
        local tools = craft.groundTools()
        assert.is_true(tools.Hammer)
        assert.is_true(tools.Screwdriver)
        assert.is_true(tools.FireLighter)
        assert.is_nil(tools.Knife) -- a combine and workbench tool only
    end)
end)
