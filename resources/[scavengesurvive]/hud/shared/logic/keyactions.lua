-- The key-actions list (core/ui/key-actions.pwn, _UpdateKeyActions): which "KEY verb" lines the HUD shows for the
-- player's state and held item. Ported line for line; a line whose action the port does not implement yet is
-- gated by ctx.supports so the HUD never advertises a key that does nothing.
local M = {}

-- M.tr(text): a line in the reader's language; the client sets it to lib lang.text, identity elsewhere
M.tr = function(s)
    return s
end
local function tr(s)
    return M.tr(s)
end

-- Per-item verbs on the interact key (upstream's single-item table), by item type uname.
-- lang:begin
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
M.BODY_PART_VERB = "Install Bobcat body part"
M.GLOVEBOX_VERB = "Open glovebox" -- listed so tools/lang_qa collects it
-- lang:end

M.BODY_PARTS = {}
for _, part in ipairs({ "Tailgate", "LeftDoor", "RightDoor", "Hood", "FrontBumper", "RearBumper" }) do
    M.SPECIAL["Bobcat" .. part .. "Good"] = M.BODY_PART_VERB
    M.SPECIAL["Bobcat" .. part .. "Bad"] = M.BODY_PART_VERB
    M.BODY_PARTS["Bobcat" .. part .. "Good"] = true
    M.BODY_PARTS["Bobcat" .. part .. "Bad"] = true
end

-- The interact verb next to a landed crate, by the loot resource's crate kind.
-- lang:begin
M.CRATES = { supply = "Open supply crate", cache = "Open weapon cache", dumpster = "Open dumpster" }
-- the world resource's button labels (puzzles.lua, area69.lua, doors.lua), listed so tools/lang_qa collects them
M.BUTTON_LABELS = {
    "Activate",
    "Activate door",
    "Activate gate",
    "Climb down the ladder",
    "Climb up the ladder",
    "Enter",
    "Go inside",
    "Interact",
    "Leave",
    "Locked",
    "Use",
    "Use the lift",
}
-- lang:end

-- ctx = {
--   spawned, uiOpen, knockedOut, hudOff, driver, hitch ("hitch" / "unhitch"), nearTrunk,
--   nearBonnet ("open" / "closed": an engine bonnet in reach with empty hands), nearPlayer,
--   nearItem (a loose world item in pickup reach),
--   nearInspectable (the uname of a nearby sign, plant pot or body),
--   cuffedNearby, hasBag,
--   glovebox (seated in a front seat of a vehicle with a glovebox: "Open glovebox"),
--   nearFeature ("ladder" / "zipline" / "ladder_on" / "zipline_on" / "button:<label>"), nearCrate ("supply" / "cache" / "dumpster"),
--   nearDoor ("open" / "closed" / "locked": a walk-in vehicle door in reach, the towable Airstream's),
--   bodyPart ("(Hold) Remove Left Door" / "(Hold) Tighten Left Door", already in the reader's language: a Wrench in
--     hand at a vehicle body part that is still on),
--   installPart (a held body part is at its matching empty vehicle slot),
--   held = false | { uname, category, isWeapon },
--   nearCooker,                           -- uncooked food in hand next to a campfire or barbecue (#95): "Cook"
--   nearMachine,                          -- a machine in reach (#145): "Access machine" / "(Hold) Machine menu"
--   nearContainer,                        -- a bag or box lying in reach: "Open" / "(Hold) Pick up"; "fixed" (the
--                                         -- snack machine): "Open" only
--   carmour,                              -- vehicles carmour: "attach" (placing a defence), "weld" (the Welder's
--                                         -- torch at a trailer), "torch" (it anywhere else), "defence" (one in hand
--                                         -- at a trailer), "grind" (an Angle Grinder at a trailer), "welder" (empty
--                                         -- hands at a Welder), "gas" / "gasoff" (empty hands at gas lying by a
--                                         -- Welder); F then does only that
--   supports = { [capability] = true },   -- eat, drink, openbag, wearbag, special, holster, reload, unload, give,
--                                         -- removebag, uncuff, trunk, repair, engine, lights, doors, radio
-- }
-- keys = { interact, putaway, drop, inventory, reload, engine, lights, doors, radio, hitch, glovebox } (display names)
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
        add("engine", tr("Toggle engine"), "engine")
        add("lights", tr("Toggle lights"), "lights")
        add("doors", tr("Toggle locks"), "doors")
        add("radio", ctx.held and ctx.held.isWeapon and tr("(Hold) Open radio") or tr("Open radio"), "radio")
        -- not an upstream line: its trailer key (KEY_ACTION, vehicle/trailer.pwn) went unlisted
        if ctx.hitch then
            add("hitch", ctx.hitch == "unhitch" and tr("Unhitch trailer") or tr("Hitch trailer"))
        end
        -- not an upstream line either: the glovebox in the dash (E)
        if ctx.glovebox then
            add("glovebox", tr("Open glovebox"))
        end
        add("inventory", tr("Open inventory"))
        return out
    end
    -- a front passenger has the glovebox in reach too
    if ctx.glovebox then
        add("glovebox", tr("Open glovebox"))
        add("inventory", tr("Open inventory"))
        return out
    end
    -- A reachable world item consumes F before nearby world, crate or vehicle actions.
    if ctx.nearItem and not ctx.held then
        local cm = ctx.carmour
        if cm == "welder" then
            add("interact", tr("Take torch"))
            add("interact", tr("(Hold) Pick up welder"))
        elseif cm == "gas" or cm == "gasoff" then
            add("interact", cm == "gas" and tr("Hook up to welder") or tr("Unhook from welder"))
            add("interact", tr("(Hold) Pick up"))
        elseif ctx.nearContainer then
            add("interact", tr("Open"))
            if ctx.nearContainer ~= "fixed" then -- the snack machine opens but is never carried off
                add("interact", tr("(Hold) Pick up"))
            end
        elseif ctx.nearInspectable then
            local inspectText = { Sign = tr("Edit sign"), PlantPot = tr("Inspect plant pot") }
            add("interact", inspectText[ctx.nearInspectable] or tr("Investigate"))
            add("interact", tr("(Hold) Pick up"))
        elseif ctx.nearMachine then
            add("interact", tr("Access machine"))
            add("interact", tr("(Hold) Machine menu"))
        else
            add("interact", tr("Pick up"))
        end
        add("inventory", tr("Open inventory"))
        return out
    end
    -- ladders and ziplines (world resource): the F line replaces everything else while climbing or riding
    local feature = ctx.nearFeature
    if feature == "ladder_on" or feature == "zipline_on" then
        add("interact", tr("Let go"))
        return out
    elseif feature == "ladder" then
        add("interact", tr("Climb ladder"))
    elseif feature == "zipline" then
        add("interact", tr("Grab zipline"))
    elseif type(feature) == "string" and feature:sub(1, 7) == "button:" then
        -- a button (world: a gate, a door, a puzzle): upstream's "Press F to <label>"
        add("interact", tr(feature:sub(8)))
    end
    -- a landed supply crate or weapons cache (loot resource): upstream's button label next to the crate
    if M.CRATES[ctx.nearCrate] then
        add("interact", tr(M.CRATES[ctx.nearCrate]))
    end
    -- carmour (vehicles, not upstream lines): these lines replace everything else while attaching or with the torch
    local cm = ctx.carmour
    if cm == "attach" then
        add("interact", tr("Attach here"))
        add("drop", tr("Cancel"))
        return out
    elseif cm == "weld" or cm == "torch" then
        add("interact", cm == "weld" and tr("Weld panel") or tr("Put torch back"))
        add("drop", tr("Put torch back"))
        return out
    elseif cm == "defence" then
        add("interact", tr("Attach to trailer"))
    elseif cm == "grind" then
        add("interact", tr("Grind panel off"))
    elseif cm == "welder" then
        add("interact", tr("Take torch"))
        add("interact", tr("(Hold) Pick up welder"))
    elseif cm == "gas" or cm == "gasoff" then
        add("interact", cm == "gas" and tr("Hook up to welder") or tr("Unhook from welder"))
        add("interact", tr("(Hold) Pick up"))
    end
    local busyF = cm ~= nil
    -- the towable Airstream's door (vehicles, not an upstream line)
    if ctx.nearDoor and not busyF then
        local doorText = { open = tr("Close door"), locked = tr("Door locked") }
        add("interact", doorText[ctx.nearDoor] or tr("Open door"))
    end
    -- a Wrench at a body part of a vehicle (vehicles bodyparts, not an upstream line): a hold takes the part off
    if ctx.bodyPart and not busyF then
        add("interact", ctx.bodyPart)
    end
    -- a machine (items, #145): upstream's button "Press F to access machine / Hold F to open menu"; a Crowbar in
    -- hand takes it down instead (Deconstruct, a port deviation: upstream left it a TODO)
    if ctx.nearMachine and not busyF and not (ctx.held and ctx.held.uname == "Crowbar") then
        add("interact", tr("Access machine"))
        add("interact", tr("(Hold) Machine menu"))
    end
    -- a bag or box lying within reach (items): upstream's button "Hold F to pick up / Press F to open"
    if ctx.nearContainer and not busyF and not (ctx.held and ctx.held.uname == "Crowbar") then
        add("interact", tr("Open"))
        add("interact", tr("(Hold) Pick up"))
    end
    if ctx.nearTrunk then
        add("interact", tr("Open Trunk"), "trunk")
    end
    if ctx.nearBonnet and not busyF then
        add("interact", ctx.nearBonnet == "open" and tr("Close Bonnet") or tr("Open Bonnet"))
    end
    local h = ctx.held
    if not h then
        if ctx.hasHolster then
            add("putaway", tr("Draw weapon"), "holster")
        end
        if ctx.cuffedNearby then
            add("interact", tr("Remove handcuffs"), "uncuff")
        end
        add("inventory", tr("Open inventory"))
        if ctx.hasBag then
            add("drop", tr("Remove bag"), "removebag")
        end
        return out
    end
    if M.SPECIAL[h.uname] and (not M.BODY_PARTS[h.uname] or ctx.installPart) then
        add("interact", tr(M.SPECIAL[h.uname]), "special")
    elseif h.category == "food" then
        add("interact", ctx.nearCooker and tr("Cook") or tr("Eat"), "eat")
    elseif h.category == "bag" then
        add("interact", tr("Open satchel"), "openbag")
        add("putaway", tr("Wear"), "wearbag")
    elseif h.category == "safebox" then
        add("interact", tr("Open"), "openbag")
    elseif h.category == "liquid" and h.uname ~= "GasCan" then -- F with a Petrol Can fills or pours, never drinks
        add("interact", tr("Drink"), "drink")
    end
    if h.isWeapon then
        out = {} -- upstream clears the list for weapons
        add("putaway", supports.holster and tr("Holster weapon") or tr("Put away"))
        add("reload", tr("Reload"), "reload")
        add("drop", tr("(Hold) Unload"), "unload")
    else
        add("putaway", tr("Put away"))
    end
    if ctx.nearPlayer and supports.give then
        add("drop", tr("Give item"))
    else
        add("drop", tr("Drop item"))
    end
    add("inventory", tr("Open inventory"))
    return out
end

return M
