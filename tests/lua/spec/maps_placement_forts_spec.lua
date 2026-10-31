local placement = dofile("resources/[scavengesurvive]/maps/shared/logic/placement.lua")

describe("maps placement forts", function()
    it("appends every fort's rows after the zone rows, in name order, and counts them", function()
        local base = { { 1234, 0, 0, 0, 0, 0, 0, -1, -1, 350 } }
        local forts = {
            ["Fort B"] = { { 20302, 5, 5, 0, 0, 0, 0, -1, -1, 350 } },
            ["Fort A"] = { { 20301, 1, 1, 0, 0, 0, 0, -1, -1, 350 }, { 3928, 2, 2, 0, 0, 0, 0, -1, -1, 350 } },
        }
        local rows, added = placement.appendForts(base, forts)
        assert.equals(3, added)
        assert.same({ 1234, 20301, 3928, 20302 }, { rows[1][1], rows[2][1], rows[3][1], rows[4][1] })
        assert.equals(1, #base) -- the zone rows are not modified
    end)

    it("routes the kit's models through the model pack as objects", function()
        assert.is_true(placement.isSampModel(placement.FORT_MODEL_MIN))
        assert.equals("skip", placement.kind({ placement.FORT_MODEL_MIN, 0, 0, 0, 0, 0, 0, -1, -1, 350 }, nil))
        assert.equals("object", placement.kind({ placement.FORT_MODEL_MIN, 0, 0, 0, 0, 0, 0, -1, -1, 350 }, 1337))
    end)

    it("holds only kit models and kept upstream ones, inside the fort, in the real forts.lua", function()
        local forts = dofile("resources/[scavengesurvive]/maps/shared/forts.lua")
        for name, rows in pairs(forts) do
            for _, o in ipairs(rows) do
                assert.equals(10, #o, name)
                local kit = o[1] >= placement.FORT_MODEL_MIN and o[1] <= placement.FORT_MODEL_MAX
                assert.is_true(kit or o[1] < 18631, name .. " model " .. o[1])
                assert.is_true(
                    o[2] > 2430 and o[2] < 2550 and o[3] > -1710 and o[3] < -1625,
                    name .. " at " .. o[2] .. "," .. o[3]
                )
            end
        end
    end)
end)
