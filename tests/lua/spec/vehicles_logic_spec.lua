local vlogic = dofile("resources/[scavengesurvive]/vehicles/shared/logic/vehicle.lua")

describe("vehicles logic", function()
    it("computes angles and relative directions correctly", function()
        -- vehicle at (0, 0) heading 0 (north)
        assert.is_true(vlogic.isFront(vlogic.angleToVehicle(0, 10, 0, 0, 0)))
        assert.is_true(vlogic.isRear(vlogic.angleToVehicle(0, -10, 0, 0, 0)))
        assert.is_true(vlogic.isDriverSide(vlogic.angleToVehicle(-10, 0, 0, 0, 0)))

        -- vehicle at (0, 0) heading 90 (facing West, -X)
        -- front is West (-X):
        assert.is_true(vlogic.isFront(vlogic.angleToVehicle(-10, 0, 0, 0, 90)))
        -- rear is East (+X):
        assert.is_true(vlogic.isRear(vlogic.angleToVehicle(10, 0, 0, 0, 90)))
        -- driver side is South (-Y):
        assert.is_true(vlogic.isDriverSide(vlogic.angleToVehicle(0, -10, 0, 0, 90)))
    end)

    it("selects the nearest damaged wheel in vehicle-local coordinates", function()
        assert.equals(1, vlogic.nearestDamagedWheel(-1, 1, { 1, 0, 1, 0 }))
        assert.equals(4, vlogic.nearestDamagedWheel(1, -1, { 0, 0, 0, 1 }))
        assert.is_nil(vlogic.nearestDamagedWheel(-1, 1, { 0, 0, 0, 0 }))
        assert.is_nil(vlogic.nearestDamagedWheel(0, 0, { 0, 1 }))
    end)

    it("calculates fuel drain smoothly", function()
        -- 0 fuel remains 0
        assert.equals(0, vlogic.fuelDrain(0, 15, 60, 1))
        -- 10 L fuel at 60 km/h: speedDrain = (15/100)*(60/36000) = 0.15*0.001666 = 0.00025 + 0.0001 = 0.00035 L/s
        local remaining = vlogic.fuelDrain(10, 15, 60, 1)
        assert.is_true(remaining < 10)
        assert.is_true(math.abs(remaining - (10 - 0.00035)) < 1e-5)
    end)

    it("validates engine start conditions", function()
        -- pushbike with no engine can always start
        assert.is_true(vlogic.canStartEngine(100, 0, true, 0))
        -- damaged below 300 cannot start
        local ok, err = vlogic.canStartEngine(250, 10, false, 50)
        assert.is_false(ok)
        assert.equals("DAMAGED", err)
        -- empty fuel cannot start
        local ok2, err2 = vlogic.canStartEngine(500, 0, false, 50)
        assert.is_false(ok2)
        assert.equals("NO_FUEL", err2)
        -- good health and fuel can start
        assert.is_true(vlogic.canStartEngine(500, 10, false, 50))
    end)

    it("selects correct repair tools for health thresholds", function()
        assert.equals("Wrench", vlogic.repairToolForHealth(350))
        assert.equals("Screwdriver", vlogic.repairToolForHealth(500))
        assert.equals("Hammer", vlogic.repairToolForHealth(700))
        assert.equals("Wrench", vlogic.repairToolForHealth(850))
        assert.is_nil(vlogic.repairToolForHealth(990))
        assert.is_nil(vlogic.repairToolForHealth(1000))
    end)

    it("evaluates lock break permissions", function()
        -- unlocked cannot be broken
        assert.is_false(vlogic.canBreakLock(vlogic.LOCK_OPEN, "Crowbar"))
        -- default lock can be broken with crowbar
        assert.is_true(vlogic.canBreakLock(vlogic.LOCK_DEFAULT, "Crowbar"))
        -- external custom lock cannot be broken with crowbar
        local ok, err = vlogic.canBreakLock(vlogic.LOCK_EXTERNAL, "Crowbar")
        assert.is_false(ok)
        assert.equals("LOCKBREAKNO", err)
        -- electronic lockbreaker can break both
        assert.is_true(vlogic.canBreakLock(vlogic.LOCK_DEFAULT, "LockBreaker"))
        assert.is_true(vlogic.canBreakLock(vlogic.LOCK_EXTERNAL, "LockBreaker"))
    end)

    it("handles key cutting and usage", function()
        -- cannot craft on unlockable vehicle (pushbike)
        local ok, err = vlogic.canCraftKey(vlogic.LOCK_OPEN, "LocksmithKit", true, 0)
        assert.is_false(ok)
        assert.equals("LOCKNODOORS", err)
        -- cannot craft if already has lock
        local ok2, err2 = vlogic.canCraftKey(vlogic.LOCK_OPEN, "LocksmithKit", false, 999)
        assert.is_false(ok2)
        assert.equals("LOCKALREADY", err2)
        -- can craft on valid vehicle
        assert.is_true(vlogic.canCraftKey(vlogic.LOCK_OPEN, "LocksmithKit", false, 0))

        -- using key matching / mismatching
        assert.is_true(vlogic.canUseKey({ code = 12345 }, 12345))
        assert.is_false(vlogic.canUseKey({ code = 12345 }, 99999))
        assert.is_false(vlogic.canUseKey({ code = 0 }, 12345))
        assert.is_false(vlogic.canUseKey(nil, 12345))
        assert.is_false(vlogic.canUseKey({ code = 12345 }, 0))
    end)

    it("picks the repair tip of upstream's health bands", function()
        assert.equals("TUTORVEHVER", vlogic.repairTipKey(300))
        assert.equals("TUTORVEHVER", vlogic.repairTipKey(450))
        assert.equals("TUTORVEHBRO", vlogic.repairTipKey(451))
        assert.equals("TUTORVEHBRO", vlogic.repairTipKey(650))
        assert.equals("TUTORVEHBIT", vlogic.repairTipKey(800))
        assert.equals("TUTORVEHSLI", vlogic.repairTipKey(990))
        assert.is_nil(vlogic.repairTipKey(991))
        assert.is_nil(vlogic.repairTipKey(nil))
    end)

    it("matches trailer hitches", function()
        local bobcat = { trailerHitch = "small" }
        local smallTrailer = { trailer = true, size = "small" }
        local largeTrailer = { trailer = true, size = "large" }
        local comet = { trailerHitch = nil }

        assert.is_true(vlogic.canAttachTrailer(bobcat, smallTrailer, 2.0, 5.0))
        assert.is_false(vlogic.canAttachTrailer(bobcat, largeTrailer, 2.0, 5.0))
        assert.is_false(vlogic.canAttachTrailer(comet, smallTrailer, 2.0, 5.0))
        assert.is_false(vlogic.canAttachTrailer(bobcat, smallTrailer, 6.0, 5.0))
    end)
end)
