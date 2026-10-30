-- Tests for the crafting recipe engine over upstream's craft sets (data/generated/recipes.lua).
local craft = loadfile("resources/[scavengesurvive]/crafting/shared/logic/craft.lua")()
local recipes = loadfile("resources/[scavengesurvive]/data/generated/recipes.lua")()
local book = craft.book(recipes)

local function items(...)
    local out = {}
    for i, u in ipairs({ ... }) do
        out[i] = { id = i, uname = u }
    end
    return out
end

local function unames(list)
    local out = {}
    for i, it in ipairs(list) do
        out[i] = it.uname
    end
    return out
end

describe("crafting logic", function()
    it("holds every upstream craft set", function()
        assert.are.equal(46, #recipes)
        assert.are.equal(5, #craft.byKind(book, "combine"))
        assert.are.equal(13, #craft.byKind(book, "construct"))
        assert.are.equal(28, #craft.byKind(book, "workbench"))
    end)

    describe("matching", function()
        it("matches exactly a set's ingredients in any order", function()
            assert.are.equal("Bandage", craft.find(book, { "Clothes", "Knife" }).result)
            assert.are.equal("Bandage", craft.find(book, { "Knife", "Clothes" }).result)
            assert.are.equal("MolotovEmpty", craft.find(book, { "Bandage", "Bottle" }).result)
        end)

        it("needs every ingredient and nothing more", function()
            assert.is_nil(craft.find(book, { "Knife" }))
            assert.is_nil(craft.find(book, { "Knife", "Clothes", "Battery" }))
            assert.is_nil(craft.find(book, { "WoodLog", "WoodLog" }))
            assert.are.equal("Campfire", craft.find(book, { "WoodLog", "WoodLog", "WoodLog" }).result)
            assert.are.equal("SmallTable", craft.find(book, { "WoodLog", "WoodLog", "WoodLog", "WoodLog" }).result)
        end)

        it("makes a Power Supply from a Battery and a Fusebox at a workbench with a Screwdriver (#119)", function()
            local r = craft.find(book, { "Fusebox", "Battery" })
            assert.are.same({ "PowerSupply", "workbench", "Screwdriver" }, { r.result, r.kind, r.tool })
        end)

        it("keeps upstream's first set when two share their ingredients", function()
            -- the scrap and refine machines are built from the same parts; upstream finds the scrap machine first
            local r = craft.find(book, { "Canister", "Motor", "Fluctuator", "PowerSupply" })
            assert.are.equal("ScrapMachine", r.result)
        end)

        it("knows the construct tools", function()
            for _, tool in ipairs({ "FireLighter", "Screwdriver", "Hammer", "Sledgehammer" }) do
                assert.is_true(book.constructTools[tool], tool)
            end
            assert.is_nil(book.constructTools.Crowbar)
        end)
    end)

    describe("split", function()
        it("keeps the knife and uses up the clothes", function()
            local r = craft.find(book, { "Knife", "Clothes" })
            local consumed, kept = craft.split(r, items("Clothes", "Knife"))
            assert.are.same({ "Clothes" }, unames(consumed))
            assert.are.same({ "Knife" }, unames(kept))
        end)

        it("keeps the first key given for a key copy and uses the other with the motor", function()
            local r = craft.find(book, { "Key", "Key", "Motor" })
            local list = items("Key", "Motor", "Key")
            local consumed, kept = craft.split(r, list)
            assert.are.same({ list[1] }, kept)
            assert.are.same({ list[2], list[3] }, consumed)
        end)
    end)

    describe("deconstruction", function()
        it("gives back the used-up ingredients", function()
            local r = craft.removal(book, "Workbench", "Crowbar")
            assert.are.same({ 25000, "Crowbar" }, { r.removalTime, r.removalTool })
            assert.are.same(
                { "RefinedMetal", "RefinedMetal", "WoodLog", "WoodLog", "WoodLog", "WoodLog" },
                craft.returned(r)
            )
        end)

        it("has no removal for sets without a removal tool, or with another tool", function()
            assert.is_nil(craft.removal(book, "Campfire", "Crowbar"))
            assert.is_nil(craft.removal(book, "Key", "Crowbar"))
            assert.is_nil(craft.removal(book, "Workbench", "Hammer"))
            assert.is_nil(craft.removal(book, "PowerSupply", "Crowbar"))
        end)

        it("lists what a crowbar takes apart", function()
            local list = craft.removable(book, "Crowbar")
            assert.are.same({
                "Barstool",
                "Desk",
                "LargeFrame",
                "Locker",
                "PlotPole",
                "RefineMachine",
                "ScrapMachine",
                "SmallTable",
                "Table",
                "WaterMachine",
                "Workbench",
            }, list)
        end)
    end)

    describe("construction details", function()
        it("carries tweak and defence from upstream", function()
            local campfire = craft.find(book, { "WoodLog", "WoodLog", "WoodLog" })
            assert.are.same({ false, 5000, "FireLighter" }, { campfire.tweak, campfire.buildTime, campfire.tool })
            local frame = craft.find(book, { "RefinedMetal", "RefinedMetal", "RefinedMetal", "RefinedMetal" })
            assert.are.equal("construct", frame.kind)
            assert.is_true(frame.defence)
            assert.is_false(craft.find(book, { "Canister", "RadioPole", "Fluctuator", "PowerSupply" }).tweak)
        end)

        it("stands the result at the ingredients' average position", function()
            local x, y, z = craft.averagePos({ { x = 1, y = 2, z = 3 }, { x = 3, y = 4, z = 5 } })
            assert.are.same({ 2, 3, 4 }, { x, y, z })
        end)

        it("times a workbench craft by its item count", function()
            assert.are.equal(7200, craft.workbenchTime(2))
            assert.are.equal(18000, craft.workbenchTime(5))
        end)

        it("counts the units a combined result needs beyond the freed ones", function()
            local sizes = { ParaBag = 6, Parachute = 6, Knife = 1, MolotovEmpty = 1, Bottle = 1, Bandage = 2 }
            local function sizeOf(u)
                return sizes[u]
            end
            assert.are.equal(0, craft.extraUnits(craft.find(book, { "Knife", "Parachute" }), sizeOf))
            assert.are.equal(-2, craft.extraUnits(craft.find(book, { "Bottle", "Bandage" }), sizeOf))
        end)
    end)

    describe("pouring one bottle into another", function()
        it("moves as much as fits", function()
            local a, b = craft.pour({ amount = 0.2, liquid = "Water" }, { { amount = 0.5, liquid = "Water" } }, 0.5)
            assert.are.same({ amount = 0.5, liquid = "Water" }, a)
            assert.is_true(math.abs(b.amount - 0.2) < 1e-9)
            assert.are.equal("Water", b.liquid)
        end)

        it("fills an empty bottle and empties the other", function()
            local a, b = craft.pour(nil, { amount = 0.3, liquid = "Orange" }, 0.5)
            assert.are.same({ amount = 0.3, liquid = "Orange" }, a)
            assert.are.same({ amount = 0 }, b)
        end)

        it("refuses empty, full and mixed bottles", function()
            assert.are.equal("LIQUID_EMPTY", select(3, craft.pour({ amount = 0.1, liquid = "Water" }, nil, 0.5)))
            local full = { amount = 0.5, liquid = "Water" }
            assert.are.equal("LIQUID_FULL", select(3, craft.pour(full, { amount = 0.1, liquid = "Water" }, 0.5)))
            local juice = { amount = 0.1, liquid = "Orange" }
            assert.are.equal("LIQUID_MIX", select(3, craft.pour(juice, { amount = 0.1, liquid = "Water" }, 0.5)))
        end)
    end)
end)
