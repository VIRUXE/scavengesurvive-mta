-- Tests for the armed vehicles' weapon overheat (upstream char/overheat.pwn).
local overheat = loadfile("resources/[scavengesurvive]/vehicles/shared/logic/overheat.lua")()

describe("overheat", function()
    it("covers the Rhino, Hunter and Hydra only", function()
        assert.is_true(overheat.isArmed(432))
        assert.is_true(overheat.isArmed(425))
        assert.is_true(overheat.isArmed(520))
        assert.is_false(overheat.isArmed(525))
    end)

    it("adds 20 a shot with the engine on", function()
        assert.are.equal(20, overheat.shot(0, true))
        assert.are.equal(0, overheat.shot(0, false))
    end)

    it("cools by 1 a tick down to 0", function()
        assert.are.equal(19, overheat.tick(20, 432, false, true))
        assert.are.equal(0, overheat.tick(0, 432, false, true))
        -- only the Hunter's held gun heats; the Rhino cools with it held
        assert.are.equal(19, overheat.tick(20, 432, true, true))
    end)

    it("heats the Hunter by 1 a tick while its gun is held, not with the engine off", function()
        assert.are.equal(21, overheat.tick(20, 425, true, true))
        assert.are.equal(20, overheat.tick(20, 425, true, false))
    end)

    it("warns over 32 and blows up over 40", function()
        assert.is_false(overheat.isWarning(32))
        assert.is_true(overheat.isWarning(33))
        assert.is_false(overheat.isOver(40))
        assert.is_true(overheat.isOver(41))
        -- three quick Rhino shots: 60 after the third, over the maximum
        assert.is_true(overheat.isOver(overheat.shot(overheat.tick(overheat.shot(20, true), 432, false, true), true)))
    end)
end)
