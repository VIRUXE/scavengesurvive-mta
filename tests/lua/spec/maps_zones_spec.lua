local zones = dofile("resources/[scavengesurvive]/maps/shared/logic/zones.lua")
local data = dofile("resources/[scavengesurvive]/maps/data/zones.lua")
local mock = dofile("tests/lua/helpers/mta_mock.lua")

describe("maps zones logic", function()
    it("normalizes clockwise and closed polygons to counter-clockwise without duplicate end point", function()
        local cw = { { 0, 0 }, { 0, 10 }, { 10, 10 }, { 10, 0 }, { 0, 0 } }
        local norm = zones.normalize(cw)
        assert.equals(4, #norm)
        assert.is_true(zones.signedArea(norm) > 0)
        local cx, cy = zones.centroid(norm)
        assert.near(5, cx, 1e-6)
        assert.near(5, cy, 1e-6)
        local args = zones.colPolygonArgs(cw)
        assert.equals(10, #args) -- cx, cy + 4 * (x, y)
        assert.near(5, args[1], 1e-6)
        assert.near(5, args[2], 1e-6)
    end)

    it("loads all seven zones from data/zones.lua with counter-clockwise winding and centroids inside", function()
        for _, name in ipairs(zones.ORDER) do
            local poly = data[name]
            assert.is_table(poly)
            assert.is_true(#poly >= 15)
            assert.is_true(zones.signedArea(poly) > 0)
            local cx, cy = zones.centroid(poly)
            assert.is_true(zones.contains(poly, cx, cy))
        end
    end)

    it("locates landmarks in each of the seven zones and returns false in the ocean", function()
        assert.equals("ls", zones.findAt(data, 2495, -1687)) -- Grove Street
        assert.equals("sf", zones.findAt(data, -2026, 156)) --Doherty
        assert.equals("lv", zones.findAt(data, 2100, 1400)) -- The Strip
        assert.equals("rc", zones.findAt(data, 1250, -300)) -- Red County
        assert.equals("fc", zones.findAt(data, -1400, -1800)) -- Mount Chiliad / Flint
        assert.equals("bc", zones.findAt(data, 200, 1850)) -- Area 69
        assert.equals("tr", zones.findAt(data, -1600, 2100)) -- Sherman Dam
        assert.is_false(zones.findAt(data, 3500, -3500))
        assert.is_false(zones.findAt(data, nil, nil))
    end)
end)

describe("maps server colshapes and events", function()
    local createdCols
    before_each(function()
        mock.install()
        createdCols = {}
        _G.exports = {
            lib = {
                getModule = function(_, name)
                    local f = assert(io.open("resources/[scavengesurvive]/lib/modules/" .. name .. ".lua", "rb"))
                    local src = f:read("*a")
                    f:close()
                    return src
                end,
            },
        }
        _G.fileOpen = function(path)
            return assert(io.open("resources/[scavengesurvive]/maps/" .. path, "rb"))
        end
        _G.fileGetSize = function(f)
            local pos = f:seek()
            local size = f:seek("end")
            f:seek("set", pos)
            return size
        end
        _G.fileRead = function(f, n)
            return f:read(n)
        end
        _G.fileClose = function(f)
            f:close()
        end
        _G.createColPolygon = function(...)
            local id = "col:" .. (#createdCols + 1)
            createdCols[#createdCols + 1] = { id = id, args = { ... } }
            return id
        end
        _G.setColPolygonHeight = function(col, floor, ceil)
            mock.calls[#mock.calls + 1] = { "setColPolygonHeight", col, floor, ceil }
            return true
        end
        _G.isInsideColShape = function()
            return false -- exercise the pure polygon fallback in unit tests
        end
        _G.getElementsByType = function()
            return {}
        end
        _G.getElementDimension = function()
            return 0
        end
        _G.getElementPosition = function()
            return 2495, -1687, 13.5
        end
        dofile("resources/[scavengesurvive]/maps/server/main.lua")
        mock.fire("onResourceStart")
    end)

    it("creates seven polygon colshapes and resolves getZoneAt", function()
        assert.equals(7, #createdCols)
        assert.equals("ls", _G.getZoneAt(2495, -1687))
        assert.equals("sf", _G.getZoneAt(-2026, 156))
        assert.is_false(_G.getZoneAt(3500, -3500))
    end)

    it("tracks player zones and fires onPlayerZoneEnter and onPlayerZoneLeave", function()
        local p = "player:1"
        mock.addElement(p)
        local lsCol = createdCols[1].id --zones.ORDER[1] == "ls"
        local rcCol = createdCols[4].id --zones.ORDER[4] == "rc"

        _G.source = lsCol
        mock.fire("onColShapeHit", p, true)
        assert.equals("ls", _G.getPlayerZone(p))

        -- Crossing directly into RC emits leave(ls) then enter(rc)
        _G.source = rcCol
        mock.fire("onColShapeHit", p, true)
        assert.equals("rc", _G.getPlayerZone(p))

        -- Leaving RC into the ocean clears the player's zone
        _G.getElementPosition = function()
            return 3500, -3500, 0
        end
        _G.source = rcCol
        mock.fire("onColShapeLeave", p, true)
        assert.is_false(_G.getPlayerZone(p))

        local events = {}
        for _, c in ipairs(mock.calls) do
            if c[1] == "triggerEvent" then
                events[#events + 1] = { c[2], c[3], c[4] }
            end
        end
        assert.same({
            { "onPlayerZoneEnter", p, "ls" },
            { "onPlayerZoneLeave", p, "ls" },
            { "onPlayerZoneEnter", p, "rc" },
            { "onPlayerZoneLeave", p, "rc" },
        }, events)
    end)
end)
