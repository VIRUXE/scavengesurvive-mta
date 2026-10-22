local wound = dofile("resources/[scavengesurvive]/weapons/shared/logic/wound.lua")
local function near(expected, actual) assert.is_true(math.abs(expected - actual) < 1e-9, tostring(expected) .. " ~= " .. tostring(actual)) end

describe("weapons wound", function()
    it("maps GTA weapon ids to ranges with a 35 m default", function()
        assert.equals(35, wound.range(22)); assert.equals(35, wound.range(24))
        assert.equals(40, wound.range(25)); assert.equals(40, wound.range(27))
        assert.equals(45, wound.range(29)); assert.equals(70, wound.range(30)); assert.equals(90, wound.range(31))
        assert.equals(100, wound.range(33)); assert.equals(320, wound.range(34)); assert.equals(75, wound.range(38))
        assert.equals(35, wound.range(99))
        assert.equals(2, wound.range(0)); assert.equals(2, wound.range(4)); assert.equals(2, wound.range(15)); assert.equals(35, wound.range(16))
        assert.is_true(wound.isMeleeWeapon(0)); assert.is_true(wound.isMeleeWeapon(4)); assert.is_false(wound.isMeleeWeapon(22))
        assert.is_true(wound.inRange(22, 40)); assert.is_false(wound.inRange(22, 40.1))
        assert.is_true(wound.inRange(34, 325)); assert.is_false(wound.inRange(0, 7.5))
    end)
    it("rate-limits the Desert Eagle harder than other weapons", function()
        assert.equals(790, wound.cooldown(24)); assert.equals(100, wound.cooldown(22)); assert.equals(100, wound.cooldown(0))
    end)
    it("implements the upstream firearm bleed formula", function()
        local v = 330 - 10 ^ (1 - 330 / 11300)
        near(0.25 * v / 1000 * 1.0, wound.firearm(330, 10, 0.25, 1.0))
        near(0.25 * 330 / 1000, wound.firearm(330, 0, 0.25, 1.0))
        local v2 = 900 - 150 ^ (1 - 900 / 11300)
        near(0.19 * v2 / 1000 * 2.0, wound.firearm(900, 150, 0.19, 2.0))
        assert.equals(0, wound.firearm(10, 1e6, 0.25, 1.0)) -- velocity clamped at 0
    end)
    it("applies body-part knock multipliers and the MVP headshot rule", function()
        assert.equals(1.0, wound.bodypartKnock(3)); assert.equals(1.2, wound.bodypartKnock(4))
        assert.equals(0.9, wound.bodypartKnock(5)); assert.equals(0.9, wound.bodypartKnock(6))
        assert.equals(0.8, wound.bodypartKnock(7)); assert.equals(0.8, wound.bodypartKnock(8))
        assert.equals(9.9, wound.bodypartKnock(9)); assert.equals(1.0, wound.bodypartKnock(42))
        near(0.2, wound.bodypartBleed(0.1, 9)); near(0.1, wound.bodypartBleed(0.1, 3))
        near(8.25, wound.hpLoss(0.0825))
    end)
    it("computes environmental damage as hpLoss, bleedAdd", function()
        local hp, bleed = wound.environmental(54, 50)
        near(math.min(50, 30) * 0.5, hp); near(50 * 2.5 * 0.00024, bleed)
        hp, bleed = wound.environmental(53, 20); near(10, hp); near(0, bleed)
        hp, bleed = wound.environmental(53, 4); near(4, hp)
        hp, bleed = wound.environmental(37, 40); near(40 * 0.1, hp); near(0, bleed)
        hp, bleed = wound.environmental(51, 80); near(0.5 * (80 / 80), bleed); near(0.5 * 100, hp)
        hp, bleed = wound.environmental(49, 100); near(0.04 * (100 * 0.02), bleed); near(0.04 * (100 * 0.02) * 100, hp)
        hp, bleed = wound.environmental(50, 50); near(0.04 * (50 * 0.02), bleed); near(0.04 * (50 * 0.02) * 100, hp)
        hp, bleed = wound.environmental(22, 50); near(20, hp); near(0, bleed)
        hp, bleed = wound.environmental(22, 5); near(5, hp)
    end)
    it("names causes of death", function()
        assert.equals("fall", wound.cause(54)); assert.equals("drowned", wound.cause(53)); assert.equals("burned", wound.cause(37))
        assert.equals("explosion", wound.cause(51)); assert.equals("vehicle", wound.cause(49)); assert.equals("vehicle", wound.cause(50))
        assert.equals("killed", wound.cause(22))
        assert.is_true(wound.isEnvironmental(51)); assert.is_true(wound.isEnvironmental(49)); assert.is_false(wound.isEnvironmental(22))
    end)
    it("computes upstream firearm knockout multipliers, knockout chance, and duration", function()
        local v = wound.firearmVelocity(330, 10)
        near((v / 50.0) * 1.5, wound.firearmKnock(330, 10, 1.5))

        -- damage.pwn:141: knockmult * (((woundcount + 1) * 0.2) * ((totalbleedrate * 50) + 1))
        near(9.9 * 2.0 * ((2 * 0.2) * ((0.1 * 50) + 1)), wound.knockoutChance(2.0, 9, 1, 0.1))

        -- damage.pwn:148: floatround((knockmult * 0.2) * ((woundcount + 1) * ((totalbleedrate * 10) + 1) * (110 - hp) + (200 * (110 - hp))))
        local expected = math.floor((9.9 * 2.0 * 0.2) * (2 * ((0.1 * 10) + 1) * 30 + (200 * 30)) + 0.5)
        assert.equals(expected, wound.knockoutDuration(2.0, 9, 1, 0.1, 80))
        assert.equals(0, wound.knockoutDuration(0.1, 3, 0, 0, 108)) -- <= 1500ms threshold ignored
        assert.equals(120000, wound.knockoutDuration(50.0, 9, 5, 1.0, 10)) -- capped at 120000ms
    end)

    it("matches SA-MP init.pwn calibre bleed rates, firearm muzzle velocities, and ammo multipliers (#28)", function()
        local items = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
        -- All 11 calibres from init.pwn:1038-1048
        local expectedCalibres = {
            ["9mm"] = 0.25,
            ["50cae"] = 0.73,
            ["12g"] = 0.31,
            ["556"] = 0.19,
            ["357"] = 0.36,
            ["762"] = 0.32,
            rpg = 0.0,
            fuel = 0.0,
            film = 0.0,
            ["50bmg"] = 0.63,
            ["308"] = 0.43,
        }
        for cal, bleed in pairs(expectedCalibres) do
            near(bleed, items.calibres[cal])
        end

        -- Representative firearms from init.pwn:1136-1163
        local expectedFirearms = {
            M9Pistol = { base = 22, cal = "9mm", vel = 330.0, mag = 10, res = 1 },
            M9PistolSD = { base = 23, cal = "9mm", vel = 295.0, mag = 10, res = 1 },
            DesertEagle = { base = 24, cal = "357", vel = 420.0, mag = 7, res = 2 },
            PumpShotgun = { base = 25, cal = "12g", vel = 475.0, mag = 6, res = 1 },
            Sawnoff = { base = 26, cal = "12g", vel = 265.0, mag = 2, res = 6 },
            Spas12 = { base = 27, cal = "12g", vel = 480.0, mag = 6, res = 1 },
            Mac10 = { base = 28, cal = "9mm", vel = 376.0, mag = 32, res = 1 },
            MP5 = { base = 29, cal = "9mm", vel = 400.0, mag = 30, res = 1 },
            WASR3Rifle = { base = 30, cal = "556", vel = 943.0, mag = 30, res = 1 },
            M16Rifle = { base = 31, cal = "556", vel = 948.0, mag = 30, res = 1 },
            Tec9 = { base = 32, cal = "9mm", vel = 360.0, mag = 36, res = 1 },
            SemiAutoRifle = { base = 33, cal = "357", vel = 829.0, mag = 5, res = 1 },
            SniperRifle = { base = 34, cal = "357", vel = 864.0, mag = 5, res = 1 },
            AK47Rifle = { base = 30, cal = "762", vel = 715.0, mag = 30, res = 1 },
            M77RMRifle = { base = 33, cal = "357", vel = 823.0, mag = 1, res = 9 },
            DogsBreath = { base = 24, cal = "50bmg", vel = 888.8, mag = 1, res = 9 },
            Model70Rifle = { base = 34, cal = "308", vel = 860.6, mag = 1, res = 9 },
            LenKnocksRifle = { base = 34, cal = "50bmg", vel = 938.5, mag = 1, res = 4 },
        }
        for uname, exp in pairs(expectedFirearms) do
            local cd = items.byUname[uname].categoryData
            assert.equals(exp.base, cd.baseWeapon)
            assert.equals(exp.cal, cd.calibre)
            near(exp.vel, cd.muzzleVelocity)
            assert.equals(exp.mag, cd.magSize)
            assert.equals(exp.res, cd.maxReserveMags)
        end

        -- All ammo multipliers from init.pwn:1198-1213
        local expectedAmmo = {
            Ammo9mm = { cal = "9mm", bld = 1.0, ko = 1.0, pen = 0.2, rounds = 20 },
            Ammo50 = { cal = "50cae", bld = 1.0, ko = 1.5, pen = 0.9, rounds = 28 },
            AmmoBuck = { cal = "12g", bld = 1.1, ko = 1.8, pen = 0.5, rounds = 24 },
            Ammo556 = { cal = "556", bld = 1.1, ko = 1.2, pen = 0.8, rounds = 30 },
            Ammo357 = { cal = "357", bld = 1.2, ko = 1.1, pen = 0.9, rounds = 10 },
            AmmoRocket = { cal = "rpg", bld = 1.0, ko = 1.0, pen = 1.0, rounds = 1 },
            Ammo9mmFMJ = { cal = "9mm", bld = 1.2, ko = 0.5, pen = 0.8, rounds = 20 },
            AmmoFlechette = { cal = "12g", bld = 1.6, ko = 0.6, pen = 0.2, rounds = 8 },
            AmmoHomeBuck = { cal = "12g", bld = 1.6, ko = 0.4, pen = 0.3, rounds = 14 },
            Ammo556Tracer = { cal = "556", bld = 0.9, ko = 1.1, pen = 0.5, rounds = 30 },
            Ammo556HP = { cal = "556", bld = 1.3, ko = 1.6, pen = 0.4, rounds = 30 },
            Ammo357Tracer = { cal = "357", bld = 1.2, ko = 1.1, pen = 0.6, rounds = 10 },
            Ammo762 = { cal = "762", bld = 1.3, ko = 1.1, pen = 0.9, rounds = 30 },
            Ammo50BMG = { cal = "50bmg", bld = 1.8, ko = 1.8, pen = 1.0, rounds = 16 },
            Ammo308 = { cal = "308", bld = 1.2, ko = 1.1, pen = 0.8, rounds = 10 },
        }
        for uname, exp in pairs(expectedAmmo) do
            local cd = items.byUname[uname].categoryData
            assert.equals(exp.cal, cd.calibre)
            near(exp.bld, cd.bleedMult)
            near(exp.ko, cd.koMult)
            near(exp.pen, cd.penetration)
            assert.equals(exp.rounds, cd.rounds)
        end
    end)
end)
