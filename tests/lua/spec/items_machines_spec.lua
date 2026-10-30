-- Machines (items/shared/logic/machines.lua; upstream itemtype/machine.pwn, item/scrap-machine.pwn,
-- refine-machine.pwn, water-purifier.pwn, #145).
local machines = dofile("resources/[scavengesurvive]/items/shared/logic/machines.lua")
local liquids = dofile("resources/[scavengesurvive]/items/shared/logic/liquids.lua")
local types = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
local function itemType(uname)
    return types.byUname[uname]
end
local function near(expected, actual)
    assert.is_true(math.abs(expected - actual) < 1e-9, tostring(expected) .. " ~= " .. tostring(actual))
end

describe("items machines", function()
    it("names the three machines and their upstream item types exist", function()
        for uname, kind in pairs(machines.TYPES) do
            assert.is_true(machines.isMachine(uname))
            assert.equals(kind, machines.kind(uname))
            assert.is_not_nil(itemType(uname), uname)
            assert.equals(12, itemType(uname).size)
        end
        assert.is_false(machines.isMachine("Workbench"))
        for uname in pairs(machines.SCRAP) do
            assert.is_not_nil(itemType(uname), "scrap value for an unknown type " .. uname)
        end
        assert.equals(1, itemType("ScrapMetal").size)
        assert.equals(1, itemType("RefinedMetal").size)
    end)

    it("reads and writes the machine state in either JSON shape, keeping other keys", function()
        local st = machines.state(nil)
        near(0, st.fuel); assert.is_nil(st.cooking)
        st = machines.state({ { machine = { fuel = "12.5", cooking = { at = "100", ms = "9000" } } } })
        near(12.5, st.fuel); assert.same({ at = 100, ms = 9000 }, st.cooking)
        local d = machines.encode({ other = 1, machine = { fuel = 3 } }, { fuel = 7.7, cooking = nil })
        assert.equals(1, d.other); near(7.7, d.machine.fuel); assert.is_nil(d.machine.cooking)
        d = machines.encode(nil, { fuel = 1, cooking = { at = 5, ms = 6 } })
        assert.same({ fuel = 1, cooking = { at = 5, ms = 6 } }, d.machine)
    end)

    it("the refining machine takes scrap only, the purifier sea water only, the scrap machine anything", function()
        assert.is_true(machines.accepts("scrap", itemType("Bucket"), nil, liquids))
        assert.is_true(machines.accepts("refine", itemType("ScrapMetal"), nil, liquids))
        local ok, needs = machines.accepts("refine", itemType("Bucket"), nil, liquids)
        assert.is_false(ok); assert.equals("Scrap Metal", needs)
        local bottle = itemType("Bottle")
        assert.is_true(machines.accepts("water", bottle, { amount = 0.3, liquid = "SeaWater" }, liquids))
        ok, needs = machines.accepts("water", bottle, { amount = 0.3, liquid = "Water" }, liquids)
        assert.is_false(ok); assert.equals("Water Bottle (Sea Water)", needs)
        assert.is_false((machines.accepts("water", bottle, { amount = 0, liquid = "SeaWater" }, liquids)))
        assert.is_false((machines.accepts("water", itemType("ScrapMetal"), nil, liquids)))
    end)

    it("knows a can of petrol in hand", function()
        local can = itemType("GasCan")
        near(12, machines.petrolIn(can, { amount = 12 }, liquids))
        assert.is_nil(machines.petrolIn(can, { amount = 0 }, liquids))
        assert.is_nil(machines.petrolIn(itemType("Bottle"), { amount = 0.4, liquid = "Water" }, liquids))
        assert.is_nil(machines.petrolIn(itemType("Bucket"), nil, liquids))
    end)

    it("refuels 1.1 a tick until the tank is full or the can empty", function()
        local fuel, can, done = machines.refuelStep(0, 20)
        near(1.1, fuel); near(18.9, can); assert.is_false(done)
        fuel, can, done = machines.refuelStep(99.5, 20)
        near(100, fuel); near(19.5, can); assert.is_true(done)
        fuel, can, done = machines.refuelStep(10, 0.4)
        near(10.4, fuel); near(0, can); assert.is_true(done)
        fuel, can, done = machines.refuelStep(100, 5)
        near(100, fuel); near(5, can); assert.is_true(done)
        assert.equals(10000, machines.refuelMs(0)); assert.equals(2500, machines.refuelMs(75))
    end)

    it("starts a cook of 90 s per item plus up to 30 s when there is fuel for every item", function()
        local idle = { fuel = 10, cooking = nil }
        assert.same({ false, "MACHNOITEMS" }, { machines.start(idle, 0, 1000) })
        assert.same({ false, "MACHNOTFUEL" }, { machines.start(idle, 3, 1000) }) -- 10.5 needed
        local ok, st = machines.start(idle, 2, 1000, function()
            return 0.5
        end)
        assert.is_true(ok)
        assert.same({ at = 1000, ms = (180 + 15) * 1000 }, st.cooking); near(10, st.fuel)
        assert.same({ false, "MACHPROCESS" }, { machines.start(st, 2, 1000) })
        assert.equals(195000, machines.remainingMs(st, 1000))
        assert.equals(135000, machines.remainingMs(st, 1060))
        assert.equals(0, machines.remainingMs(st, 2000))
        assert.equals(0, machines.remainingMs(idle, 2000))
        assert.equals("3 minutes 15 seconds", machines.timeText(195000))
        assert.equals("0 minutes 0 seconds", machines.timeText(-5))
    end)

    describe("finishing a cook burns 3.5 fuel per item and swaps the contents", function()
        local st = { fuel = 50, cooking = { at = 1, ms = 2 } }
        it("scrap: the items' scrap values in Scrap Metal, at most 11, nothing for a type without one", function()
            local nextSt, out = machines.finish("scrap", st, {
                { uname = "Barbecue" }, -- 6
                { uname = "Bucket" }, -- 2
                { uname = "Meat" }, -- none: destroyed for nothing
            }, liquids, itemType)
            near(50 - 3.5 * 3, nextSt.fuel); assert.is_nil(nextSt.cooking)
            assert.equals(8, #out); assert.same({ uname = "ScrapMetal" }, out[1])
            local _, capped = machines.finish("scrap", st, { { uname = "MetalFrame" } }, liquids, itemType) -- 16
            assert.equals(11, #capped)
            local _, none = machines.finish("scrap", st, {}, liquids, itemType)
            assert.equals(0, #none)
        end)
        it("refine: one Refined Metal per Scrap Metal", function()
            local nextSt, out = machines.finish("refine", st, { { uname = "ScrapMetal" }, { uname = "ScrapMetal" } }, liquids, itemType)
            near(43, nextSt.fuel); assert.equals(2, #out); assert.equals("RefinedMetal", out[2].uname)
        end)
        it("water: every bottle keeps its amount and becomes water", function()
            local _, out = machines.finish("water", st, {
                { uname = "Bottle", data = { amount = 0.3, liquid = "SeaWater" } },
                { uname = "Bottle", data = { { amount = 0.5, liquid = "SeaWater" } } },
            }, liquids, itemType)
            assert.equals(2, #out)
            assert.equals("Bottle", out[1].uname); assert.same({ amount = 0.3, liquid = "Water" }, out[1].data)
            assert.same({ amount = 0.5, liquid = "Water" }, out[2].data)
        end)
    end)

    it("writes the menu and the messages", function()
        assert.matches("Fuel amount: 12.5", machines.menuBody("scrap", 12.5))
        assert.matches("^Press 'Start'", machines.menuBody("water", 0))
        assert.equals("There is not enough fuel. Machine requires 3.5 per item.", string.format(machines.TEXT.MACHNOTFUEL, machines.FUEL_PER_ITEM))
    end)
end)
