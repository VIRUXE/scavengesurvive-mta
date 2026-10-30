-- Fishing (items/shared/logic/fishing.lua, upstream fishingrod.pwn, #141).
local fishing = dofile("resources/[scavengesurvive]/items/shared/logic/fishing.lua")

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

describe("items fishing", function()
    it("casts a metre per 100 ms of hold, up to 100 m", function()
        assert.are.equal(0, fishing.castDistance(0))
        assert.are.equal(20, fishing.castDistance(2000))
        assert.are.equal(100, fishing.castDistance(10000))
        assert.are.equal(100, fishing.castDistance(25000))
        assert.are.equal(0, fishing.castDistance(nil))
        assert.are.equal(0, fishing.castDistance(-5))
    end)

    it("lands the line ahead of the player", function()
        local x, y = fishing.castPoint(10, 20, 0, 5)
        assert.is_true(near(x, 10) and near(y, 25))
        x, y = fishing.castPoint(10, 20, 90, 5) -- facing west
        assert.is_true(near(x, 5) and near(y, 20))
    end)

    it("waits 30 to 120 s and lands the fish 100 ms per metre after the tug", function()
        assert.are.equal(
            30000,
            fishing.waitMs(function(a)
                return a
            end)
        )
        assert.are.equal(
            120000,
            fishing.waitMs(function(_, b)
                return b
            end)
        )
        assert.are.equal(2000, fishing.catchDelayMs(20))
        assert.are.equal(2100, fishing.catchDelayMs(20.6))
        assert.are.equal(0, fishing.catchDelayMs(nil))
    end)

    it("catches 30 % of the time without the skill and 65 % at its best", function()
        assert.is_true(fishing.caught(299, 700))
        assert.is_false(fishing.caught(300, 700))
        assert.is_true(fishing.caught(649, 350)) -- the time modifier halves the miss at Master
        assert.is_false(fishing.caught(650, 350))
        assert.is_false(fishing.caught(300, nil))
    end)
end)
