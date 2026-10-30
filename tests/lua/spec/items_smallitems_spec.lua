-- The small item behaviours (items/shared/logic/smallitems.lua, upstream note/sign/dice/locator/stungun/molotov.pwn,
-- #136).
local small = dofile("resources/[scavengesurvive]/items/shared/logic/smallitems.lua")
local liquids = dofile("resources/[scavengesurvive]/items/shared/logic/liquids.lua")

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

describe("small items", function()
    describe("note and sign text", function()
        it(
            "keeps a player's text without control characters, colour codes or outer spaces, cut at the limit",
            function()
                assert.are.equal("hello there", small.cleanText("  hello\tthere \n", 256))
                assert.are.equal("red", small.cleanText("#FF0000red", 256))
                assert.are.equal("abc", small.cleanText("abcdef", 3))
                assert.are.equal("", small.cleanText(nil, 10))
                assert.are.equal("", small.cleanText(42, 10))
                assert.are.equal(256, #small.cleanText(string.rep("x", 300), small.NOTE_MAX))
                assert.are.equal(128, #small.cleanText(string.rep("x", 300), small.SIGN_MAX))
            end
        )

        it("reads the message from either JSON shape and labels the note like upstream", function()
            assert.are.equal("", small.text(nil))
            assert.are.equal("", small.text({}))
            assert.are.equal("hi", small.text({ text = "hi" }))
            assert.are.equal("hi", small.text({ { text = "hi" } }))
            assert.are.equal("Note (Blank)", small.noteLabel("Note", nil))
            assert.are.equal("Note (hi)", small.noteLabel("Note", { text = "hi" }))
            assert.are.equal("Note (12345678)", small.noteLabel("Note", { text = "12345678" }))
            assert.are.equal("Note (12345678(...))", small.noteLabel("Note", { text = "123456789" }))
        end)

        it("splits a sign's text on backslashes and drops trailing empty lines", function()
            assert.same({ "KEEP OUT" }, small.signLines("KEEP OUT"))
            assert.same({ "KEEP", "OUT" }, small.signLines("KEEP\\OUT"))
            assert.same({ "a", "", "b" }, small.signLines("a\\\\b\\"))
            assert.same({}, small.signLines(""))
            assert.same({}, small.signLines(nil))
        end)
    end)

    describe("dice", function()
        it("rolls one of six faces and lands 40 cm ahead of the thrower", function()
            for face = 1, 6 do
                assert.are.equal(
                    face,
                    small.rollDice(function()
                        return face
                    end)
                )
            end
            local x, y = small.diceLanding(10, 20, 0)
            assert.is_true(near(x, 10) and near(y, 20.4))
            x, y = small.diceLanding(10, 20, 90) -- facing west
            assert.is_true(near(x, 9.6) and near(y, 20))
        end)

        it("shows each face with upstream's rotation set, the first face for anything else", function()
            assert.same({ 0, 90 }, { small.diceRotation(2) })
            assert.same({ 180, 0 }, { small.diceRotation(6) })
            assert.same({ 0, 0 }, { small.diceRotation(nil) })
            assert.are.equal(3, small.diceFace({ face = 3 }))
            assert.are.equal(3, small.diceFace({ { face = "3" } }))
            assert.is_nil(small.diceFace({ face = 9 }))
            assert.is_nil(small.diceFace(nil))
        end)
    end)

    describe("stun gun", function()
        it("is charged by data.charged = 1 and says so in its label", function()
            assert.is_false(small.isCharged(nil))
            assert.is_false(small.isCharged({ charged = 0 }))
            assert.is_true(small.isCharged({ charged = 1 }))
            assert.is_true(small.isCharged({ { charged = "1" } }))
            assert.are.equal("Stun Gun (Uncharged)", small.stunLabel("Stun Gun", nil))
            assert.are.equal("Stun Gun (Charged)", small.stunLabel("Stun Gun", { charged = 1 }))
            assert.are.equal(60000, small.STUN_KO_MS)
        end)
    end)

    describe("molotov", function()
        local CAN = { category = "liquid", categoryData = { capacity = 20, liquids = { { "Petrol", 1 } } } }

        it("pours half a litre of petrol out of the can", function()
            local ok, nextData, moved = small.pourMolotov(liquids, CAN, { amount = 19.4, liquid = "Petrol" })
            assert.is_true(ok)
            assert.is_true(near(nextData.amount, 18.9) and nextData.liquid == "Petrol")
            assert.is_true(near(moved, 0.5))
        end)

        it("takes what is left of a nearly empty can", function()
            local ok, nextData, moved = small.pourMolotov(liquids, CAN, { amount = 0.2, liquid = "Petrol" })
            assert.is_true(ok)
            assert.is_true(near(moved, 0.2) and near(nextData.amount, 0))
        end)

        it("refuses an empty can or one holding anything but petrol", function()
            assert.same({ false, "PETROLEMPTY" }, { small.pourMolotov(liquids, CAN, { amount = 0 }) })
            assert.same({ false, "PETROLEMPTY" }, { small.pourMolotov(liquids, CAN, nil) })
            local water = { category = "liquid", categoryData = { capacity = 20, liquids = { { "Water", 1 } } } }
            assert.same(
                { false, "FUELNOTPETR" },
                { small.pourMolotov(liquids, water, { amount = 3, liquid = "Water" }) }
            )
        end)
    end)

    it("knows which phone a locator was synced to", function()
        assert.is_nil(small.locatorPhone(nil))
        assert.are.equal(42, small.locatorPhone({ phone = 42 }))
        assert.are.equal(42, small.locatorPhone({ { phone = "42" } }))
    end)
end)
