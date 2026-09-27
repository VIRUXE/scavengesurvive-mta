local g = dofile("resources/[scavengesurvive]/items/shared/logic/geometry.lua")
describe("items geometry", function()
    it("drops in front of the player using MTA rotation", function()
        local x, y = g.dropPosition(0, 0, 0, 1.0) -- facing north => +y
        assert.is_true(math.abs(x) < 1e-6 and math.abs(y - 1) < 1e-6)
        x, y = g.dropPosition(0, 0, 90, 1.0) -- facing west => -x
        assert.is_true(math.abs(x + 1) < 1e-6 and math.abs(y) < 1e-6)
    end)
    it("builds a bounding box and WKT polygon", function()
        assert.same({ -10, -10, 10, 10 }, { g.box(0, 0, 10) })
        assert.equals("POLYGON((-10 -10,10 -10,10 10,-10 10,-10 -10))", g.polygonWKT(-10, -10, 10, 10))
    end)
end)
