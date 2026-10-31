-- The key-actions list (core/ui/key-actions.pwn, _UpdateKeyActions): which "KEY verb" lines the HUD shows for the
-- player's state and held item. Ported line for line; a line whose action the port does not implement yet is
-- gated by ctx.supports so the HUD never advertises a key that does nothing.
local M = {}

-- Per-item verbs on the interact key (upstream's single-item table), by item type uname.
M.SPECIAL = {
    Sign = "Place sign",
    Armour = "Wear armour",
    Crowbar = "Deconstruct",
    Shield = "Place shield",
    Wheel = "Repair vehicle wheel",
    Clothes = "Wear clothes",
    Pills = "Take Pills",
    HerpDerp = "Herp-a-derp",
    Note = "Read note", -- not upstream lines: the port's note and locator use the interact key (#136)
    Locator = "Locate phone",
    FishRod = "Cast line", -- #141
}

-- The interact verb next to a landed crate, by the loot resource's crate kind.
M.CRATES = { supply = "Open supply crate", cache = "Open weapon cache" }

-- ctx = {
--   spawned, uiOpen, knockedOut, hudOff, driver, hitch ("hitch" / "unhitch"), nearTrunk, nearBonnet, nearPlayer,
--   cuffedNearby, hasBag,
--   nearFeature ("ladder" / "zipline" / "ladder_on" / "zipline_on" / "button:<label>"), nearCrate ("supply" / "cache"),
--   nearDoor ("open" / "closed": a walk-in vehicle door in reach, the towable Airstream's),
--   held = false | { uname, category, isWeapon },
--   nearCooker,                           -- uncooked food in hand next to a campfire or barbecue (#95): "Cook"
--   nearMachine,                          -- a machine in reach (#145): "Access machine" / "(Hold) Machine menu"
--   supports = { [capability] = true },   -- eat, drink, openbag, wearbag, special, holster, reload, unload, give,
--                                         -- removebag, uncuff, trunk, repair, engine, lights, doors, radio
-- }
-- keys = { interact, putaway, drop, inventory, reload, engine, lights, doors, radio, hitch } (display names)
-- Returns { { key = "F", text = "Open Trunk" }, ... } in upstream order.
function M.lines(ctx, keys)
    local out = {}
    local supports = ctx.supports or {}
    local function add(key, text, cap)
        if cap == nil or supports[cap] then
            out[#out + 1] = { key = keys[key] or "?", text = text }
        end
    end
    if not ctx.spawned or ctx.uiOpen or ctx.knockedOut or ctx.hudOff then
        return out
    end
    if ctx.driver then
        add("engine", "Toggle engine", "engine")
        add("lights", "Toggle lights", "lights")
        add("doors", "Toggle locks", "doors")
        add("radio", ctx.held and ctx.held.isWeapon and "(Hold) Open radio" or "Open radio", "radio")
        -- not an upstream line: its trailer key (KEY_ACTION, vehicle/trailer.pwn) went unlisted
        if ctx.hitch then
            add("hitch", ctx.hitch == "unhitch" and "Unhitch trailer" or "Hitch trailer")
        end
        return out
    end
    -- ladders and ziplines (world resource): the F line replaces everything else while climbing or riding
    local feature = ctx.nearFeature
    if feature == "ladder_on" or feature == "zipline_on" then
        add("interact", "Let go")
        return out
    elseif feature == "ladder" then
        add("interact", "Climb ladder")
    elseif feature == "zipline" then
        add("interact", "Grab zipline")
    elseif type(feature) == "string" and feature:sub(1, 7) == "button:" then
        -- a button (world: a gate, a door, a puzzle): upstream's "Press F to <label>"
        add("interact", feature:sub(8))
    end
    -- a landed supply crate or weapons cache (loot resource): upstream's button label next to the crate
    if M.CRATES[ctx.nearCrate] then
        add("interact", M.CRATES[ctx.nearCrate])
    end
    -- the towable Airstream's door (vehicles, not an upstream line)
    if ctx.nearDoor then
        add("interact", ctx.nearDoor == "open" and "Close door" or "Open door")
    end
    -- a machine (items, #145): upstream's button "Press F to access machine / Hold F to open menu"; a Crowbar in
    -- hand takes it down instead (Deconstruct, a port deviation: upstream left it a TODO)
    if ctx.nearMachine and not (ctx.held and ctx.held.uname == "Crowbar") then
        add("interact", "Access machine")
        add("interact", "(Hold) Machine menu")
    end
    if ctx.nearTrunk then
        add("interact", "Open Trunk", "trunk")
    end
    if ctx.nearBonnet then
        add("interact", "Repair with tool", "repair")
    end
    local h = ctx.held
    if not h then
        if ctx.hasHolster then
            add("putaway", "Draw weapon", "holster")
        end
        if ctx.cuffedNearby then
            add("interact", "Remove handcuffs", "uncuff")
        end
        add("inventory", "Open inventory")
        if ctx.hasBag then
            add("drop", "Remove bag", "removebag")
        end
        return out
    end
    if M.SPECIAL[h.uname] then
        add("interact", M.SPECIAL[h.uname], "special")
    elseif h.category == "food" then
        add("interact", ctx.nearCooker and "Cook" or "Eat", "eat")
    elseif h.category == "bag" then
        add("interact", "Open satchel", "openbag")
        add("putaway", "Wear", "wearbag")
    elseif h.category == "liquid" then
        add("interact", "Drink", "drink")
    end
    if h.isWeapon then
        out = {} -- upstream clears the list for weapons
        add("putaway", supports.holster and "Holster weapon" or "Put away")
        add("reload", "Reload", "reload")
        add("drop", "(Hold) Unload", "unload")
    else
        add("putaway", "Put away")
    end
    if ctx.nearPlayer and supports.give then
        add("drop", "Give item")
    else
        add("drop", "Drop item")
    end
    add("inventory", "Open inventory")
    return out
end

return M
