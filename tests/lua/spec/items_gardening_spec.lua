-- Gardening (items/shared/logic/gardening.lua, upstream plantpot.pwn and seedbag.pwn, #142).
local gardening = dofile("resources/[scavengesurvive]/items/shared/logic/gardening.lua")
local liquids = dofile("resources/[scavengesurvive]/items/shared/logic/liquids.lua")
local BOTTLE = { category = "liquid", categoryData = { capacity = 0.5, liquids = { { "Water", 100 } } } }

describe("items gardening", function()
    it("rolls a looted bag's seeds from its id and reads stored seeds as they are", function()
        local a, b = gardening.seedsFor(1001), gardening.seedsFor(1001)
        assert.same(a, b)
        assert.is_true(a.amount >= 0 and a.amount <= gardening.MAX_SEEDS)
        assert.is_true(a.kind >= 1 and a.kind <= #gardening.SEEDS)
        local counts = {}
        for id = 1, 400 do
            local s = gardening.seedsFor(id)
            counts[s.amount] = (counts[s.amount] or 0) + 1
        end
        for amount = 0, gardening.MAX_SEEDS do
            assert.is_true((counts[amount] or 0) > 0, "no bag with " .. amount .. " seeds")
        end
        assert.same({ amount = 3, kind = 1 }, gardening.seedsFor(5, { seeds = { amount = 3, kind = 1 } }))
        assert.same({ amount = 3, kind = 1 }, gardening.seedsFor(5, { { seeds = { amount = "3", kind = "1" } } }))
    end)

    it("labels the bag with its count and kind", function()
        assert.are.equal("Seeds (3, Tomato)", gardening.seedLabel("Seeds", { amount = 3, kind = 1 }))
        assert.are.equal("Seeds (1, Unknown)", gardening.seedLabel("Seeds", { amount = 1, kind = 7 }))
        assert.are.equal("Seeds (Empty)", gardening.seedLabel("Seeds", { amount = 0, kind = 1 }))
        assert.are.equal("Seeds (Empty)", gardening.seedLabel("Seeds", nil))
    end)

    it("plants one seed from a bag into an empty pot", function()
        local pot = gardening.pot(nil)
        assert.is_false(pot.active)
        local ok, nextPot, nextSeeds = gardening.plant(pot, { amount = 2, kind = 4 })
        assert.is_true(ok)
        assert.same({ active = true, kind = 4, water = 0, growth = 0 }, nextPot)
        assert.same({ amount = 1, kind = 4 }, nextSeeds)
        assert.is_false(gardening.plant(pot, { amount = 0, kind = 4 }))
        assert.is_false(gardening.plant(pot, { amount = 1, kind = 99 }))
        assert.same({ active = 1, kind = 4, water = 0, growth = 0 }, gardening.encodePot(nextPot))
        assert.same(nextPot, gardening.pot({ pot = gardening.encodePot(nextPot) }))
    end)

    it("takes a tenth of a litre of water per pour, only water", function()
        local pot = { active = true, kind = 1, water = 0, growth = 0 }
        local ok, nextPot, nextData = gardening.water(pot, liquids, BOTTLE, { amount = 0.45, liquid = "Water" })
        assert.is_true(ok)
        assert.are.equal(1, nextPot.water)
        assert.is_true(math.abs(nextData.amount - 0.35) < 1e-6)
        assert.same({ false, "POTBOTEMPTY" }, { gardening.water(pot, liquids, BOTTLE, { amount = 0 }) })
        assert.same(
            { false, "POTBOTNOWAT" },
            { gardening.water(pot, liquids, BOTTLE, { amount = 0.3, liquid = "Milk" }) }
        )
    end)

    it("grows while watered, withers dry, dies at zero", function()
        local pot = { active = true, kind = 1, water = 2, growth = 0 }
        pot = gardening.grow(pot)
        assert.same({ active = true, kind = 1, water = 1, growth = 1 }, pot)
        pot = gardening.grow(pot)
        assert.same({ active = true, kind = 1, water = 0, growth = 2 }, pot)
        pot = gardening.grow(pot)
        assert.same({ active = true, kind = 1, water = 0, growth = 1 }, pot)
        pot = gardening.grow(pot)
        assert.same(gardening.empty(), pot)
        assert.same(gardening.empty(), gardening.grow(gardening.empty()))
    end)

    it("harvests the crop once grown, a bush gives nothing, an empty pot refuses", function()
        assert.same({ false, "POTNOACPLNT" }, { gardening.harvest(gardening.empty()) })
        assert.same({ false, "POTNOTGROWN" }, { gardening.harvest({ active = true, kind = 1, water = 0, growth = 3 }) })
        assert.same(
            { false, "POTINVASEED" },
            { gardening.harvest({ active = true, kind = 99, water = 0, growth = 9 }) }
        )
        local ok, crop, nextPot = gardening.harvest({ active = true, kind = 1, water = 2, growth = 4 })
        assert.is_true(ok)
        assert.are.equal("Tomato", crop)
        assert.same(gardening.empty(), nextPot)
        ok, crop = gardening.harvest({ active = true, kind = 7, water = 0, growth = 0 })
        assert.is_true(ok)
        assert.is_nil(crop)
    end)

    it("shows nothing just planted, a rising sprout, then the full plant", function()
        assert.is_nil(gardening.plantObject(gardening.empty()))
        assert.is_nil(gardening.plantObject({ active = true, kind = 1, water = 0, growth = 0 }))
        local model, lift = gardening.plantObject({ active = true, kind = 1, water = 0, growth = 2 })
        assert.are.equal(gardening.SPROUT_MODEL, model)
        assert.is_true(math.abs(lift - gardening.SPROUT_RISE / 2) < 1e-6)
        model, lift = gardening.plantObject({ active = true, kind = 1, water = 0, growth = 4 })
        assert.same({ 631, 0.90649 }, { model, lift })
        model = gardening.plantObject({ active = true, kind = 7, water = 0, growth = 0 }) -- a bush stands at once
        assert.are.equal(692, model)
    end)

    it("prints the status lines", function()
        local s = gardening.status({ active = true, kind = 4, water = 2, growth = 3 })
        assert.are.equal("Active: yes\nSeed type: Banana\nWater: 2\nGrowth: 3/6", s)
        assert.are.equal("Active: no\nSeed type: -\nWater: 0\nGrowth: 0/0", gardening.status(gardening.empty()))
    end)
end)
