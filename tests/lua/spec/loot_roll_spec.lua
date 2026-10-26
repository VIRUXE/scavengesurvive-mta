local roll = dofile("resources/[scavengesurvive]/loot/shared/logic/roll.lua")
local function seq(values)
    local i = 0
    return function()
        i = i + 1
        return values[((i - 1) % #values) + 1]
    end
end
local tbl = {
    mult = 1.0,
    entries = {
        { weight = 100, uname = "A", perLimit = 3, serverLimit = 0 },
        { weight = 0, uname = "B", perLimit = 3, serverLimit = 0 },
    },
}
describe("loot roll", function()
    it("samples entries by weight", function()
        local l = roll.sampleList(tbl.entries, seq({ 0.5 }))
        local out = {}
        for _, e in ipairs(l) do
            out[#out + 1] = e.uname
        end
        assert.same({ "A" }, out)
    end)
    it("rolls size 3..5 when size is -1 and respects the spawn weight", function()
        -- picks are without replacement, so the fixture needs at least 5 sampleable entries
        local five = { mult = 1.0, entries = {} }
        for i = 1, 5 do
            five.entries[i] = { weight = 100, uname = "E" .. i, perLimit = 3, serverLimit = 0 }
        end
        assert.equals(3, #roll.pick(five, -1, 100, 1.0, seq({ 0.0 }))) -- size = 3 + 0
        assert.equals(5, #roll.pick(five, -1, 100, 1.0, seq({ 0.99 }))) -- size = 3 + 2
        assert.same({ "A" }, roll.pick(tbl, -1, 100, 1.0, seq({ 0.0 }))) -- only one entry sampled
        assert.same({}, roll.pick(tbl, 2, 0, 1.0, seq({ 0.5 }))) -- weight 0 => nothing spawns
    end)
    it("never exceeds 6 and never repeats an entry", function()
        local big = { mult = 1.0, entries = {} }
        for i = 1, 10 do
            big.entries[i] = { weight = 100, uname = "I" .. i, perLimit = 3, serverLimit = 0 }
        end
        local out = roll.pick(big, 10, 100, 1.0, seq({ 0.1, 0.7, 0.3 }))
        assert.equals(6, #out)
        local seen = {}
        for _, u in ipairs(out) do
            assert.is_nil(seen[u])
            seen[u] = true
        end
    end)
end)

describe("loot initial item data", function()
    local CAN =
        { category = "liquid", categoryData = { capacity = 20.0, liquids = { { "Petrol", 100.0 } }, reusable = true } }
    it("rolls a liquid container's amount from its capacity (#118)", function()
        assert.equals('{"amount":10.0}', roll.initialItemData(CAN, "world_civilian", nil, seq({ 0.5 })))
        assert.equals('{"amount":0.0}', roll.initialItemData(CAN, "world_civilian", nil, seq({ 0.0 })))
        assert.equals('{"amount":19.9}', roll.initialItemData(CAN, "world_civilian", nil, seq({ 0.997 })))
        assert.equals('{"amount":12.3}', roll.initialItemData(CAN, "world_civilian", nil, seq({ 0.6174 })))
    end)
    it("leaves a container without a capacity and other generic types alone", function()
        assert.is_nil(
            roll.initialItemData({ category = "liquid", categoryData = {} }, "world_civilian", nil, seq({ 0.5 }))
        )
        assert.is_nil(
            roll.initialItemData({ category = "generic", categoryData = {} }, "world_civilian", nil, seq({ 0.5 }))
        )
        assert.is_nil(roll.initialItemData({ category = "generic" }, "world_civilian", nil, seq({ 0.5 })))
    end)
end)
