local fields = dofile("resources/[scavengesurvive]/anticheat/shared/logic/fields.lua")

local square = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } }

describe("anticheat detection fields", function()
    it("tests a point against a polygon with the even-odd rule", function()
        assert.is_true(fields.insidePolygon(5, 5, square))
        assert.is_false(fields.insidePolygon(15, 5, square))
        assert.is_false(fields.insidePolygon(5, -1, square))
        -- a concave arrowhead: the notch is outside even though the bounding box holds it
        local arrow = { { 0, 0 }, { 10, 5 }, { 0, 10 }, { 4, 5 } }
        assert.is_true(fields.insidePolygon(6, 5, arrow))
        assert.is_false(fields.insidePolygon(1, 5, arrow))
    end)
    it("keeps a field to its Z band", function()
        local f = { points = square, min_z = 0, max_z = 20 }
        assert.is_true(fields.contains(f, 5, 5, 10))
        assert.is_false(fields.contains(f, 5, 5, 25))
        assert.is_false(fields.contains(f, 5, 5, -1))
    end)
    it("builds a field from a row and refuses malformed ones", function()
        local row = { id = "3", name = "smoke", min_z = "0", max_z = "20" }
        local f = fields.fromRow(row, { { "995", "995" }, { 1005, 995 }, { 1005, 1005 }, { 995, 1005 } })
        assert.same(
            {
                id = 3,
                name = "smoke",
                points = { { 995, 995 }, { 1005, 995 }, { 1005, 1005 }, { 995, 1005 } },
                min_z = 0,
                max_z = 20,
            },
            f
        )
        assert.is_nil(fields.fromRow(row, false))
        assert.is_nil(fields.fromRow(row, { { 0, 0 }, { 1, 0 }, { 1, 1 } }))
        assert.is_nil(fields.fromRow(row, { { 0, 0 }, { 1, 0 }, { 1, 1 }, { "x", 1 } }))
        assert.is_nil(fields.fromRow({ id = 3, name = "flat", min_z = 5, max_z = 5 }, square))
    end)
    it("reports an entry once until the player leaves", function()
        local list = {
            { id = 1, name = "a", points = square, min_z = 0, max_z = 20 },
            { id = 2, name = "b", points = { { 5, 5 }, { 20, 5 }, { 20, 20 }, { 5, 20 } }, min_z = 0, max_z = 20 },
        }
        local active, entered = fields.scan(list, nil, 2, 2, 1)
        assert.same({ [1] = true }, active)
        assert.equals(1, #entered)
        assert.equals("a", entered[1].name)
        -- still inside a, now also in b: only b is new
        active, entered = fields.scan(list, active, 7, 7, 1)
        assert.same({ [1] = true, [2] = true }, active)
        assert.same({ "b" }, { entered[1].name })
        -- out of both, then back into a: a is logged again
        active, entered = fields.scan(list, active, 50, 50, 1)
        assert.same({}, active)
        assert.equals(0, #entered)
        active, entered = fields.scan(list, active, 2, 2, 1)
        assert.same({ [1] = true }, active)
        assert.same({ "a" }, { entered[1].name })
    end)
end)
