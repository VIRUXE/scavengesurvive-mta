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

describe("loot roll: liquid containers", function()
    local BOTTLE = {
        category = "liquid",
        categoryData = { capacity = 0.5, liquids = { { "Water", 100.0 }, { "Orange", 50.0 } }, reusable = true },
    }
    -- rng(a, b) draws from the queue, rng() the fixed fraction
    local function rngOf(ints, fraction)
        local i = 0
        return function(a)
            if a == nil then
                return fraction
            end
            i = i + 1
            return ints[i] or a
        end
    end
    it("fills a container with one of the liquids whose chance beat the roll, to a random level", function()
        -- Water 100 keeps on 99, Orange 50 drops on 60; the pick is 1 of 1; 0.8 of 0.5 L
        assert.equals(
            '{"amount":0.400,"liquid":"Water"}',
            roll.initialItemData(BOTTLE, "civilian", nil, rngOf({ 99, 60, 1 }, 0.8))
        )
        -- both qualify, the second is picked
        assert.equals(
            '{"amount":0.250,"liquid":"Orange"}',
            roll.initialItemData(BOTTLE, "civilian", nil, rngOf({ 0, 50, 2 }, 0.5))
        )
    end)
    it("spawns a container empty when no liquid qualifies or the type lists none", function()
        local never = { category = "liquid", categoryData = { capacity = 0.33, liquids = { { "Turpentine", 1.0 } } } }
        assert.is_nil(roll.initialItemData(never, "industrial", nil, rngOf({ 2 }, 0.5)))
        assert.is_nil(
            roll.initialItemData(
                { category = "liquid", categoryData = { capacity = 0.5, liquids = {} } },
                "x",
                nil,
                rngOf({}, 0.5)
            )
        )
    end)
end)
