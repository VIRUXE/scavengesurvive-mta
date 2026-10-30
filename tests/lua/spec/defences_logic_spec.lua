-- Tests for building, defence, keypad, and plot pole logic.
local defences = loadfile("resources/[scavengesurvive]/building/shared/logic/defences.lua")()

describe("defences logic", function()
    describe("type checks", function()
        it("identifies defence items correctly", function()
            assert.is_true(defences.isDefenceItem("LargeFrame"))
            assert.is_true(defences.isDefenceItem("Door"))
            assert.is_true(defences.isDefenceItem("MetalGate"))
            assert.is_true(defences.isDefenceItem("CorPanel"))
            assert.is_false(defences.isDefenceItem("WoodLog"))
            assert.is_false(defences.isDefenceItem("Bandage"))
        end)
    end)

    describe("passcode verification", function()
        it("accepts exact 4-digit code match", function()
            assert.is_true(defences.verifyPasscode("1234", "1234"))
            assert.is_true(defences.verifyPasscode("0042", "42"))
            assert.is_true(defences.verifyPasscode(42, "0042"))
        end)

        it("rejects wrong code", function()
            assert.is_false(defences.verifyPasscode("1234", "4321"))
            assert.is_false(defences.verifyPasscode("1234", nil))
        end)

        it("accepts any code if expected is empty or nil", function()
            assert.is_true(defences.verifyPasscode(nil, "1234"))
            assert.is_true(defences.verifyPasscode("", "1234"))
        end)
    end)

    describe("keypad display formatting", function()
        it("formats empty input as _ _ _ _", function()
            assert.are.equal("_ _ _ _", defences.formatKeypadDisplay(""))
            assert.are.equal("_ _ _ _", defences.formatKeypadDisplay(nil))
        end)

        it("formats partial inputs with asterisks", function()
            assert.are.equal("* _ _ _", defences.formatKeypadDisplay("1"))
            assert.are.equal("* * _ _", defences.formatKeypadDisplay("12"))
            assert.are.equal("* * * _", defences.formatKeypadDisplay("123"))
            assert.are.equal("* * * *", defences.formatKeypadDisplay("1234"))
        end)
    end)

    describe("plot pole territory check", function()
        it("returns true when inside 20m radius", function()
            assert.is_true(defences.isInsidePlotPole(100, 100, 100, 110, 20))
            assert.is_true(defences.isInsidePlotPole(100, 100, 114, 114, 20)) -- sqrt(14^2 + 14^2) = 19.8m
        end)

        it("returns false when outside 20m radius", function()
            assert.is_false(defences.isInsidePlotPole(100, 100, 100, 125, 20))
            assert.is_false(defences.isInsidePlotPole(100, 100, 115, 115, 20)) -- sqrt(15^2 + 15^2) = 21.2m
        end)
    end)

    describe("building a defence", function()
        -- upstream: DefineDefenceItem(item_CorPanel, 0.0, 90.0, 0.0, 90.0, 90.0, 0.0, 1.21428, true)
        local cor = { vertical = { 0.0, 90.0, 0.0 }, horizontal = { 90.0, 90.0, 0.0 }, zOffset = 1.21428 }
        -- upstream: DefineDefenceItem(item_WoodPanel, 90.0, 0.0, 23.5, 0.0, 0.0, 0.0, 1.0161, false)
        local wood = { vertical = { 90.0, 0.0, 23.5 }, horizontal = { 0.0, 0.0, 0.0 }, zOffset = 1.0161 }

        it("maps the tool in hand to a pose", function()
            assert.are.equal("vertical", defences.TOOL_POSE.Screwdriver)
            assert.are.equal("horizontal", defences.TOOL_POSE.Hammer)
            assert.is_nil(defences.TOOL_POSE.Crowbar)
        end)

        it("stands a defence up with a screwdriver, raised by its z offset", function()
            local z, rz, st = defences.build(wood, "vertical", 10.0, 350.0, 0.0)
            assert.are.equal(11.0161, z)
            assert.are.equal(13.5, rz)
            assert.are.same({ active = true, pose = "vertical", rx = 90.0, ry = 0.0 }, st)
        end)

        it("lays a defence down with a hammer at its own height", function()
            local z, rz, st = defences.build(cor, "horizontal", 10.0, 45.0, 0.0)
            assert.are.equal(10.0, z)
            assert.are.equal(45.0, rz)
            assert.are.same({ active = true, pose = "horizontal", rx = 90.0, ry = 90.0 }, st)
        end)

        it("restores the lying position when taken down", function()
            local z, rz, st = defences.build(wood, "vertical", 10.0, 350.0, 5.0)
            local z2, rz2 = defences.unbuild(wood, st, z, rz, 5.0)
            assert.is_true(math.abs(z2 - 10.0) < 1e-9)
            assert.is_true(math.abs(rz2 - 350.0) < 1e-9)
        end)

        it("reads the built state from item data in either JSON shape", function()
            local st = { active = true, pose = "vertical", rx = 0, ry = 90 }
            assert.are.equal(st, defences.state({ defence = st }))
            assert.are.equal(st, defences.state({ { defence = st } }))
            assert.is_nil(defences.state({ defence = { active = false } }))
            assert.is_nil(defences.state({}))
            assert.is_nil(defences.state(nil))
        end)

        it("only lets a crowbar work from the back side", function()
            -- a defence at the origin facing north (rz 0): the player south of it is behind it
            assert.is_true(defences.isBehind(cor, 0, 0, 0, 0, -2))
            assert.is_false(defences.isBehind(cor, 0, 0, 0, 0, 2))
            -- turned to face east (rz 270): west of it is behind
            assert.is_true(defences.isBehind(cor, 270, 0, 0, -2, 0))
            assert.is_false(defences.isBehind(cor, 270, 0, 0, 2, 0))
        end)
    end)

    describe("toggling pose (motor movement)", function()
        -- upstream: DefineDefenceItem(item_CorPanel, 0.0, 90.0, 0.0, 90.0, 90.0, 0.0, 1.21428, true)
        local cor = {
            vertical = { 0.0, 90.0, 0.0 },
            horizontal = { 90.0, 90.0, 0.0 },
            zOffset = 1.21428,
            movable = true,
        }
        -- upstream: DefineDefenceItem(item_WoodPanel, 90.0, 0.0, 23.5, 0.0, 0.0, 0.0, 1.0161, false)
        local wood = {
            vertical = { 90.0, 0.0, 23.5 },
            horizontal = { 0.0, 0.0, 0.0 },
            zOffset = 1.0161,
            movable = false,
        }

        it("toggles vertical to horizontal, lowering z and applying horizontal rotation", function()
            local st = { active = true, pose = "vertical", rx = 0.0, ry = 90.0, motor = true }
            local newZ, newRz, newSt = defences.toggle(cor, st, 11.21428, 45.0)
            assert.is_true(math.abs(newZ - 10.0) < 1e-5)
            assert.is_true(math.abs(newRz - 45.0) < 1e-5)
            assert.are.equal("horizontal", newSt.pose)
            assert.are.equal(90.0, newSt.rx)
            assert.are.equal(90.0, newSt.ry)
            assert.is_true(newSt.motor)
        end)

        it("toggles horizontal to vertical, raising z and applying vertical rotation", function()
            local st = {
                active = true,
                pose = "horizontal",
                rx = 90.0,
                ry = 90.0,
                motor = true,
                keypad = 1,
                passcode = "1234",
            }
            local newZ, newRz, newSt = defences.toggle(cor, st, 10.0, 45.0)
            assert.is_true(math.abs(newZ - 11.21428) < 1e-5)
            assert.is_true(math.abs(newRz - 45.0) < 1e-5)
            assert.are.equal("vertical", newSt.pose)
            assert.are.equal(0.0, newSt.rx)
            assert.are.equal(90.0, newSt.ry)
            assert.is_true(newSt.motor)
            assert.are.equal(1, newSt.keypad)
            assert.are.equal("1234", newSt.passcode)
        end)

        it("handles rotation differences between vertical and horizontal poses", function()
            local st = { active = true, pose = "vertical", rx = 90.0, ry = 0.0 }
            -- WoodPanel: vertical rotz = 23.5, horizontal rotz = 0.0. delta = (0 - 23.5) = -23.5 -> +336.5
            local newZ, newRz, newSt = defences.toggle(wood, st, 11.0161, 23.5)
            assert.is_true(math.abs(newZ - 10.0) < 1e-5)
            assert.is_true(math.abs(newRz - 0.0) < 1e-5)
            assert.are.equal("horizontal", newSt.pose)

            -- toggling back from horizontal to vertical restores z and rz
            local z2, rz2, st2 = defences.toggle(wood, newSt, newZ, newRz)
            assert.is_true(math.abs(z2 - 11.0161) < 1e-5)
            assert.is_true(math.abs(rz2 - 23.5) < 1e-5)
            assert.are.equal("vertical", st2.pose)
        end)

        it("allows unbuild to restore the original lying position from toggled pose", function()
            -- CorPanel built vertical from lying pos (10.0, 30.0) with restRz = 0.0
            local z1, rz1, st1 = defences.build(cor, "vertical", 10.0, 30.0, 0.0)
            -- Motor moves it to horizontal
            local z2, rz2, st2 = defences.toggle(cor, st1, z1, rz1)
            -- Crowbar unbuilds it while in horizontal pose
            local zUn, rzUn = defences.unbuild(cor, st2, z2, rz2, 0.0)
            assert.is_true(math.abs(zUn - 10.0) < 1e-5)
            assert.is_true(math.abs(rzUn - 30.0) < 1e-5)
        end)

        it("supports isBehind check in both vertical and horizontal poses", function()
            assert.is_true(defences.isBehind(cor, 0, 0, 0, 0, -2, "vertical"))
            assert.is_false(defences.isBehind(cor, 0, 0, 0, 0, 2, "vertical"))
            assert.is_true(defences.isBehind(cor, 0, 0, 0, 0, -2, "horizontal"))
            assert.is_false(defences.isBehind(cor, 0, 0, 0, 0, 2, "horizontal"))
        end)
    end)

    describe("large frame covering", function()
        it("only the Large Frame takes a covering", function()
            assert.is_true(defences.isCoverable("LargeFrame"))
            assert.is_false(defences.isCoverable("Door"))
        end)

        it("puts the covering on and takes it off, keeping the rest of the state", function()
            local st = { active = true, pose = "horizontal", rx = 0, ry = 0 }
            local on = defences.toggleCovering(st)
            assert.is_true(on.covered)
            assert.are.equal("horizontal", on.pose)
            assert.is_nil(st.covered)
            local off = defences.toggleCovering(on)
            assert.is_nil(off.covered)
            assert.is_true(off.active)
        end)
    end)
end)
