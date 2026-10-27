local focus = dofile("resources/[scavengesurvive]/anticheat/shared/logic/focus.lua")

describe("anticheat focus / idle kick logic", function()
    it("kicks an unfocused non-staff player when elapsed time exceeds limit", function()
        local should, elapsed = focus.shouldKick(true, 60, 1000, 62000, false)
        assert.is_true(should)
        assert.equals(61000, elapsed)
    end)

    it("does not kick if elapsed time is under the limit", function()
        local should, elapsed = focus.shouldKick(true, 60, 1000, 30000, false)
        assert.is_false(should)
        assert.equals(29000, elapsed)
    end)

    it("does not kick when idle kick is disabled", function()
        local should = focus.shouldKick(false, 60, 1000, 100000, false)
        assert.is_false(should)
    end)

    it("does not kick staff on duty", function()
        local should = focus.shouldKick(true, 60, 1000, 100000, true)
        assert.is_false(should)
    end)

    it("does not kick if player is not minimized", function()
        local should = focus.shouldKick(true, 60, nil, 100000, false)
        assert.is_false(should)
    end)

    it("does not kick when maxTabOutTime is 0 or negative (disabled limit)", function()
        local shouldZero = focus.shouldKick(true, 0, 1000, 100000, false)
        assert.is_false(shouldZero)

        local shouldNeg = focus.shouldKick(true, -1, 1000, 100000, false)
        assert.is_false(shouldNeg)
    end)

    it("uses default limit 60 when maxTabOutTime is non-numeric nil", function()
        local should = focus.shouldKick(true, nil, 1000, 62000, false)
        assert.is_true(should)

        local shouldNot = focus.shouldKick(true, nil, 1000, 50000, false)
        assert.is_false(shouldNot)
    end)
end)
