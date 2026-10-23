local apparel = dofile("resources/[scavengesurvive]/items/shared/logic/apparel.lua")

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

        it("falls back to a similar skin, then to the default", function()
            assert.are.same({ 1.1, 1, 1 }, apparel.attachConfig("hat", "HelmArmy", 90, lookup).scale)
            assert.are.same(
                { 0.152, 0.0, -0.006, 0.0, 0.0, 0.0 },
                apparel.attachConfig("hat", "HelmArmy", 217, lookup).offsets
            )
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

describe("apparel on spawnable skins", function()
    local items = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")
    local sp = dofile("resources/[scavengesurvive]/character/shared/logic/spawnpoints.lua")
    local function lookup(uname)
        local t = items.byUname[uname]
        return t and t.wearOffsets
    end

    it("gives every hat, mask and armour a tuned row on every spawn skin", function()
        local defaults = {}
        for _, slot in ipairs({ "hat", "mask", "armour" }) do
            defaults[slot] = apparel.attachConfig(slot, "none", nil, nil)
        end
        local skins = {}
        for _, s in ipairs(sp.SKINS_MALE) do
            skins[#skins + 1] = s
        end
        for _, s in ipairs(sp.SKINS_FEMALE) do
            skins[#skins + 1] = s
        end
        for _, uname in ipairs(items.order) do
            local slot = apparel.slotFor(uname)
            if defaults[slot] then
                for _, skin in ipairs(skins) do
                    local cfg = apparel.attachConfig(slot, uname, skin, lookup)
                    assert(cfg ~= defaults[slot], uname .. " has no row for skin " .. skin)
                end
            end
        end
    end)
end)
