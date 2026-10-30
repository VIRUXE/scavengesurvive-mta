local explosives = dofile("resources/[scavengesurvive]/explosives/shared/logic/explosives.lua")

describe("explosives pure logic", function()
    describe("presets", function()
        it("defines all upstream presets accurately", function()
            local p = explosives.PRESETS
            assert.is_table(p)
            assert.are.same({ anim = 12, size = 3.0, itemDmg = 1 }, p.SMALL)
            assert.are.same({ anim = 0, size = 8.0, itemDmg = 2 }, p.MEDIUM)
            assert.are.same({ anim = 6, size = 24.0, itemDmg = 3 }, p.LARGE)
            assert.are.same({ anim = 2, size = 5.0, itemDmg = 0, unimplemented = true }, p.INCEN)
            assert.are.same({ anim = 4, size = 8.0, itemDmg = 0, unimplemented = true }, p.THERM)
            assert.are.same({ anim = 0, size = 12.0, itemDmg = 0, emp = true, knockoutMs = 60000 }, p.EMP)
            assert.are.same({
                anim = 12,
                size = 10.0,
                itemDmg = 0,
                shrapnel = true,
                knockRange = 3.0,
                knockDurationMs = 3000,
                bleedRange = 10.0,
                bleedRate = 0.005,
                hpLoss = 25.0,
            }, p.SHRAP)
        end)

        it("looks up presets by name", function()
            assert.is_not_nil(explosives.getPreset("MEDIUM"))
            assert.are.equal(8.0, explosives.getPreset("MEDIUM").size)
            assert.is_nil(explosives.getPreset("NON_EXISTENT"))
        end)
    end)

    describe("distance and range filtering", function()
        it("calculates 3D distance correctly", function()
            -- Point at (0, 0, 0) and (2, 2, 1) -> dist^2 = 4 + 4 + 1 = 9 (dist = 3.0)
            assert.is_true(explosives.isItemInRange(2, 2, 1, 0, 0, 0, 3.0))
            assert.is_true(explosives.isItemInRange(2, 2, 1, 0, 0, 0, 3.1))
            assert.is_false(explosives.isItemInRange(2, 2, 1, 0, 0, 0, 2.9))
        end)

        it("filters items within range, interior, and dimension", function()
            local items = {
                { id = 1, x = 0, y = 2, z = 0, interior = 0, dimension = 0 },
                { id = 2, x = 0, y = 10, z = 0, interior = 0, dimension = 0 },
                { id = 3, x = 0, y = 1, z = 0, interior = 1, dimension = 0 },
                { id = 4, x = 0, y = 1, z = 0, interior = 0, dimension = 2 },
            }
            local res = explosives.filterItemsInRange(items, 0, 0, 0, 5.0, 0, 0)
            assert.are.equal(1, #res)
            assert.are.equal(1, res[1].id)
        end)
    end)

    describe("damage calculation", function()
        it("partitions destroyed and surviving items", function()
            local items = {
                { id = 10, uname = "CorPanel", hitpoints = 5, x = 1, y = 2, z = 3 },
                { id = 20, uname = "Door", hitpoints = 2, x = 4, y = 5, z = 6 },
            }
            local destroyed, damaged = explosives.calculateItemDamage(items, 2)
            assert.are.equal(1, #damaged)
            assert.are.equal(10, damaged[1].id)
            assert.are.equal(3, damaged[1].hp)

            assert.are.equal(1, #destroyed)
            assert.are.equal(20, destroyed[1].id)
            assert.are.equal("Door", destroyed[1].uname)
        end)

        it("carries what a broken defence did not need on to the next nearest", function()
            local items = {
                { id = 3, def = true, hitpoints = 5, x = 3, y = 0, z = 0 },
                { id = 1, def = true, hitpoints = 1, x = 1, y = 0, z = 0 },
                { id = 2, def = true, hitpoints = 1, x = 2, y = 0, z = 0 },
                { id = 9, def = false, hitpoints = 4, x = 5, y = 0, z = 0 },
            }
            local isDefence = function(it)
                return it.def
            end
            local batch = explosives.spreadDamage(items, 3, 0, 0, 0, isDefence)
            local dmg = {}
            for _, b in ipairs(batch) do
                dmg[b.id] = b.dmg
            end
            assert.are.same({ [9] = 3, [1] = 1, [2] = 1, [3] = 1 }, dmg)
            batch = explosives.spreadDamage(items, 0, 0, 0, 0, isDefence)
            assert.are.equal(0, #batch)
        end)

        it("stops once the pool is spent", function()
            local items = {
                { id = 1, hitpoints = 6, x = 1, y = 0, z = 0 },
                { id = 2, hitpoints = 6, x = 2, y = 0, z = 0 },
            }
            local always = function()
                return true
            end
            local batch = explosives.spreadDamage(items, 2, 0, 0, 0, always)
            assert.are.same({ { id = 1, dmg = 2 } }, batch)
        end)

        it("handles zero or negative damage safely", function()
            local items = { { id = 1, hitpoints = 5 } }
            local destroyed, damaged = explosives.calculateItemDamage(items, 0)
            assert.are.equal(0, #destroyed)
            assert.are.equal(0, #damaged)
        end)
    end)

    describe("trigger rules", function()
        it("verifies radio detonation requirements", function()
            local phoneData = { bombId = 42 }
            local bombRow = { id = 42, data = { armed = 1 } }
            local bombType = { explosive = { trigger = "RADIO", preset = "MEDIUM" } }

            local ok = explosives.canRadioDetonate(phoneData, bombRow, bombType)
            assert.is_true(ok)

            -- Fails if not armed
            bombRow.data.armed = 0
            local ok2, err2 = explosives.canRadioDetonate(phoneData, bombRow, bombType)
            assert.is_false(ok2)
            assert.are.equal("RADIONOSYNC", err2)

            -- Fails if wrong trigger
            bombRow.data.armed = 1
            bombType.explosive.trigger = "TIMED"
            local ok3, err3 = explosives.canRadioDetonate(phoneData, bombRow, bombType)
            assert.is_false(ok3)
            assert.are.equal("RADIONOSYNC", err3)

            -- Fails if ID mismatch
            bombType.explosive.trigger = "RADIO"
            phoneData.bombId = 99
            local ok4, err4 = explosives.canRadioDetonate(phoneData, bombRow, bombType)
            assert.is_false(ok4)
            assert.are.equal("RADIONOSYNC", err4)
        end)

        it("checks armed trip mine", function()
            local tripType = { explosive = { trigger = "MOTION", preset = "MEDIUM" } }
            assert.is_true(explosives.isArmedTripMine(tripType, { armed = 1 }))
            assert.is_false(explosives.isArmedTripMine(tripType, { armed = 0 }))
            assert.is_false(explosives.isArmedTripMine(tripType, nil))

            local timedType = { explosive = { trigger = "TIMED", preset = "MEDIUM" } }
            assert.is_false(explosives.isArmedTripMine(timedType, { armed = 1 }))
        end)

        it("finds armed trip mine in container items", function()
            local items = {
                { id = 1, uname = "Wrench", data = nil },
                { id = 2, uname = "TntTripMine", data = { armed = 1 } },
            }
            local typeFn = function(uname)
                if uname == "TntTripMine" then
                    return { explosive = { trigger = "MOTION", preset = "MEDIUM" } }
                end
                return { category = "generic" }
            end

            local found = explosives.findArmedTripMine(items, typeFn)
            assert.is_not_nil(found)
            assert.are.equal(2, found.id)

            -- If unarmed
            items[2].data.armed = 0
            assert.is_nil(explosives.findArmedTripMine(items, typeFn))
        end)
    end)
end)
