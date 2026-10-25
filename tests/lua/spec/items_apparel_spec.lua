local apparel = dofile("resources/[scavengesurvive]/items/shared/logic/apparel.lua")
local skins = dofile("resources/[scavengesurvive]/items/shared/logic/skins.lua")
apparel.skins = skins

describe("apparel logic", function()
    describe("slotFor", function()
        it("identifies hats", function()
            assert.are.equal("hat", apparel.slotFor("HelmArmy"))
            assert.are.equal("hat", apparel.slotFor("PoliceCap"))
            assert.are.equal("hat", apparel.slotFor("TopHat"))
        end)

        it("identifies masks", function()
            assert.are.equal("mask", apparel.slotFor("GasMask"))
            assert.are.equal("mask", apparel.slotFor("HockeyMask"))
            assert.are.equal("mask", apparel.slotFor("BandanaBl"))
        end)

        it("identifies armour", function()
            assert.are.equal("armour", apparel.slotFor("Armour"))
            assert.are.equal("armour", apparel.slotFor("Torso"))
        end)

        it("identifies bags", function()
            assert.are.equal("bag", apparel.slotFor("Satchel"))
            assert.are.equal("bag", apparel.slotFor("Backpack"))
            assert.are.equal("bag", apparel.slotFor("ParaBag"))
        end)

        it("identifies holsters", function()
            assert.are.equal("holster", apparel.slotFor("M9Pistol"))
            assert.are.equal("holster", apparel.slotFor("AK47Rifle"))
            assert.are.equal("holster", apparel.slotFor("PumpShotgun"))
            assert.are.equal("holster", apparel.slotFor("Sword"))
        end)

        it("returns nil for non-wearable items", function()
            assert.is_nil(apparel.slotFor("HotDog"))
            assert.is_nil(apparel.slotFor("WoodLog"))
            assert.is_nil(apparel.slotFor(nil))
        end)
    end)

    describe("isWearable", function()
        it("returns true for wearable items", function()
            assert.is_true(apparel.isWearable("HelmArmy"))
            assert.is_true(apparel.isWearable("GasMask"))
            assert.is_true(apparel.isWearable("Armour"))
            assert.is_true(apparel.isWearable("Satchel"))
            assert.is_true(apparel.isWearable("M9Pistol"))
        end)

        it("returns false for non-wearable items", function()
            assert.is_false(apparel.isWearable("HotDog"))
            assert.is_false(apparel.isWearable("WoodLog"))
            assert.is_false(apparel.isWearable("Ammo9mm"))
        end)
    end)

    describe("attachConfig", function()
        it("returns head bone for hat", function()
            local cfg = apparel.attachConfig("hat", "HelmArmy")
            assert.is_not_nil(cfg)
            assert.are.equal(2, cfg.bone)
            assert.are.equal(6, #cfg.offsets)
        end)

        it("returns head bone for mask", function()
            local cfg = apparel.attachConfig("mask", "GasMask")
            assert.is_not_nil(cfg)
            assert.are.equal(2, cfg.bone)
        end)

        it("returns spine bone for armour", function()
            local cfg = apparel.attachConfig("armour", "Armour")
            assert.is_not_nil(cfg)
            assert.are.equal(1, cfg.bone)
        end)

        local rows = {
            HelmArmy = {
                ["60"] = { 0.15, 0, -0.006, 0, 0, 0, 1, 1, 1 },
                ["193"] = { 0.14, 0.01, 0, 0, 0, 0, 1.1, 1, 1 },
            },
            HockeyMask = { ["60"] = { 0.09, 0.04, -0.007, 90, 90, 0, 1, 1, 1 } },
        }
        local function lookup(uname)
            return rows[uname]
        end

        it("uses the wearer's upstream row", function()
            local cfg = apparel.attachConfig("hat", "HelmArmy", 60, lookup)
            assert.are.same({ 0.15, 0, -0.006, 0, 0, 0 }, cfg.offsets)
        end)

        it("falls back to a same-gender skin, or to the default without the skins table", function()
            assert.are.same({ 1.1, 1, 1 }, apparel.attachConfig("hat", "HelmArmy", 90, lookup).scale) -- woman: 193
            assert.are.same({ 0.15, 0, -0.006, 0, 0, 0 }, apparel.attachConfig("hat", "HelmArmy", 217, lookup).offsets)
            apparel.skins = nil
            assert.are.same(
                { 0.152, 0.0, -0.006, 0.0, 0.0, 0.0 },
                apparel.attachConfig("hat", "HelmArmy", 217, lookup).offsets
            )
            apparel.skins = skins
        end)

        it("gives a bag the wearer's row, else a similar skin's, or nothing without rows", function()
            local bags = {
                Backpack = { ["60"] = { -0.15, -0.07, -0.02, 0, 0, 0, 1, 1.2, 1.3 }, ["93"] = { -0.13, 0, 0 } },
            }
            local function bagLookup(uname)
                return bags[uname]
            end
            assert.are.same({ 1, 1.2, 1.3 }, apparel.bagConfig("Backpack", 60, bagLookup).scale)
            assert.are.equal(-0.13, apparel.bagConfig("Backpack", 211, bagLookup).offsets[1]) -- woman: 93
            assert.are.equal(-0.15, apparel.bagConfig("Backpack", 217, bagLookup).offsets[1]) -- man: 60
            assert.are.equal(1, apparel.bagConfig("Backpack", 217, bagLookup).bone)
            assert.is_nil(apparel.bagConfig("Satchel", 60, bagLookup))
        end)

        it("borrows rows for wearables upstream never tuned, with their own rotation, shift and scale", function()
            local beanie = apparel.attachConfig("hat", "Beanie", 60, lookup)
            assert.are.same({ 0.15, 0, -0.006, 0, 0, 0 }, beanie.offsets)
            local devil = apparel.attachConfig("mask", "DevilMask", 60, lookup)
            assert.are.equal(180, devil.offsets[4])
            assert.is_true(math.abs(devil.offsets[1] - 0.03) < 1e-9)
            assert.are.same({ 0.45, 0.45, 0.45 }, devil.scale)
        end)

        it("nudges bandanas forward on skins whose nose pokes through, leaving other skins alone", function()
            local bandana = {
                BandanaBl = {
                    ["250"] = { 0.08, 0.03, -0.002, 90, 90, 0, 1, 1, 1 },
                    ["60"] = { 0.08, 0.03, -0.002, 90, 90, 0, 1, 1, 1 },
                },
            }
            local function bandanaLookup(uname)
                return bandana[uname]
            end
            local nudged = apparel.attachConfig("mask", "BandanaBl", 250, bandanaLookup).offsets
            assert.is_true(math.abs(nudged[2] - (0.03 + 0.012)) < 1e-9)
            assert.are.equal(0.08, nudged[1])
            assert.are.equal(-0.002, nudged[3])
            local plain = apparel.attachConfig("mask", "BandanaBl", 60, bandanaLookup)
            assert.are.same({ 0.08, 0.03, -0.002, 90, 90, 0 }, plain.offsets)
        end)

        it("returns thigh bone for handgun holster", function()
            local cfg = apparel.attachConfig("holster", "M9Pistol")
            assert.is_not_nil(cfg)
            assert.are.equal(8, cfg.bone)
        end)

        it("returns spine bone for rifle holster", function()
            local cfg = apparel.attachConfig("holster", "AK47Rifle")
            assert.is_not_nil(cfg)
            assert.are.equal(1, cfg.bone)
        end)
    end)
end)

describe("ped skin table", function()
    it("covers every human ped model, with the right gender for spawn and duty skins", function()
        local all = skins.all()
        assert.are.equal(310, #all)
        assert.is_false(skins.isValid(74))
        assert.is_false(skins.isValid(149))
        assert.is_false(skins.isValid(208))
        assert.is_true(skins.isValid(0))
        assert.is_true(skins.isValid(312))
        for _, s in ipairs({ 60, 170, 250, 188, 206, 50, 254, 217 }) do
            assert.is_false(skins.isFemale(s), s .. " is a man")
        end
        for _, s in ipairs({ 192, 93, 233, 193, 90, 191, 131, 211 }) do
            assert.is_true(skins.isFemale(s), s .. " is a woman")
        end
    end)

    it("lists the wearer first and never crosses gender", function()
        for _, id in ipairs(skins.all()) do
            local c = skins.candidates(id)
            assert.are.equal(id, c[1])
            assert.is_true(#c > 5, id .. " has donors")
            for i = 2, #c do
                assert.are.equal(skins.isFemale(id), skins.isFemale(c[i]), id .. " borrows across gender from " .. c[i])
            end
        end
    end)
end)

describe("apparel on spawnable skins", function()
    local items = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
    -- upstream spawn.pwn's skins (the port's spawn pool before #76 widened it to every clothes type)
    local UPSTREAM_SPAWN = { 60, 170, 250, 188, 206, 50, 254, 192, 93, 233, 193, 90, 191, 131 }
    local function lookup(uname)
        local t = items.byUname[uname]
        return t and t.wearOffsets
    end

    local function bagLookup(uname)
        local t = items.byUname[uname]
        return t and t.categoryData and t.categoryData.bag_offsets
    end

    it("gives every hat, mask and armour a row of upstream's spawn skins' own", function()
        apparel.skins = nil -- no donors: the row must be the skin's own (90 excepted, which borrows 193)
        local defaults = {}
        for _, slot in ipairs({ "hat", "mask", "armour" }) do
            defaults[slot] = apparel.attachConfig(slot, "none", nil, nil)
        end
        local pool = UPSTREAM_SPAWN
        for _, uname in ipairs(items.order) do
            local slot = apparel.slotFor(uname)
            if defaults[slot] then
                for _, skin in ipairs(pool) do
                    if skin ~= 90 then
                        local cfg = apparel.attachConfig(slot, uname, skin, lookup)
                        assert(cfg ~= defaults[slot], uname .. " has no row for skin " .. skin)
                    end
                end
            end
        end
        apparel.skins = skins
    end)

    it("gives every hat, mask, armour and bag a row on every human ped model", function()
        local defaults = {}
        for _, slot in ipairs({ "hat", "mask", "armour" }) do
            defaults[slot] = apparel.attachConfig(slot, "none", nil, nil)
        end
        for _, uname in ipairs(items.order) do
            local slot = apparel.slotFor(uname)
            for _, skin in ipairs(skins.all()) do
                if defaults[slot] then
                    local cfg = apparel.attachConfig(slot, uname, skin, lookup)
                    assert(cfg ~= defaults[slot], uname .. " has no row for skin " .. skin)
                elseif slot == "bag" then
                    local cfg = apparel.bagConfig(uname, skin, bagLookup)
                    assert(cfg and cfg.scale[1] > 0, uname .. " has no row for skin " .. skin)
                end
            end
        end
    end)
end)

describe("cut hats", function()
    local items = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
    local CUT = {
        "SheriffHat",
        "FireHelmet",
        "GardenerHat",
        "PilotCap",
        "MotoHelmet",
        "RanchHat",
        "GolfCap",
        "BurgerHat",
        "BucketHat",
    }

    it("are hats, and only they are cut hats", function()
        for _, uname in ipairs(CUT) do
            assert.are.equal("hat", apparel.slotFor(uname))
            assert.is_true(apparel.isCutHat(uname))
            assert.is_true(apparel.isWearable(uname))
        end
        assert.is_false(apparel.isCutHat("HelmArmy"))
        assert.is_false(apparel.isCutHat(nil))
    end)

    it("sit at zero offset on the head bone of every skin, with or without rows", function()
        local none = function()
            return nil
        end
        for _, uname in ipairs(CUT) do
            for _, skin in ipairs({ 0, 60, 283, 250 }) do
                local cfg = apparel.attachConfig("hat", uname, skin, none)
                assert.are.equal(2, cfg.bone)
                assert.are.same({ 0, 0, 0, 0, 0, 0 }, cfg.offsets)
                assert.are.same({ 1, 1, 1 }, cfg.scale)
            end
        end
    end)

    it("are in the generated item types with the port's model ids", function()
        for i, uname in ipairs(CUT) do
            local t = items.byUname[uname]
            assert.is_not_nil(t, uname)
            assert.are.equal(20000 + i, t.model)
            assert.are.equal("generic", t.category)
        end
        assert.are.equal(20001, items.byUname.SheriffHat.model)
    end)
end)
