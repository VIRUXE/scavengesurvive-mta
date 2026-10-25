local g = dofile("resources/[scavengesurvive]/items/shared/logic/geometry.lua")
describe("items geometry", function()
    it("drops in front of the player using MTA rotation", function()
        local x, y = g.dropPosition(0, 0, 0, 1.0) -- facing north => +y
        assert.is_true(math.abs(x) < 1e-6 and math.abs(y - 1) < 1e-6)
        x, y = g.dropPosition(0, 0, 90, 1.0) -- facing west => -x
        assert.is_true(math.abs(x + 1) < 1e-6 and math.abs(y) < 1e-6)
    end)
    it("tilts an object's matrix onto the ground normal", function()
        local function near(a, b)
            assert.is_true(math.abs(a - b) < 1e-6, string.format("%f ~= %f", a, b))
        end
        local flat = { { 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 5, 6, 7, 1 } }
        assert.equals(flat, g.tilt(flat, 0, 0))
        local s, c = math.sin(math.rad(30)), math.cos(math.rad(30))
        local m = g.tilt(flat, s, 0) -- ground rising to -x: up leans to +x
        near(s, m[3][1])
        near(0, m[3][2])
        near(c, m[3][3])
        near(c, m[1][1]) -- right dips with the slope
        near(-s, m[1][3])
        assert.same({ 0, 1, 0, 0 }, m[2]) -- the axis it turns about stays put
        assert.same({ 5, 6, 7, 1 }, m[4])
        -- any turned object: rows stay unit length and orthogonal
        local r = math.rad(40)
        local turned = { { math.cos(r), math.sin(r), 0, 0 }, { -math.sin(r), math.cos(r), 0, 0 }, { 0, 0, 1, 0 }, flat[4] }
        local t = g.tilt(turned, 0.3, -0.2)
        for i = 1, 3 do
            near(1, t[i][1] ^ 2 + t[i][2] ^ 2 + t[i][3] ^ 2)
        end
        near(0, t[1][1] * t[2][1] + t[1][2] * t[2][2] + t[1][3] * t[2][3])
        near(0.3, t[3][1])
        near(-0.2, t[3][2])
    end)
    it("builds a bounding box and WKT polygon", function()
        assert.same({ -10, -10, 10, 10 }, { g.box(0, 0, 10) })
        assert.equals("POLYGON((-10 -10,10 -10,10 10,-10 10,-10 -10))", g.polygonWKT(-10, -10, 10, 10))
    end)
end)
