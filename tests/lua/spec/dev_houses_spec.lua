local houses = dofile("resources/[scavengesurvive]/dev/shared/logic/houses.lua")

local function near(a, b, eps)
    return math.abs(a - b) < (eps or 1e-6)
end

local function realZones()
    local zones = {}
    for zone in pairs(dofile("resources/[scavengesurvive]/maps/data/index.lua")) do
        zones[zone] = dofile("resources/[scavengesurvive]/maps/data/" .. zone .. ".lua")
    end
    return zones
end

describe("dev houses", function()
    it("collects the shell rows of every zone, zones in name order, other models left out", function()
        local zones = {
            SF = { objects = { { 19489, 1, 2, 3, 0, 0, 90 }, { 1491, 0, 0, 0, 0, 0, 0 } } },
            LS = { objects = { { 19511, 4, 5, 6, 0, 0, 0 }, { 19490, 0, 0, 0, 0, 0, 0 } } },
        }
        local list = houses.collect(zones)
        assert.equals(2, #list)
        assert.same({ model = 19511, name = "lshouse4", x = 4, y = 5, z = 6, rz = 0, zone = "LS" }, list[1])
        assert.equals("sfhouse1", list[2].name)
        assert.equals(90, list[2].rz)
    end)

    it("orders entrances lowest first, ties in list order", function()
        assert.same({ 2, 1, 3 }, houses.entrances({ { 0, 0, -2 }, { 0, 0, -5 }, { 0, 0, -2 } }))
        assert.same({}, houses.entrances(nil))
    end)

    it("stands outside the doorway, away from the shell origin, facing it", function()
        -- leaf hinged at (5, 0) running along +x (rz 0): doorway middle (5.45, 0), wall normal along y
        local d = { 0, 0, 0, 0, 20000, 5, 1, -4, 0 }
        local h = { x = 100, y = 200, z = 10, rz = 0 }
        local x, y, z, rz = houses.spotOutside(h, d)
        assert.is_true(near(x, 105.45))
        assert.is_true(near(y, 201 + houses.STAND_OFF))
        assert.is_true(near(z, 10 - 4 + houses.LIFT))
        assert.is_true(near(rz, 180)) -- facing -y, back towards the doorway
    end)

    it("turns the spot with the shell", function()
        local d = { 0, 0, 0, 0, 20000, 5, 1, -4, 0 }
        local x, y, _, rz = houses.spotOutside({ x = 0, y = 0, z = 0, rz = 90 }, d)
        -- local (5.45, 3.5) turned 90 degrees lands at (-3.5, 5.45), facing local -y = world +x
        assert.is_true(near(x, -(1 + houses.STAND_OFF)))
        assert.is_true(near(y, 5.45))
        assert.is_true(near(rz, 270))
    end)

    it("falls back to above the shell origin when a shell has no entrances, and cycles entrances", function()
        local h = { x = 1, y = 2, z = 3, rz = 45 }
        assert.same({ 1, 2, 5, 45, 0, 0 }, { houses.spot(h, nil) })
        local doors = { { 0, 0, -1, 0, 1, 0, 3, -1, 0 }, { 0, 0, -2, 0, 1, 0, -3, -2, 0 } }
        local _, _, z1, _, n1, count = houses.spot({ x = 0, y = 0, z = 0, rz = 0 }, doors, 1)
        local _, _, z3, _, n3 = houses.spot({ x = 0, y = 0, z = 0, rz = 0 }, doors, 3)
        assert.equals(2, count)
        assert.equals(1, n1)
        assert.is_true(near(z1, -2 + houses.LIFT))
        assert.equals(1, n3)
        assert.is_true(near(z3, z1))
    end)

    it("picks next, prev, a number or the next of a type, wrapping round", function()
        local list = { { name = "lshouse1" }, { name = "sfhouse2" }, { name = "lshouse1" } }
        assert.equals(1, houses.pick(list, 0))
        assert.equals(1, houses.pick(list, 3, "next"))
        assert.equals(3, houses.pick(list, 1, "prev"))
        assert.equals(3, houses.pick(list, 0, "prev"))
        assert.equals(2, houses.pick(list, 1, "2"))
        assert.equals(3, houses.pick(list, 1, "LSHOUSE1"))
        assert.equals(1, houses.pick(list, 3, "lshouse1"))
        assert.is_nil((houses.pick(list, 1, "9")))
        assert.is_nil((houses.pick(list, 1, "lvhouse4")))
        assert.is_nil((houses.pick({}, 0)))
    end)

    it("finds all 237 shells in the real maps, each with entrances and a spot outside the walls", function()
        local list = houses.collect(realZones())
        local doors = dofile("resources/[scavengesurvive]/maps/shared/shell_doors.lua")
        assert.equals(237, #list)
        for _, h in ipairs(list) do
            assert.is_truthy(doors[h.model], h.name)
            local x, y, z, _, n = houses.spot(h, doors[h.model], 1)
            assert.equals(1, n)
            assert.is_true(math.abs(z - h.z) < 8)
            assert.is_true((x - h.x) ^ 2 + (y - h.y) ^ 2 > 4)
        end
        assert.is_truthy(houses.summary(list):find("lshouse1 x%d+"))
    end)
end)
