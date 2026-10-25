local keyactions = dofile("resources/[scavengesurvive]/hud/shared/logic/keyactions.lua")
local KEYS = {
    interact = "F",
    putaway = "Y",
    drop = "N",
    inventory = "H",
    reload = "R",
    engine = "Y",
    lights = "N",
    doors = "2",
    radio = "R",
}
local function texts(lines)
    local out = {}
    for _, l in ipairs(lines) do
        out[#out + 1] = l.key .. " " .. l.text
    end
    return out
end
describe("hud key actions", function()
    it("shows nothing before spawn, with the UI open or knocked out", function()
        assert.same({}, keyactions.lines({ spawned = false }, KEYS))
        assert.same({}, keyactions.lines({ spawned = true, uiOpen = true }, KEYS))
        assert.same({}, keyactions.lines({ spawned = true, knockedOut = true }, KEYS))
    end)
    it("next to a landed crate: Open supply crate / Open weapon cache before the rest", function()
        local l = keyactions.lines({ spawned = true, held = false, nearCrate = "supply" }, KEYS)
        assert.same({ "F Open supply crate", "H Open inventory" }, texts(l))
        l = keyactions.lines({ spawned = true, held = false, nearCrate = "cache" }, KEYS)
        assert.same({ "F Open weapon cache", "H Open inventory" }, texts(l))
        l = keyactions.lines({ spawned = true, held = false, nearCrate = "other" }, KEYS)
        assert.same({ "H Open inventory" }, texts(l))
    end)
    it("empty hands: Open inventory (and Remove bag once supported)", function()
        assert.same(
            { "H Open inventory" },
            texts(keyactions.lines({ spawned = true, held = false, hasBag = true }, KEYS))
        )
        local l =
            keyactions.lines({ spawned = true, held = false, hasBag = true, supports = { removebag = true } }, KEYS)
        assert.same({ "H Open inventory", "N Remove bag" }, texts(l))
    end)
    it("food: Eat, Put away, Drop item, Open inventory (the footage order)", function()
        local l = keyactions.lines(
            { spawned = true, held = { uname = "Hotdog", category = "food" }, supports = { eat = true } },
            KEYS
        )
        assert.same({ "F Eat", "Y Put away", "N Drop item", "H Open inventory" }, texts(l))
    end)
    it("uncooked food next to a campfire or barbecue: Cook instead of Eat (#95)", function()
        local ctx = { spawned = true, held = { uname = "Meat", category = "food" }, nearCooker = true }
        ctx.supports = { eat = true }
        assert.same("F Cook", texts(keyactions.lines(ctx, KEYS))[1])
    end)
    it("weapons clear the list: Holster, Reload, Unload, Drop, Inventory", function()
        local held = { uname = "DesertEagle", category = "weapon", isWeapon = true }
        local l = keyactions.lines(
            { spawned = true, held = held, supports = { holster = true, reload = true, unload = true } },
            KEYS
        )
        assert.same({ "Y Holster weapon", "R Reload", "N (Hold) Unload", "N Drop item", "H Open inventory" }, texts(l))
        l = keyactions.lines({ spawned = true, held = held, supports = {} }, KEYS)
        assert.same({ "Y Put away", "N Drop item", "H Open inventory" }, texts(l))
    end)
    it("gives instead of dropping next to a player when give exists", function()
        local held = { uname = "Wrench", category = "generic" }
        local l = keyactions.lines({ spawned = true, held = held, nearPlayer = true, supports = { give = true } }, KEYS)
        assert.same({ "Y Put away", "N Give item", "H Open inventory" }, texts(l))
    end)
    it("driver lines only when the vehicle commands exist", function()
        assert.same({}, keyactions.lines({ spawned = true, driver = true }, KEYS))
        local l = keyactions.lines(
            { spawned = true, driver = true, supports = { engine = true, lights = true, doors = true, radio = true } },
            KEYS
        )
        assert.same({ "Y Toggle engine", "N Toggle lights", "2 Toggle locks", "R Open radio" }, texts(l))
    end)
    it("per-item verbs and bags", function()
        local l = keyactions.lines(
            { spawned = true, held = { uname = "Armour", category = "generic" }, supports = { special = true } },
            KEYS
        )
        assert.equals("F Wear armour", texts(l)[1])
        l = keyactions.lines(
            {
                spawned = true,
                held = { uname = "Daypack", category = "bag" },
                supports = { openbag = true, wearbag = true },
            },
            KEYS
        )
        assert.same({ "F Open satchel", "Y Wear", "Y Put away", "N Drop item", "H Open inventory" }, texts(l))
    end)
end)
