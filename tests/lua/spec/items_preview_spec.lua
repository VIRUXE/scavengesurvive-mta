local p = dofile("resources/[scavengesurvive]/items/shared/logic/preview.lua")

local IDENTITY = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } }
-- 90 degrees about Z: local +x becomes world +y
local YAW90 = { { 0, 1, 0, 0 }, { -1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 5, 6, 7, 1 } }

describe("gear tile previews", function()
    it("uses the tile below its title bar, centred", function()
        local a = p.area(100, 200, 65, 65, 14)
        assert.same({ x = 100, y = 214, w = 65, h = 51, cx = 132.5, cy = 239.5 }, a)
    end)

    it("measures metres per pixel from two probe points", function()
        assert.is_true(math.abs(p.metresPerPixel(0, 0, 0, 0, 0, 0.05) - 0.005) < 1e-9)
    end)

    it("frames a box centred on the origin with no offset", function()
        local f = p.frame(-1, -2, -3, 1, 2, 3, IDENTITY)
        assert.same({ 0, 0, 0 }, { f.ox, f.oy, f.oz })
        assert.is_true(math.abs(f.radius - 3 * 1.1) < 1e-9) -- largest half-extent (z: 3) with SLACK
    end)

    it("rotates an off-centre box with the object's matrix and ignores its position row", function()
        local f = p.frame(0, 0, 0, 2, 0, 0, YAW90) -- centre at local (1, 0, 0)
        assert.is_true(math.abs(f.ox) < 1e-9 and math.abs(f.oy - 1) < 1e-9 and math.abs(f.oz) < 1e-9)
        assert.is_true(math.abs(f.radius - 1.1) < 1e-9)
    end)

    it("scales the silhouette radius to FILL of the shorter side", function()
        local area = { w = 65, h = 51 }
        local s = p.scale(0.5, area, 0.01) -- 51 px * 1.0 * 0.01 m/px = 0.51 m wanted diameter, model is 1 m
        assert.is_true(math.abs(s - 0.51) < 1e-9)
        assert.equals(1, p.scale(0, area, 0.01))
        assert.equals(1, p.scale(0.5, area, 0))
    end)

    it("shifts the drawn origin so the box centre lands on the tile point", function()
        local x, y, z = p.origin(10, 20, 30, { ox = 1, oy = -2, oz = 0.5 }, 2)
        assert.same({ 8, 24, 29 }, { x, y, z })
    end)
end)
