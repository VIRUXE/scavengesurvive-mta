local liquid = dofile("resources/[scavengesurvive]/items/shared/logic/liquid.lua")

local CAN =
    { category = "liquid", categoryData = { capacity = 20.0, liquids = { { "Petrol", 100.0 } }, reusable = true } }
local BOTTLE = { category = "generic", categoryData = nil }

describe("liquid containers", function()
    it("knows the Petrol Can and its capacity", function()
        assert.is_true(liquid.isContainer(CAN))
        assert.is_false(liquid.isContainer(BOTTLE))
        assert.is_false(liquid.isContainer(nil))
        assert.equals(20, liquid.capacity(CAN))
        assert.equals(0, liquid.capacity(BOTTLE))
    end)
    it("reads the amount from either data form and counts no amount as full", function()
        assert.equals(12.3, liquid.amount(CAN, { amount = 12.3 }))
        assert.equals(12.3, liquid.amount(CAN, { { amount = 12.3 } })) -- MTA's wrapped toJSON form
        assert.equals(20, liquid.amount(CAN, nil))
        assert.equals(20, liquid.amount(CAN, {}))
        assert.equals(20, liquid.amount(CAN, { amount = 25 })) -- clamped to the capacity
        assert.equals(0, liquid.amount(CAN, { amount = -1 }))
    end)
    it("labels the litres held, Empty at zero, and leaves other types alone", function()
        assert.equals("Petrol Can (12.3 L)", liquid.label(CAN, "Petrol Can", { amount = 12.3 }))
        assert.equals("Petrol Can (20.0 L)", liquid.label(CAN, "Petrol Can", nil))
        assert.equals("Petrol Can (0.1 L)", liquid.label(CAN, "Petrol Can", { amount = 0.1 }))
        assert.equals("Petrol Can (Empty)", liquid.label(CAN, "Petrol Can", { amount = 0 }))
        assert.equals("Bottle", liquid.label(BOTTLE, "Bottle", { amount = 5 }))
    end)
end)
