local load = require("tests.lua.helpers.load_module")
local budget = load("budget")

local function rng(values)
    local i = 0
    return function()
        i = i + 1
        return values[((i - 1) % #values) + 1]
    end
end

describe("lib.budget", function()
    it("caps from the first roll times the multiplier", function()
        assert.equals(80, budget.cap(80, 1.0))
        assert.equals(40, budget.cap(80, "0.5"))
        assert.equals(0, budget.cap(0, 2))
        assert.equals(81, budget.cap(80.6, nil))
    end)

    describe("refill", function()
        it("accrues nothing at or above capacity", function()
            assert.same({ 0, 0 }, { budget.refill(80, 80, 0.9, 0.1, 0.02, 300) })
            assert.same({ 0, 0 }, { budget.refill(80, 95, 0.9, 0.1, 0.02, 300) })
        end)
        it("spawns 10 % of the deficit per hour, carrying the fraction", function()
            -- deficit 40 → 4/h → 1/3 per 5 min
            local spawns, rem = budget.refill(80, 40, 0, 0.10, 0, 300)
            assert.equals(0, spawns)
            assert.is_true(math.abs(rem - 1 / 3) < 1e-9)
            spawns, rem = budget.refill(80, 40, rem, 0.10, 0, 300)
            assert.equals(0, spawns)
            spawns, rem = budget.refill(80, 40, rem, 0.10, 0, 300)
            assert.equals(1, spawns)
            assert.is_true(rem < 1e-9)
        end)
        it("keeps a floor of the cap when the deficit is small", function()
            -- deficit 2 → 0.2/h by rate; floor 2 % of 80 = 1.6/h wins → 1.6 in one hour
            local spawns, rem = budget.refill(80, 78, 0, 0.10, 0.02, 3600)
            assert.equals(1, spawns)
            assert.is_true(math.abs(rem - 0.6) < 1e-9)
        end)
        it("never spawns above the deficit", function()
            local spawns, rem = budget.refill(80, 79, 5.5, 0.10, 0.02, 3600)
            assert.equals(1, spawns)
            assert.equals(0, rem)
        end)
    end)

    it("jitters cooldowns within base × (1 ± jitter)", function()
        assert.equals(3600, budget.cooldown(3600, 0.5, rng({ 0.5 })))
        assert.equals(1800, budget.cooldown(3600, 0.5, rng({ 0 })))
        assert.equals(5400, budget.cooldown(3600, 0.5, rng({ 1 })))
        assert.equals(21600, budget.cooldown(21600, nil, rng({ 0.9 })))
    end)

    it("checks the distance to every player", function()
        local players = { { x = 0, y = 0 }, { x = 500, y = 500 } }
        assert.is_false(budget.clearOfPlayers(100, 100, players, 150))
        assert.is_true(budget.clearOfPlayers(200, 0, players, 150))
        assert.is_true(budget.clearOfPlayers(200, 0, {}, 150))
    end)

    it("picks random clear points up to the count asked", function()
        local points = { { x = 0, y = 0, id = 1 }, { x = 1000, y = 0, id = 2 }, { x = 2000, y = 0, id = 3 } }
        local players = { { x = 10, y = 10 } }
        local picked = budget.pickClear(points, players, 150, 5, rng({ 0.5, 0.1 }))
        assert.equals(2, #picked)
        for _, p in ipairs(picked) do
            assert.is_not.equals(1, p.id)
        end
        assert.equals(1, #budget.pickClear(points, players, 150, 1, rng({ 0.2 })))
    end)
end)
