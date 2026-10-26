local liquids = dofile("resources/[scavengesurvive]/items/shared/logic/liquids.lua")

local BOTTLE = {
    name = "Bottle",
    category = "liquid",
    categoryData = { capacity = 0.5, liquids = { { "Water", 100.0 }, { "Orange", 50.0 } }, reusable = true },
}
local GASCAN =
    { name = "Petrol Can", category = "liquid", categoryData = { capacity = 20.0, liquids = { { "Petrol", 100.0 } } } }
local BREAD = { name = "Bread", category = "food", categoryData = {} }

describe("liquid containers", function()
    it("reads the amount and liquid from plain and wrapped data, empty below a millilitre", function()
        assert.same({ 0.4, "Water" }, { liquids.decode(BOTTLE, { amount = 0.4, liquid = "Water" }) })
        assert.same({ 0.4, "Water" }, { liquids.decode(BOTTLE, { { amount = 0.4, liquid = "Water" } }) })
        assert.same({ 0, nil }, { liquids.decode(BOTTLE, { amount = 0.0005, liquid = "Water" }) })
        assert.same({ 0, nil }, { liquids.decode(BOTTLE, nil) })
    end)
    it(
        "assumes the only possible liquid when the data carries just an amount (vehicles write the Petrol Can so)",
        function()
            assert.same({ 12.5, "Petrol" }, { liquids.decode(GASCAN, { amount = 12.5 }) })
            assert.same({ 0, nil }, { liquids.decode(BOTTLE, { amount = 0.3 }) }) -- two candidates: unknown
        end
    )
    it("labels as upstream: liquid, amount and capacity, or Empty", function()
        assert.equals("Bottle (Water 0.4/0.50)", liquids.label(BOTTLE, "Bottle", { amount = 0.4, liquid = "Water" }))
        assert.equals(
            "Bottle (Orange Juice 0.1/0.50)",
            liquids.label(BOTTLE, "Bottle", { amount = 0.12, liquid = "Orange" })
        )
        assert.equals("Bottle (Empty)", liquids.label(BOTTLE, "Bottle", nil))
        assert.is_true(liquids.isContainer(BOTTLE))
        assert.is_false(liquids.isContainer(BREAD))
    end)
    it("takes 0.2 L per sip with the liquid's food value, and refuses an empty container", function()
        local ok, data, food = liquids.sip(BOTTLE, { amount = 0.5, liquid = "Milk" })
        assert.is_true(ok)
        assert.same({ amount = 0.3, liquid = "Milk" }, data)
        assert.equals(2.1, food)
        ok, data, food = liquids.sip(GASCAN, { amount = 0.1 })
        assert.is_true(ok)
        assert.equals(0, data.amount)
        assert.equals(-8.0, food)
        assert.same({ false, "EMPTY" }, { liquids.sip(BOTTLE, { amount = 0, liquid = "Water" }) })
    end)
end)
