-- Tests for the Firework Box's flight (upstream item/firework.pwn).
local firework = loadfile("resources/[scavengesurvive]/items/shared/logic/firework.lua")()

-- randInt(n) always rolling the middle of the wobble: elevation + 10 - 10, so no wobble at all
local function steady(n)
    return n == 20 and 10 or 0
end

local function count(p)
    local n = 1
    for _, child in ipairs(firework.burst(p, steady)) do
        n = n + count(child)
    end
    return n
end

describe("firework", function()
    it("launches the rocket straight up 10 m at 20 m/s", function()
        local p = firework.launch(100, 200, 10, steady)
        assert.are.equal(345, p.look)
        assert.is_true(math.abs(p.to[1] - 100) < 1e-6)
        assert.is_true(math.abs(p.to[2] - 200) < 1e-6)
        assert.is_true(math.abs(p.to[3] - 20) < 1e-6)
        assert.are.equal(500, p.ms)
    end)

    it("bursts through sequence 1: camflash, shootlight, fire, then stops", function()
        local rocket = firework.launch(0, 0, 0, steady)
        local first = firework.burst(rocket, steady)
        assert.are.equal(4, #first)
        assert.are.equal("camflash", first[1].look)
        local second = firework.burst(first[1], steady)
        assert.are.equal(3, #second)
        assert.are.equal("shootlight", second[1].look)
        local third = firework.burst(second[1], steady)
        assert.are.equal(4, #third)
        assert.are.equal("fire", third[1].look)
        assert.are.same({}, firework.burst(third[1], steady))
    end)

    it("spreads a burst evenly round from where the parent stopped", function()
        local rocket = firework.launch(0, 0, 0, steady)
        local sparks = firework.burst(rocket, steady)
        for _, s in ipairs(sparks) do
            assert.are.same(rocket.to, s.from)
        end
        -- rotation 0, 90, 180, 270 at 45 degrees and 6 m: north, east, south, west
        local r = 6 * math.cos(math.rad(45))
        assert.is_true(math.abs(sparks[1].to[2] - r) < 1e-6)
        assert.is_true(math.abs(sparks[2].to[1] - r) < 1e-6)
        assert.is_true(math.abs(sparks[3].to[2] + r) < 1e-6)
        assert.is_true(math.abs(sparks[4].to[1] + r) < 1e-6)
    end)

    it("makes 65 projectiles from one launch, one past upstream's cap", function()
        assert.are.equal(65, count(firework.launch(0, 0, 0, steady)))
        assert.are.equal(64, firework.MAX_PROJECTILES)
    end)
end)
