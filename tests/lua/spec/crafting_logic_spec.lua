-- Tests for the crafting recipe engine (in-hand combine, ground construct, workbench, deconstruction), against
-- upstream core/server/init.pwn's CRAFTING SET DEFINITIONS.
local craft = loadfile("resources/[scavengesurvive]/crafting/shared/logic/craft.lua")()

local function names(list)
    local out = {}
    for _, r in ipairs(list) do
        out[#out + 1] = r.name
    end
    return out
end

describe("crafting logic", function()
    describe("the recipe list", function()
        it("has upstream's sets: 4 by hand (Bottle + Bottle left out), 13 on the ground, 28 on a workbench", function()
            local kinds = {}
            for _, r in ipairs(craft.RECIPES) do
                kinds[r.kind] = (kinds[r.kind] or 0) + 1
            end
            assert.same({ combine = 4, ground = 13, workbench = 28 }, kinds)
        end)

        it("only uses item types that exist", function()
            local items = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
            for _, r in ipairs(craft.RECIPES) do
                assert.is_not_nil(items.byUname[r.result.uname], r.result.uname)
                for _, ing in ipairs(r.ingredients) do
                    assert.is_not_nil(items.byUname[ing.uname], r.name .. ": " .. ing.uname)
                end
                for _, tool in ipairs({ r.tool, r.removalTool }) do
                    assert.is_not_nil(items.byUname[tool], r.name .. ": " .. tool)
                end
            end
        end)

        it("drops the recipes upstream never had", function()
            for _, n in ipairs({
                "Barricade",
                "SmallBox",
                "Door",
                "MetalGate",
                "Keypad",
                "Shield",
                "Armour",
                "Backpack",
                "Rucksack",
            }) do
                assert.is_nil(craft.byName[n], n)
            end
        end)
    end)

    describe("in-hand combine", function()
        it("combines Knife + Clothes into Bandage, keeping the Knife, in either order", function()
            local res = craft.matchCombine("Knife", "Clothes")
            assert.are.equal("Bandage", res.recipe.result.uname)
            assert.is_false(res.consumeA)
            assert.is_true(res.consumeB)
            local rev = craft.matchCombine("Clothes", "Knife")
            assert.is_true(rev.consumeA)
            assert.is_false(rev.consumeB)
        end)

        it("combines Bottle + Bandage into MolotovEmpty consuming both", function()
            local res = craft.matchCombine("Bottle", "Bandage")
            assert.are.equal("MolotovEmpty", res.recipe.result.uname)
            assert.is_true(res.consumeA and res.consumeB)
        end)

        it("combines Knife + Parachute into ParaBag, keeping the Knife", function()
            local res = craft.matchCombine("Knife", "Parachute")
            assert.are.equal("ParaBag", res.recipe.result.uname)
            assert.is_false(res.consumeA)
            assert.is_true(res.consumeB)
        end)

        it("combines WheelLock + LocksmithKit into a WheelLock consuming both", function()
            local res = craft.matchCombine("LocksmithKit", "WheelLock")
            assert.are.equal("WheelLock", res.recipe.result.uname)
            assert.is_true(res.consumeA and res.consumeB)
        end)

        it("does not make a Power Supply in the hand (a workbench recipe upstream) nor duplicate bottles", function()
            assert.is_nil(craft.matchCombine("Fusebox", "Battery"))
            assert.is_nil(craft.matchCombine("Bottle", "Bottle"))
            assert.is_nil(craft.matchCombine("Knife", "Hammer"))
        end)
    end)

    describe("ground construction", function()
        it("builds a Campfire from 3 logs with a Fire Lighter in 5 s, not nudged", function()
            local matches = craft.matchGround({ WoodLog = 3 }, "FireLighter")
            assert.same({ "Campfire" }, names(matches))
            assert.are.equal(5000, matches[1].buildTime)
            assert.is_false(matches[1].tweak)
            assert.same({}, craft.matchGround({ WoodLog = 2 }, "FireLighter"))
        end)

        it("needs the recipe's own tool", function()
            assert.same({}, craft.matchGround({ WoodLog = 3 }, "Hammer"))
            assert.same({}, craft.matchGround({ WoodLog = 4 }, "Hammer"))
        end)

        it("builds a Workbench from 2 Refined Metal and 4 logs with a Hammer", function()
            local m = craft.matchGround({ RefinedMetal = 2, WoodLog = 4 }, "Hammer")
            assert.are.equal("Workbench", m[1].name)
            assert.are.equal(30000, m[1].buildTime)
        end)

        it("prefers the set that uses the most of what lies there (Table over Desk over Small Table)", function()
            local tables = names(craft.matchGround({ RefinedMetal = 1, WoodLog = 4 }, "Screwdriver"))
            assert.same({ "Table", "Desk", "SmallTable" }, tables)
            assert.same({ "Desk" }, names(craft.matchGround({ RefinedMetal = 1, WoodLog = 3 }, "Screwdriver")))
            assert.same({ "SmallTable" }, names(craft.matchGround({ WoodLog = 4 }, "Screwdriver")))
        end)

        it("builds the machines with a Screwdriver; a Metal Panel more makes the Refine Machine", function()
            local machine = { Canister = 1, Motor = 1, Fluctuator = 1, PowerSupply = 1 }
            assert.same({ "ScrapMachine" }, names(craft.matchGround(machine, "Screwdriver")))
            machine.MetPanel = 1
            assert.are.equal("RefineMachine", craft.matchGround(machine, "Screwdriver")[1].name)
            assert.are.equal(5, #craft.getDeconstructInfo("RefineMachine", "Crowbar").ingredients)
            local water = craft.matchGround({ Canister = 1, Motor = 1, Bucket = 1, PowerSupply = 1 }, "Screwdriver")
            assert.are.equal("WaterMachine", water[1].name)
        end)

        it("builds a Plot Pole from a Canister, Radio Pole, Fluctuator and Power Supply, not nudged", function()
            local pole =
                craft.matchGround({ Canister = 1, RadioPole = 1, Fluctuator = 1, PowerSupply = 1 }, "Screwdriver")
            assert.are.equal("PlotPole", pole[1].name)
            assert.are.equal(20000, pole[1].buildTime)
            assert.is_false(pole[1].tweak)
        end)

        it("copies a key from two keys and a Motor, keeping one key", function()
            local m = craft.matchGround({ Key = 2, Motor = 1 }, "Screwdriver")
            assert.are.equal("Key", m[1].name)
            assert.are.equal("Key", m[1].copyData)
            assert.same({}, craft.matchGround({ Key = 1, Motor = 1 }, "Screwdriver"))
            local kept = 0
            for _, ing in ipairs(m[1].ingredients) do
                kept = kept + (ing.keep and ing.count or 0)
            end
            assert.are.equal(1, kept)
        end)

        it("builds a Large Frame from 4 Refined Metal with a Sledgehammer, as a defence lying flat", function()
            local m = craft.matchGround({ RefinedMetal = 4 }, "Sledgehammer")
            assert.are.equal("LargeFrame", m[1].name)
            assert.are.equal("horizontal", m[1].defence)
            assert.are.equal("Locker", craft.matchGround({ MetalFrame = 2, RefinedMetal = 1 }, "Sledgehammer")[1].name)
        end)
    end)

    describe("workbench crafting", function()
        it("crafts a Power Supply from exactly a Battery and a Fusebox with a Screwdriver", function()
            assert.same({ "PowerSupply" }, names(craft.matchWorkbench({ Battery = 1, Fusebox = 1 }, "Screwdriver")))
        end)

        it("needs the bench to hold exactly one set", function()
            assert.same({}, craft.matchWorkbench({ Battery = 1, Fusebox = 1, Timer = 1 }, "Screwdriver"))
            assert.same({}, craft.matchWorkbench({ Battery = 1 }, "Screwdriver"))
        end)

        it("refuses the wrong tool", function()
            assert.same({}, craft.matchWorkbench({ Battery = 1, Fusebox = 1 }, "Hammer"))
            assert.same({ "MetalFrame" }, names(craft.matchWorkbench({ RefinedMetal = 4 }, "Hammer")))
        end)

        it("crafts the Lock Breaker from its five parts", function()
            local bench = { LocksmithKit = 1, FluxCap = 1, RefinedMetal = 2, PowerSupply = 1 }
            assert.same({ "LockBreaker" }, names(craft.matchWorkbench(bench, "Screwdriver")))
        end)

        it("takes 3.6 s per item on the bench, as upstream workbench.pwn", function()
            assert.are.equal(7200, craft.workbenchTime(craft.byName.PowerSupply))
            assert.are.equal(18000, craft.workbenchTime(craft.byName.LockBreaker))
        end)
    end)

    describe("deconstruction", function()
        it("takes a Workbench down with a Crowbar in 25 s and gives back every part", function()
            local info = craft.getDeconstructInfo("Workbench", "Crowbar")
            assert.are.equal("Crowbar", info.tool)
            assert.are.equal(25000, info.duration)
            local back = {}
            for _, ing in ipairs(info.ingredients) do
                back[ing.uname] = (back[ing.uname] or 0) + ing.count
            end
            assert.same({ RefinedMetal = 2, WoodLog = 4 }, back)
        end)

        it("refuses other tools and the sets with no removal tool", function()
            assert.is_nil(craft.getDeconstructInfo("Workbench", "Hammer"))
            assert.is_nil(craft.getDeconstructInfo("Campfire", "Crowbar"))
            assert.is_nil(craft.getDeconstructInfo("Key", "Crowbar"))
            assert.is_nil(craft.getDeconstructInfo("Bandage", "Crowbar"))
        end)

        it("lists every constructed item type a Crowbar can take down", function()
            local expected =
                { "PlotPole", "ScrapMachine", "RefineMachine", "WaterMachine", "Workbench", "Locker", "Desk" }
            for _, u in ipairs({ "Table", "Barstool", "SmallTable", "LargeFrame" }) do
                expected[#expected + 1] = u
            end
            assert.same(expected, craft.deconstructables("Crowbar"))
        end)
    end)
end)

describe("crafting logic: ground tools", function()
    it("lists the tools the ground recipes are built with", function()
        assert.same({ FireLighter = true, Hammer = true, Screwdriver = true, Sledgehammer = true }, craft.groundTools())
    end)
end)
