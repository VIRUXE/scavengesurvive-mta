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
    describe("damage no held item is behind (upstream damage-world, damage-vehicle, damage-explosive.pwn)", function()
        local function seq(...)
            local v, i = { ... }, 0
            return function()
                i = i + 1
                return assert(v[i], "rnd drawn too often")
            end
        end
        it("scales a velocity vector like upstream's km/h readout", function()
            near(75, wound.velocity(0.3, 0.4, 0)); near(0, wound.velocity(false))
        end)
        it("a fall over 10 hp wounds a leg with chance amount x 2.5 %, knockmult x 0.9", function()
            assert.is_nil(wound.nonFirearm(54, 10, nil, seq()))
            assert.is_nil(wound.nonFirearm(54, 20, nil, seq(0.5))) -- 50 >= 50: no wound
            local w = wound.nonFirearm(54, 20, nil, seq(0.49, 0.2))
            near(50 * 0.00024, w.bleed); near(50 * 0.00024 * 100, w.hp); near(45, w.knockMult)
            assert.equals(7, w.bodypart); assert.equals("fall", w.cause); assert.is_nil(w.knockoutMs)
            assert.equals(8, wound.nonFirearm(54, 40, nil, seq(0.99, 0.5)).bodypart)
        end)
        it("drowning knocks out for 1.5 to 3 s and keeps the capped hp loss", function()
            local w = wound.nonFirearm(53, 20, nil, seq(0.5))
            assert.equals(2250, w.knockoutMs); near(10, w.hp); near(0, w.bleed); assert.equals("drowned", w.cause)
            near(4, wound.nonFirearm(53, 4, nil, seq(0)).hp)
            assert.equals(1500, wound.nonFirearm(53, 4, nil, seq(0)).knockoutMs)
        end)
        it("fire takes a tenth of the loss as hp", function()
            local w = wound.nonFirearm(37, 40, nil, seq())
            near(4, w.hp); near(0, w.bleed); assert.equals("burned", w.cause)
        end)
        it("a ram bleeds with the driver's speed and knocks out past 55 km/h", function()
            -- 100 km/h, bleed x2, knock x1.5: rnd 0.6 -> 60 > 55 knocks out (1000 + 5000) x 1.5; coins 0.5, 0.7 -> left leg
            local w = wound.nonFirearm(49, 0, { velocity = 100, bleedMult = 2.0, knockMult = 1.5 }, seq(0.6, 0.5, 0.7))
            near(0.04 * (100 * 0.02) * 2.0, w.bleed); near(w.bleed * 100, w.hp); near(1.0, w.knockMult)
            assert.equals(9000, w.knockoutMs); assert.equals(7, w.bodypart); assert.equals("vehicle", w.cause)
            w = wound.nonFirearm(49, 0, { velocity = 100 }, seq(0.5, 0.2)) -- 50 < 55: no knockout, torso
            assert.equals(0, w.knockoutMs); assert.equals(3, w.bodypart); near(0.08, w.bleed)
            w = wound.nonFirearm(50, 0, { velocity = 50 }, seq(0.2)) -- under 55 km/h: never a knockout
            assert.equals(0, w.knockoutMs); near(0.04, w.bleed)
            near(0, wound.nonFirearm(49, 30, {}, seq(0.2)).bleed) -- no speed known: no wound to apply
        end)
        it("an explosion is a burn wound with knockmult 150 + amount", function()
            local w = wound.nonFirearm(51, 80, nil, seq(0.7, 0.3)) -- coins: not the torso, the right leg
            near(0.5, w.bleed); near(50, w.hp); near(230, w.knockMult); assert.equals(8, w.bodypart)
            assert.equals("explosion", w.cause)
        end)
        it("an explosion MTA reports as a grenade or rocket wounds the same way", function()
            for _, id in ipairs({ 16, 19 }) do
                local w = wound.nonFirearm(id, 32, nil, seq(0.2))
                near(0.2, w.bleed); near(182, w.knockMult); assert.equals("explosion", w.cause)
            end
            assert.equals("explosion", wound.killCause(19))
        end)
        it("anything else takes the loss as hp, capped at 20", function()
            local w = wound.nonFirearm(22, 50, nil, seq())
            near(20, w.hp); near(0, w.bleed); assert.equals("killed", w.cause)
            near(5, wound.nonFirearm(22, 5, nil, seq()).hp)
        end)
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
    describe("the shield (#137)", function()
        -- victim at the origin facing north (0); attackers north (0, 10), south (0, -10), east (10, 0)
        it("in hand stops shots from the front only", function()
            assert.is_true(wound.shieldBlocks("held", 3, false, 0, 0, 0, 0, 10))
            assert.is_true(wound.shieldBlocks("held", 3, false, 0, 0, 0, 5, 10)) -- 26 degrees off
            assert.is_false(wound.shieldBlocks("held", 3, false, 0, 0, 0, 10, 0)) -- from the side
            assert.is_false(wound.shieldBlocks("held", 3, false, 0, 0, 0, 0, -10)) -- from behind
            assert.is_true(wound.shieldBlocks("held", 3, false, 90, 0, 0, -10, 0)) -- facing west, shot from the west
        end)
        it("on the back stops shots from behind only", function()
            assert.is_true(wound.shieldBlocks("holster", 3, false, 0, 0, 0, 0, -10))
            assert.is_false(wound.shieldBlocks("holster", 3, false, 0, 0, 0, 0, 10))
            assert.is_false(wound.shieldBlocks("holster", 3, false, 0, 0, 0, 10, -5)) -- 63 degrees off behind
        end)
        it("never covers the head, and the legs only from a crouching shooter", function()
            assert.is_false(wound.shieldBlocks("held", 9, false, 0, 0, 0, 0, 10))
            assert.is_false(wound.shieldBlocks("held", 7, false, 0, 0, 0, 0, 10))
            assert.is_true(wound.shieldBlocks("held", 7, true, 0, 0, 0, 0, 10))
            assert.is_true(wound.shieldBlocks("held", 8, true, 0, 0, 0, 0, 10))
            assert.is_false(wound.shieldBlocks(nil, 3, false, 0, 0, 0, 0, 10))
        end)
    end)
end)
