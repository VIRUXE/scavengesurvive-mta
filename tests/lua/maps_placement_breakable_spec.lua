local placement = dofile("resources/[scavengesurvive]/maps/shared/logic/placement.lua")

describe("maps placement breakable fences", function()
    it("places wire fence panels as objects so they can break", function()
        assert.is_true(placement.isBreakable(1651))
        assert.equals("object", placement.kind({ 1651, 0, 0, 0, 0, 0, 0, -1, -1, 350 }))
    end)

    it("keeps other vanilla models as buildings", function()
        assert.is_false(placement.isBreakable(1225))
        assert.equals("building", placement.kind({ 1225, 0, 0, 0, 0, 0, 0, -1, -1, 350 }))
    end)
end)
