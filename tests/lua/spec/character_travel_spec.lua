-- Travel stats and the Endurance skill (character/shared/logic/travel.lua, upstream travel-stats.pwn, #138).
local travel = dofile("resources/[scavengesurvive]/character/shared/logic/travel.lua")

describe("character travel", function()
    it("classifies a second of movement from what the server sees", function()
        assert.are.equal("driving", travel.classify({ inVehicle = true, speed = 20 }))
        assert.are.equal("swimming", travel.classify({ inWater = true, speed = 1 }))
        assert.are.equal("air", travel.classify({ falling = true, speed = 9 }))
        assert.is_nil(travel.classify({ speed = 0.2 }))
        assert.are.equal("crouching", travel.classify({ ducked = true, speed = 1.5 }))
        assert.are.equal("walking", travel.classify({ speed = 1.5 }))
        assert.are.equal("running", travel.classify({ speed = 4.5 }))
        assert.are.equal("sprinting", travel.classify({ speed = 6.5 }))
    end)

    it("gains Endurance every 500 m run and every 200 m swum, once per 10 s", function()
        local t = travel.new()
        local gains = 0
        for s = 1, 120 do -- 120 s at 4.5 m/s = 540 m
            if travel.record(t, "running", 4.5, 1000, s * 1000) then
                gains = gains + 1
            end
        end
        assert.are.equal(1, gains)
        assert.is_true(math.abs(t.dist.running - 540) < 1e-6)
        assert.are.equal(120000, t.time.running)
        local sw = travel.new()
        local swims = 0
        for s = 1, 300 do -- 300 m swum
            if travel.record(sw, "swimming", 1, 1000, s * 1000) then
                swims = swims + 1
            end
        end
        assert.are.equal(1, swims)
        assert.is_nil(sw.time.running)
    end)

    it("loses a crossing inside the cooldown and never counts a teleport", function()
        local t = travel.new()
        assert.is_false(travel.record(t, "sprinting", 500, 1000, 1000)) -- 500 m in one second: a teleport
        assert.is_nil(t.dist.sprinting)
        -- 20 m/s: 500 m at s = 25 and 1000 m at s = 50, 25 s apart, past the cooldown
        local gainedAt = {}
        for s = 1, 60 do
            if travel.record(t, "sprinting", 20, 1000, s * 1000) then
                gainedAt[#gainedAt + 1] = s
            end
        end
        assert.same({ 25, 50 }, gainedAt)
        -- running and swimming share the cooldown: a swim crossing 2 s after a run gain is lost, the next counts
        t = travel.new()
        t.dist.running = 499
        assert.is_true(travel.record(t, "running", 2, 1000, 1000))
        t.dist.swimming = 199
        assert.is_false(travel.record(t, "swimming", 2, 1000, 3000))
        assert.are.equal(400, t.nextXpAt.swimming)
        assert.is_false(travel.record(t, "swimming", 20, 1000, 20000))
        t.dist.swimming = 399
        assert.is_true(travel.record(t, "swimming", 2, 1000, 21000))
    end)

    it("counts jumps and pays on every tenth, boosts a running jump by the skill", function()
        local t = travel.new()
        local paid = 0
        for _ = 1, 25 do
            if travel.jump(t) then
                paid = paid + 1
            end
        end
        assert.are.equal(2, paid)
        assert.are.equal(25, t.jumps)
        assert.are.equal(1, travel.boost(0))
        assert.is_true(math.abs(travel.boost(0.5) - 1.65) < 1e-9)
        assert.is_true(math.abs(travel.boost(2) - 2.3) < 1e-9)
        assert.are.equal(1, travel.boost(nil))
    end)

    it("prints upstream's /mstats lines", function()
        local t = travel.new()
        travel.record(t, "walking", 3, 1000, 1000)
        travel.jump(t)
        local lines = travel.lines(t)
        assert.are.equal(#travel.KINDS * 2 + 2, #lines)
        assert.are.equal("DIST_WALKING: 3.0", lines[1])
        assert.are.equal("TIME_WALKING: 1000", lines[#travel.KINDS + 1])
        assert.are.equal("JUMPS: 1", lines[#lines])
    end)
end)
