local clothes = dofile("resources/[scavengesurvive]/items/shared/logic/clothes.lua")
local skins = dofile("resources/[scavengesurvive]/items/shared/logic/skins.lua")

describe("clothes", function()
    it("carries upstream's 29 DefineClothesType rows with genders matching the skin table", function()
        assert.equals(29, #clothes.TYPES)
        for _, row in ipairs(clothes.TYPES) do
            assert.equals(row[3] == clothes.FEMALE, skins.isFemale(row[1]), "skin " .. row[1])
        end
    end)

    it("labels a skin by gender and name, and an unknown skin as plain clothes", function()
        assert.equals("Male Civilian", clothes.label(60))
        assert.equals("Female Business", clothes.label(141))
        assert.equals("Male S.W.A.T.", clothes.label(285))
        assert.equals("Female Clothes", clothes.label(9, true))
        assert.equals("Male Clothes", clothes.label(7))
    end)

    it("rolls upstream's rule: a type passes its chance, one pass is picked", function()
        local always = function()
            return 0
        end
        local never = function()
            return 0.999
        end
        local first = function()
            return 1
        end
        assert.equals(60, clothes.roll(always, first))
        assert.equals(192, clothes.roll(always, first, clothes.FEMALE))
        -- only the 1.0 rows pass a 0.999 draw? none do (rand < chance), so the gender fallback is used
        assert.equals(60, clothes.roll(never, first, clothes.MALE))
        assert.equals(192, clothes.roll(never, first, clothes.FEMALE))
    end)

    it("keeps a spawn roll inside the gender", function()
        math.randomseed(7)
        for _ = 1, 200 do
            local m = clothes.roll(math.random, math.random, clothes.MALE)
            local f = clothes.roll(math.random, math.random, clothes.FEMALE)
            assert.equals(clothes.MALE, clothes.gender(m))
            assert.equals(clothes.FEMALE, clothes.gender(f))
        end
    end)

    it("gives an unrolled item the same type every time, and a stored skin wins", function()
        for id = 1, 50 do
            local a, b = clothes.skinFor(id, nil), clothes.skinFor(id, {})
            assert.equals(a, b)
            assert.is_true(clothes.isClothesSkin(a))
        end
        assert.equals(287, clothes.skinFor(3, { skin = 287 }))
        assert.equals(7, clothes.skinFor(3, { skin = "7" }))
    end)

    it("spreads unrolled items over several types with civilians the most common", function()
        local counts, civ = {}, 0
        for id = 1, 2000 do
            local s = clothes.skinFor(id)
            counts[s] = (counts[s] or 0) + 1
        end
        local kinds = 0
        for s, n in pairs(counts) do
            kinds = kinds + 1
            if clothes.label(s):find("Civilian") then
                civ = civ + n
            end
        end
        assert.is_true(kinds >= 20)
        assert.is_true(civ > 1200)
    end)

    it("seeds a generator whose draws stay in [0, 1) and [1, n]", function()
        local rand, randInt = clothes.seeded(123456789)
        for _ = 1, 500 do
            local r = rand()
            assert.is_true(r >= 0 and r < 1)
            local n = randInt(29)
            assert.is_true(n >= 1 and n <= 29)
        end
    end)
end)
