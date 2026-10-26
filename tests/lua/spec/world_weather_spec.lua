local weather = dofile("resources/[scavengesurvive]/world/shared/logic/weather.lua")
local function rng(values)
    local i = 0
    return function()
        i = i + 1
        return values[((i - 1) % #values) + 1]
    end
end

describe("world weather", function()
    it("carries upstream's 20 weather types with their chances", function()
        assert.equals(20, #weather.TYPES)
        assert.equals("EXTRASUNNY_LS", weather.name(0))
        assert.equals("SANDSTORM_DESERT", weather.name(19))
        assert.equals(0.3, weather.TYPES[9].chance) -- RAINY_SF
        assert.equals(0.3, weather.TYPES[20].chance) -- SANDSTORM_DESERT
        for i, t in ipairs(weather.TYPES) do
            assert.equals(i - 1, t.id)
        end
    end)
    it("never boots into the sandstorm (upstream random(19))", function()
        assert.equals(0, weather.initial(rng({ 0 })))
        assert.equals(18, weather.initial(rng({ 0.9999 })))
    end)
    it("keeps the types whose chance beats the roll", function()
        -- roll 0.5 against every chance: the 0.3/0.4/0.5 types drop out
        local list = weather.candidates(rng({ 0.5 }))
        assert.same({ 0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 17, 18 }, list)
        -- chance 1.0 always beats a roll in [0,1): the 13 fair-weather types are never all excluded
        assert.equals(13, #weather.candidates(rng({ 0.99999 })))
    end)
    it("picks uniformly from the candidates", function()
        -- 20 candidate rolls of 0, then 0.5 as the index roll -> candidate 11 of 20 = id 10
        local values = {}
        for _ = 1, 20 do
            values[#values + 1] = 0
        end
        values[#values + 1] = 0.5
        assert.equals(10, weather.pick(rng(values)))
        -- a high roll keeps only the chance-1.0 types and lands on the last of them
        assert.equals(18, weather.pick(rng({ 0.99999 })))
    end)
    it("excludes current weather when rolling a change", function()
        -- With 20 rolls of 0, all candidates 0..19 qualify.
        -- When excludeId is 0, the first element is now id 1.
        local values = {}
        for _ = 1, 20 do
            values[#values + 1] = 0
        end
        values[#values + 1] = 0 -- index 0 -> first element of candidate list
        assert.equals(1, weather.pick(rng(values), 0))
    end)
    it("defines 1-minute check interval for weather change evaluations", function()
        assert.equals(60000, weather.CHECK_INTERVAL_MS)
    end)
    it("changes with 10 % chance once 10 minutes have passed", function()
        assert.is_false(weather.shouldChange(600000, rng({ 0 })))
        assert.is_true(weather.shouldChange(600001, rng({ 0.0999 })))
        assert.is_false(weather.shouldChange(600001, rng({ 0.1 })))
    end)
    it("parses ids and names for the dev/staff command", function()
        assert.equals(8, weather.parse("8"))
        assert.equals(8, weather.parse(8))
        assert.equals(8, weather.parse("rainy_sf"))
        assert.equals(19, weather.parse("SANDSTORM_DESERT"))
        assert.is_nil(weather.parse("20"))
        assert.is_nil(weather.parse("-1"))
        assert.is_nil(weather.parse("1.5"))
        assert.is_nil(weather.parse("snow"))
        assert.is_nil(weather.parse(nil))
    end)
    it("reads the clock from getRealTime()", function()
        local h, m = weather.clock({ hour = 23, minute = 7, second = 1 })
        assert.equals(23, h)
        assert.equals(7, m)
    end)
end)
