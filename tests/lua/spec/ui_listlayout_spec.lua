local layout = dofile("resources/[scavengesurvive]/ui/shared/logic/listlayout.lua")
local rows = {
    {
        id = 1,
        label = "Knife",
        sub = "",
        actions = { { id = "take", label = "Take" }, { id = "drop", label = "Drop" } },
    },
    { id = 2, label = "Bandage", sub = "", actions = { { id = "use", label = "Use" } } },
}
describe("listlayout", function()
    it("centres a panel and stacks rows", function()
        local c = layout.compute(rows, nil, 1920, 1080, 1)
        assert.is_true(c.panel.x > 0 and c.panel.w > 300)
        assert.equals(2, #c.rows)
        assert.is_true(c.rows[2].y > c.rows[1].y)
        assert.equals(0, #c.rows[1].actions) -- collapsed
    end)
    it("expands one row's actions and hit-tests them", function()
        local c = layout.compute(rows, 1, 1920, 1080, 1)
        assert.equals(2, #c.rows[1].actions)
        local a = c.rows[1].actions[2]
        local kind, rowId, actionId = layout.hit(c, a.x + 1, a.y + 1)
        assert.same({ "action", 1, "drop" }, { kind, rowId, actionId })
        kind, rowId = layout.hit(c, c.rows[2].x + 1, c.rows[2].y + 1)
        assert.same({ "row", 2 }, { kind, rowId })
        assert.equals("close", (layout.hit(c, c.close.x + 1, c.close.y + 1)))
        assert.is_nil((layout.hit(c, 1, 1)))
    end)
    it("scales with resolution", function()
        local a = layout.compute(rows, nil, 1920, 1080, 1)
        local b = layout.compute(rows, nil, 1280, 720, 720 / 1080)
        assert.is_true(b.rowH < a.rowH)
    end)
end)
