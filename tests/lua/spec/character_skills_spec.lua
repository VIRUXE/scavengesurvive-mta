local skills = dofile("resources/[scavengesurvive]/character/shared/logic/skills.lua")

describe("character skills", function()
    it("starts empty and reads 0 for an unknown skill", function()
        local s = skills.fromList(false)
        assert.equals(0, skills.value(s, "Repair"))
        assert.equals("[]", skills.encode(s))
    end)

    it("gains RATE x mult of the gap to 1.0", function()
        local s = skills.fromList({})
        assert.is_true(math.abs(skills.gain(s, "Repair") - 0.02) < 1e-9)
        assert.is_true(math.abs(skills.gain(s, "Repair") - (0.02 + 0.02 * 0.98)) < 1e-9)
        assert.is_true(math.abs(skills.gain(s, "Fishing", 2) - 0.04) < 1e-9)
    end)

    it("reaches Master after about 115 actions and never passes 1.0", function()
        local s = skills.fromList({})
        local n = 0
        while skills.value(s, "Repair") < 0.9 do
            skills.gain(s, "Repair")
            n = n + 1
        end
        assert.equals(114, n)
        for _ = 1, 5000 do
            skills.gain(s, "Repair", 10)
        end
        assert.is_true(skills.value(s, "Repair") <= 1)
    end)

    it("cuts up to half of an action's time", function()
        local s = skills.fromList({ { "Repair", 0.5 }, { "Workbench", 1 } })
        assert.equals(3000, skills.timeModifier(s, 3000, "Fishing"))
        assert.equals(2250, skills.timeModifier(s, 3000, "Repair"))
        assert.equals(1500, skills.timeModifier(s, 3000, "Workbench"))
    end)

    it("names levels by upper bound and shows Master at 0.9 and above", function()
        assert.equals("Novice", skills.level(0).name)
        assert.equals("Adequate", skills.level(0.1).name)
        assert.equals("Intermediate", skills.level(0.2).name)
        assert.equals("Experienced", skills.level(0.5).name)
        assert.equals("Master", skills.level(0.7).name)
        assert.equals("Master", skills.level(1).name)
    end)

    it("round-trips through the column text and drops bad pairs", function()
        local s = skills.fromList({ { "Repair", 0.25 }, { "Repair", 0.9 }, { "bad name", 1 }, { "Big", 7 }, "x" })
        assert.same({ "Repair", "Big" }, s.order)
        assert.equals(1, skills.value(s, "Big"))
        assert.equals('[["Repair",0.250000],["Big",1.000000]]', skills.encode(s))
    end)

    it("caps the list at MAX_SKILLS and validates names", function()
        local s = skills.fromList({})
        for i = 1, skills.MAX_SKILLS do
            assert.is_truthy(skills.set(s, "S" .. i, 0.1))
        end
        assert.is_false(skills.set(s, "OneMore", 0.1))
        assert.is_false(skills.gain(s, "OneMore"))
        assert.is_false(skills.set(s, string.rep("a", skills.MAX_NAME + 1), 0.1))
        assert.is_false(skills.set(s, 'x"y', 0.1))
    end)

    it("lists rows with level and colour in learned order", function()
        local rows = skills.rows(skills.fromList({ { "Workbench", 0.95 }, { "Repair", 0.05 } }))
        assert.equals("Workbench", rows[1].name)
        assert.equals("Master", rows[1].level)
        assert.equals("Novice", rows[2].level)
        assert.same({ 0xFF, 0xFF, 0x00 }, rows[2].colour)
    end)
end)
