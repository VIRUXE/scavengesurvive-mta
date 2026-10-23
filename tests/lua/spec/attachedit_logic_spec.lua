local ae = dofile("resources/[scavengesurvive]/attachedit/shared/logic/attachedit.lua")

local function cfg()
    return {
        slot = "hat",
        uname = "Beanie",
        skin = 23,
        bone = 2,
        offsets = { 0.152, 0, -0.006, 0, 90, 0 },
        scale = { 1, 1.1, 1 },
    }
end

describe("attachedit logic", function()
    it("starts from the live values, field 1 and the finest steps", function()
        local s = ae.new(cfg())
        assert.same({ 0.152, 0, -0.006, 0, 90, 0, 1, 1.1, 1 }, s.values)
        assert.equals(1, s.field)
        assert.equals(0.001, ae.step(s))
        assert.equals("Beanie", s.uname)
        assert.equals(23, s.skin)
    end)

    it("defaults missing offsets to 0 and a missing scale to 1", function()
        local s = ae.new({ slot = "held", uname = "Wrench" })
        assert.same({ 0, 0, 0, 0, 0, 0, 1, 1, 1 }, s.values)
    end)

    it("cycles the selected field both ways", function()
        local s = ae.new(cfg())
        ae.moveField(s, -1)
        assert.equals(9, s.field)
        ae.moveField(s, 1)
        assert.equals(1, s.field)
        ae.selectField(s, 5)
        assert.equals("ry", ae.FIELDS[s.field])
        ae.selectField(s, 10)
        assert.equals(1, s.field)
    end)

    it("cycles each kind's steps separately", function()
        local s = ae.new(cfg())
        ae.cycleStep(s, 1)
        assert.equals(0.005, ae.step(s))
        ae.cycleStep(s, 1)
        assert.equals(0.02, ae.step(s))
        ae.cycleStep(s, 1)
        assert.equals(0.001, ae.step(s))
        ae.cycleStep(s, -1)
        assert.equals(0.02, ae.step(s))
        ae.selectField(s, 4)
        assert.equals(1, ae.step(s)) -- rotation kept its own index
        ae.cycleStep(s, 1)
        ae.cycleStep(s, 1)
        assert.equals(15, ae.step(s))
        ae.selectField(s, 8)
        assert.equals(0.01, ae.step(s))
        ae.cycleStep(s, 1)
        ae.cycleStep(s, 1)
        assert.equals(0.01, ae.step(s)) -- scale has two steps
        ae.selectField(s, 1)
        assert.equals(0.02, ae.step(s))
    end)

    it("nudges the selected field without float drift", function()
        local s = ae.new(cfg())
        for _ = 1, 10 do
            ae.nudge(s, 1)
        end
        assert.equals(0.162, s.values[1])
        ae.selectField(s, 2)
        ae.nudge(s, -1)
        assert.equals(-0.001, s.values[2])
    end)

    it("clamps positions and scales and folds rotations", function()
        assert.equals(2, ae.clamp("pos", 5))
        assert.equals(-2, ae.clamp("pos", -5))
        assert.equals(0.01, ae.clamp("scale", 0))
        assert.equals(10, ae.clamp("scale", 50))
        assert.equals(254.87, ae.clamp("rot", 254.87))
        assert.equals(5, ae.clamp("rot", 365))
        assert.equals(-5, ae.clamp("rot", -365))
        assert.equals(0, ae.clamp("rot", 360))
        local s = ae.new({ slot = "bag", scale = { 0.01, 1, 1 } })
        ae.selectField(s, 7)
        ae.nudge(s, -1)
        assert.equals(0.01, s.values[7])
        ae.selectField(s, 6)
        ae.cycleStep(s, -1)
        for _ = 1, 25 do
            ae.nudge(s, 1)
        end
        assert.equals(15, s.values[6]) -- 375 folded back under a full turn
    end)

    it("maps keys to actions", function()
        local s = ae.new(cfg())
        assert.equals("ui", ae.handleKey(s, "3"))
        assert.equals(3, s.field)
        assert.equals("ui", ae.handleKey(s, "num_7"))
        assert.equals(7, s.field)
        assert.equals("ui", ae.handleKey(s, "arrow_u"))
        assert.equals(6, s.field)
        assert.equals("changed", ae.handleKey(s, "pgup"))
        assert.equals(1, s.values[6])
        assert.equals("changed", ae.handleKey(s, "-"))
        assert.equals(0, s.values[6])
        assert.equals("ui", ae.handleKey(s, "0"))
        assert.equals(5, ae.step(s))
        assert.equals("save", ae.handleKey(s, "enter"))
        assert.equals("cancel", ae.handleKey(s, "escape"))
        assert.is_nil(ae.handleKey(s, "w"))
        assert.is_nil(ae.handleKey(s, "f"))
    end)

    it("rounds to 3 decimals, drops trailing zeros and never prints -0", function()
        assert.equals(0.153, ae.round(0.15251))
        assert.equals(0, ae.round(-0.0004))
        assert.equals(
            "{ 0.152, 0.0, -0.006, -8.7, 254.87, 0.0, 1.0, 1.1, 1.027 }",
            ae.formatRow({ 0.1524, 0, -0.0061, -8.7, 254.87, -0.0001, 1, 1.1, 1.0271 })
        )
    end)

    it("formats a row ready for OVERRIDES[uname]", function()
        assert.equals(
            "[23] = { 0.152, 0.0, -0.006, 0.0, 90.0, 0.0, 1.0, 1.1, 1.0 }, -- Beanie hat",
            ae.formatEntry("Beanie", 23, "hat", ae.new(cfg()).values)
        )
    end)

    it("describes the state with the selected field marked", function()
        local s = ae.new(cfg())
        ae.selectField(s, 2)
        local lines = ae.describe(s)
        assert.truthy(lines[1]:find("slot=hat", 1, true))
        assert.truthy(lines[1]:find("Beanie", 1, true))
        assert.truthy(lines[1]:find("skin=23", 1, true))
        assert.equals("step 0.001 (pos)", lines[2])
        assert.equals("> 2 y  0.0", lines[4])
        assert.equals("  1 x  0.152", lines[3])
        assert.equals(9 + 3, #lines)
    end)

    it("parses rcon arguments", function()
        assert.same({ action = "off" }, ae.parseArgs({ "off" }))
        assert.same({ action = "get" }, ae.parseArgs({ "get" }))
        assert.same(
            { action = "set", offsets = { 0.1, 0, 0, 0, 0, 90 }, scale = { 1, 1, 1 } },
            ae.parseArgs({ "0.1", "0", "0", "0", "0", "90" })
        )
        assert.same(
            { action = "set", offsets = { 2, 0, 0, 5, 0, 0 }, scale = { 1.2, 0.01, 1 } },
            ae.parseArgs({ "9", "0", "0", "365", "0", "0", "1.2", "0", "1" })
        )
        assert.is_nil(ae.parseArgs({}))
        assert.is_nil(ae.parseArgs({ "1", "2", "3" }))
        local r, err = ae.parseArgs({ "1", "2", "3", "4", "5", "x" })
        assert.is_nil(r)
        assert.truthy(err:find("'x'", 1, true))
    end)

    it("accepts only nine finite numbers from a client", function()
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, ae.checkValues({ 1, 2, 3, 4, 5, 6, 7, 8, "9" }))
        assert.is_nil(ae.checkValues({ 1, 2, 3 }))
        assert.is_nil(ae.checkValues({ 1, 2, 3, 4, 5, 6, 7, 8, 0 / 0 }))
        assert.is_nil(ae.checkValues({ 1, 2, 3, 4, 5, 6, 7, 8, math.huge }))
        assert.is_nil(ae.checkValues("x"))
    end)

    it("joins offsets and scale back into nine values", function()
        assert.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, ae.join({ 1, 2, 3, 4, 5, 6 }, { 7, 8, 9 }))
        assert.same({ 1, 2, 3, 4, 5, 6, 1, 1, 1 }, ae.join({ 1, 2, 3, 4, 5, 6 }))
        local o, sc = ae.split(ae.join({ 1, 2, 3, 4, 5, 6 }, { 7, 8, 9 }))
        assert.same({ 1, 2, 3, 4, 5, 6 }, o)
        assert.same({ 7, 8, 9 }, sc)
    end)

    it("knows the attach slots", function()
        for _, slot in ipairs({ "hat", "mask", "armour", "bag", "holster", "held", "cuffs" }) do
            assert.is_true(ae.isSlot(slot))
        end
        assert.is_false(ae.isSlot("shoes"))
        assert.is_false(ae.isSlot(nil))
    end)
end)
