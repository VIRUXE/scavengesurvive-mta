local Ammo = dofile("resources/[scavengesurvive]/items/shared/logic/ammo.lua")

describe("items ammo logic", function()
    local m9 = {
        uname = "M9Pistol",
        name = "M9 Pistol",
        category = "weapon",
        categoryData = { baseWeapon = 22, calibre = "9mm", magSize = 17, maxReserveMags = 6 },
    }
    local sawnoff = {
        uname = "Sawnoff",
        name = "Sawn-off Shotgun",
        category = "weapon",
        categoryData = { baseWeapon = 26, calibre = "12g", magSize = 2, maxReserveMags = 0 },
    }
    local flamer = {
        uname = "Flamer",
        name = "Flamethrower",
        category = "weapon",
        categoryData = { baseWeapon = 37, calibre = "fuel", liquid = true, magSize = 100, maxReserveMags = 0 },
    }
    local knife = {
        uname = "Knife",
        name = "Knife",
        category = "weapon",
        categoryData = { baseWeapon = 4, calibre = nil, magSize = 0, maxReserveMags = 0, melee = true },
    }
    local ammo9 = {
        uname = "Ammo9mm",
        name = "9mm Rounds",
        category = "ammo",
        categoryData = { name = "FMJ", calibre = "9mm", rounds = 200 },
    }
    local ammo9fmj = {
        uname = "Ammo9mmFMJ",
        name = "9mm FMJ Rounds",
        category = "ammo",
        categoryData = { name = "AP", calibre = "9mm", rounds = 200 },
    }
    local ammo556 = {
        uname = "Ammo556",
        name = "5.56 Rounds",
        category = "ammo",
        categoryData = { name = "FMJ", calibre = "556", rounds = 200 },
    }

    it("identifies calibre weapons and ammo tins", function()
        assert.is_true(Ammo.isCalibreWeapon(m9))
        assert.is_false(Ammo.isCalibreWeapon(flamer))
        assert.is_false(Ammo.isCalibreWeapon(knife))
        assert.is_true(Ammo.isAmmoItem(ammo9))
        assert.is_false(Ammo.isAmmoItem(m9))
    end)

    it("resolves weapon state with backwards-compatible defaults and explicit zero mag", function()
        assert.same({ mag = 17, reserve = 0, ammoItem = "Ammo9mm" }, Ammo.weaponState(m9, nil, "Ammo9mm"))
        assert.same({ mag = 17, reserve = 0, ammoItem = "Ammo9mm" }, Ammo.weaponState(m9, {}, "Ammo9mm"))
        assert.same({ mag = 0, reserve = 0, ammoItem = nil }, Ammo.weaponState(m9, { mag = 0, reserve = 0 }, "Ammo9mm"))
        assert.same(
            { mag = 5, reserve = 20, ammoItem = "Ammo9mmFMJ" },
            Ammo.weaponState(m9, { mag = 5, reserve = 20, ammoItem = "Ammo9mmFMJ" }, "Ammo9mm")
        )
    end)

    it("reloads from reserve and fires with auto-reload on empty magazine", function()
        local ok, state, moved = Ammo.reload(m9, { mag = 5, reserve = 20, ammoItem = "Ammo9mm" }, "Ammo9mm")
        assert.is_true(ok)
        assert.equals(12, moved)
        assert.same({ mag = 17, reserve = 8, ammoItem = "Ammo9mm" }, state)

        local fired, afterFire, autoReloaded = Ammo.fire(m9, { mag = 1, reserve = 5, ammoItem = "Ammo9mm" }, "Ammo9mm")
        assert.is_true(fired)
        assert.is_true(autoReloaded)
        assert.same({ mag = 5, reserve = 0, ammoItem = "Ammo9mm" }, afterFire)

        local firedLast, emptyState, auto2 = Ammo.fire(m9, { mag = 1, reserve = 0, ammoItem = "Ammo9mm" }, "Ammo9mm")
        assert.is_true(firedLast)
        assert.is_false(auto2)
        assert.same({ mag = 0, reserve = 0, ammoItem = nil }, emptyState)
    end)

    it("unloads mag and reserve into an ammo tin specification", function()
        local ok, unloadedState, spawned = Ammo.unload(m9, { mag = 10, reserve = 15, ammoItem = "Ammo9mmFMJ" }, "Ammo9mm")
        assert.is_true(ok)
        assert.same({ mag = 0, reserve = 0, ammoItem = nil }, unloadedState)
        assert.same({ uname = "Ammo9mmFMJ", data = { rounds = 25 } }, spawned)

        local ok2, code = Ammo.unload(m9, { mag = 0, reserve = 0 }, "Ammo9mm")
        assert.is_false(ok2)
        assert.equals("WEAPAUNLOAD", code)
    end)

    it("transfers rounds between ammo tins and weapons with calibre/type checks", function()
        -- Wrong calibre rejected
        local okCal, codeCal = Ammo.transfer(ammo556, { rounds = 50 }, m9, { mag = 0, reserve = 0 }, "Ammo9mm")
        assert.is_false(okCal)
        assert.equals("AMWRONGCALI", codeCal)

        -- Different ammo type in loaded weapon rejected
        local okDiff, codeDiff =
            Ammo.transfer(ammo9fmj, { rounds = 50 }, m9, { mag = 5, reserve = 0, ammoItem = "Ammo9mm" }, "Ammo9mm")
        assert.is_false(okDiff)
        assert.equals("AMDIFFATYPE", codeDiff)

        -- Ammo tin -> unloaded weapon fills mag then reserve
        local okLoad, codeLoad, nextTin, nextWep, moved =
            Ammo.transfer(ammo9, { rounds = 50 }, m9, { mag = 0, reserve = 0 }, "Ammo9mm")
        assert.is_true(okLoad)
        assert.equals("AMTRANS", codeLoad)
        assert.equals(50, moved)
        assert.same({ rounds = 0 }, nextTin)
        assert.same({ mag = 17, reserve = 33, ammoItem = "Ammo9mm" }, nextWep)

        -- Mixing different ammo tins rejected
        local okMix, codeMix = Ammo.transfer(ammo9, { rounds = 10 }, ammo9fmj, { rounds = 10 })
        assert.is_false(okMix)
        assert.equals("AMMIXINTINS", codeMix)
    end)

    it("routes held/world interactions and flags depleted ammo tins for deletion", function()
        local ok, code, nextHeld, nextWorld, moved, delWorld, delHeld = Ammo.interactTransfer(
            m9,
            { mag = 0, reserve = 0 },
            ammo9,
            { rounds = 10 },
            "Ammo9mm"
        )
        assert.is_true(ok)
        assert.equals("AMTRANS", code)
        assert.equals(10, moved)
        assert.is_true(delWorld)
        assert.is_false(delHeld)
        assert.same({ mag = 10, reserve = 0, ammoItem = "Ammo9mm" }, nextHeld)
        assert.same({ rounds = 0 }, nextWorld)
    end)

    it("rolls civilian vs military loot ammo and formats item display names", function()
        local civ = Ammo.rollLootData(m9, "world_civilian", { "Ammo9mm", "Ammo9mmFMJ" }, function(a, b)
            if a == 0 and b == 16 then
                return 6
            end
            return 2
        end)
        assert.same({ mag = 6, reserve = 0, ammoItem = "Ammo9mmFMJ" }, civ)

        local milFull = Ammo.rollLootData(m9, "world_military", { "Ammo9mm" }, function(a, b)
            if a == 0 and b == 99 then
                return 75
            end
            return 1
        end)
        assert.same({ mag = 17, reserve = 0, ammoItem = "Ammo9mm" }, milFull)

        local defs = { Ammo9mm = ammo9, Ammo9mmFMJ = ammo9fmj }
        local calNames = { ["9mm"] = "9mm", ["12g"] = "12 Gauge" }
        assert.equals(
            "M9 Pistol (6/0, 9mm, AP)",
            Ammo.displayName(m9, civ, function(u)
                return defs[u]
            end, function(c)
                return calNames[c]
            end, "Ammo9mm")
        )
        assert.equals(
            "Sawn-off Shotgun (0/0, 12 Gauge, Unloaded)",
            Ammo.displayName(sawnoff, { mag = 0, reserve = 0 }, function(u)
                return defs[u]
            end, function(c)
                return calNames[c]
            end, nil)
        )
        assert.equals(
            "9mm Rounds (42, 9mm, FMJ)",
            Ammo.displayName(ammo9, { rounds = 42 }, nil, function(c)
                return calNames[c]
            end)
        )
        assert.equals('{"rounds":42}', Ammo.encodeData({ rounds = 42 }))
        assert.equals(
            '{"mag":6,"reserve":0,"ammoItem":"Ammo9mmFMJ"}',
            Ammo.encodeData({ mag = 6, reserve = 0, ammoItem = "Ammo9mmFMJ" })
        )
        assert.equals('{"mag":0,"reserve":0}', Ammo.encodeData({ mag = 0, reserve = 0 }))
    end)
end)
