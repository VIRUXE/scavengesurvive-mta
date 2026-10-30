local placement = dofile("resources/[scavengesurvive]/maps/shared/logic/placement.lua")

-- one shell (SA-MP 19489) with one entrance: upstream's door hinged at (1, 2, 0) turned 90, the fitted 20120 at
-- (1, 2.3, 0.2) turned 90
local doors = { [19489] = { { 1, 2, 0, 90, 20120, 1, 2.3, 0.2, 90 } } }

describe("maps placement fitted shell doors", function()
    it("swaps upstream's door for the fitted one, rotated with the shell", function()
        local shell = { 19489, 100, 200, 10, 0, 0, 90 }
        -- turned 90 degrees, local (1, 2) lands at world (98, 201); the door's own 90 adds to the shell's
        local door = { 1502, 98, 201, 10, 0, 0, 180, -1, -1, 350 }
        local rows, swapped, added = placement.fitShellDoors({ shell, door }, doors)
        assert.equals(1, swapped)
        assert.equals(0, added)
        assert.equals(2, #rows)
        assert.equals(shell, rows[1])
        local fit = rows[2]
        assert.equals(20120, fit[1])
        assert.near(97.7, fit[2], 1e-6)
        assert.near(201, fit[3], 1e-6)
        assert.near(10.2, fit[4], 1e-6)
        assert.near(180, fit[7], 1e-6)
        assert.same({ -1, -1, 350 }, { fit[8], fit[9], fit[10] })
    end)

    it("keeps doors elsewhere, turned another way and of other models", function()
        local shell = { 19489, 0, 0, 0, 0, 0, 0, -1, -1, 350 }
        local away = { 1502, 3, 2, 0, 0, 0, 90 }
        local turned = { 1502, 1, 2, 0, 0, 0, 0 }
        local other = { 1523, 1, 2, 0, 0, 0, 90 }
        local rows, swapped = placement.fitShellDoors({ shell, away, turned, other }, doors)
        assert.equals(0, swapped)
        assert.same({ shell, away, turned, other }, { rows[1], rows[2], rows[3], rows[4] })
    end)

    it("hangs a fitted door in an entrance upstream left empty, in the shell's world", function()
        local shell = { 19489, 100, 200, 10, 0, 0, 0, 5, 3, 300 }
        local rows, swapped, added = placement.fitShellDoors({ shell }, doors)
        assert.equals(0, swapped)
        assert.equals(1, added)
        assert.same({ 20120, 101, 202.3, 10.2, 0, 0, 90, 5, 3, 300 }, rows[2])
    end)

    it("fitted doors swing", function()
        assert.is_true(placement.isSwingDoor(20120))
        assert.is_false(placement.isSwingDoor(19489))
    end)

    it("swaps the doors of the placed shells in the real maps", function()
        local data = dofile("resources/[scavengesurvive]/maps/shared/shell_doors.lua")
        local rows = {}
        for zone in pairs(dofile("resources/[scavengesurvive]/maps/data/index.lua")) do
            for _, o in ipairs(dofile("resources/[scavengesurvive]/maps/data/" .. zone .. ".lua").objects or {}) do
                rows[#rows + 1] = o
            end
        end
        local _, swapped, added = placement.fitShellDoors(rows, data)
        assert.is_true(swapped > 500, "swapped " .. swapped)
        assert.equals(42, added) -- lshouse2: 5 copies x 2 entrances, lshouse3: 16 x 2
    end)
end)
