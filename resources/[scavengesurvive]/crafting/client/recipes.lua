-- luacheck: max line length 140
-- /recipes: the recipe browser (upstream core/player/recipes.pwn), reworked so nobody needs a help page. A search
-- box (result, ingredient or tool name) and method filters over one list; the selected recipe shows what it takes,
-- ticked green against what the character carries (the server's recipeCarriedSent), and numbered steps saying
-- exactly where and how to make it.
-- GUI functions that postdate the generated luacheck lists:
-- luacheck: read_globals guiSetSize guiCreateGridList guiGridListSetSortingEnabled guiGridListAddColumn
-- luacheck: read_globals guiGridListAddRow guiGridListSetItemText guiGridListSetItemColor guiGridListClear
-- luacheck: read_globals guiGridListGetSelectedItem guiGridListSetSelectedItem guiCreateScrollPane guiGetInputMode
-- luacheck: read_globals guiLabelSetColor guiLabelSetHorizontalAlign guiLabelGetTextExtent guiCreateEdit
-- luacheck: read_globals guiEditSetCaretIndex guiBringToFront guiScrollPaneSetVerticalScrollPosition utf8
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local L = lang.text

local W, H = 780, 520
local LIST_W, PANE_X = 300, 324
local PANE_W = W - PANE_X - 14
local LINE_H = 16
local WHITE, GREY, RED = { 255, 255, 255 }, { 190, 190, 190 }, { 255, 110, 110 }
local GREEN, YELLOW = { 110, 220, 110 }, { 255, 255, 0 }
-- each method's colour: its tag in the list, its filter and the "how" heading
local COLOURS = {
    combine = { 255, 255, 0 },
    ground = { 51, 200, 51 },
    workbench = { 51, 204, 255 },
    machines = { 255, 170, 0 },
    cooking = { 255, 130, 90 },
    gathering = { 190, 255, 140 },
}
local KINDS = { "combine", "ground", "workbench", "machines", "cooking", "gathering" }
-- lang:begin
local KIND_NAMES = {
    combine = "Combination",
    ground = "Construction",
    workbench = "Workbench",
    machines = "Machines",
    cooking = "Cooking",
    gathering = "Gathering",
}
local TEXTS = {
    all = "All",
    search = "Search:",
    need = "You need:",
    kept = "kept",
    usedUp = "used up",
    have = "you have it",
    missing = "missing",
    steps = "How to make it:",
}
-- lang:end

local lower = utf8 and utf8.lower or string.lower
local win = nil -- the open window's elements and state
local filter, query = "all", "" -- kept between openings while the resource runs

local function itemName(uname)
    local name = lang.itemName(uname)
    return (name and name ~= "") and name or uname
end

-- every recipe once, the crafting ones then the items resource's machines, cooking and gathering, by method order
local function allRecipes()
    local byKind = {}
    for _, kind in ipairs(KINDS) do
        byKind[kind] = craft.ofKind(kind)
    end
    for _, r in ipairs(exports.items:getProductionRecipes()) do
        if byKind[r.kind] then
            table.insert(byKind[r.kind], r)
        end
    end
    local out = {}
    for _, kind in ipairs(KINDS) do
        for _, r in ipairs(byKind[kind]) do
            out[#out + 1] = r
        end
    end
    return out
end

-- the search text a recipe answers to: its result, ingredients and tool in the player's language
local function searchText(r)
    local parts = { itemName(r.result.uname) }
    for _, ing in ipairs(r.ingredients) do
        parts[#parts + 1] = itemName(ing.uname)
    end
    if r.tool then
        parts[#parts + 1] = itemName(r.tool)
    end
    return lower(table.concat(parts, "\n"))
end

local function matches(r)
    if filter ~= "all" and r.kind ~= filter then
        return false
    end
    return query == "" or win.search[r]:find(query, 1, true) ~= nil
end

-- the detail pane: a stack of wrapped labels, each its own colour
local function clearPane()
    for _, el in ipairs(win.lines) do
        if isElement(el) then
            destroyElement(el)
        end
    end
    win.lines, win.y = {}, 0
end

local function addLine(text, colour, indent, font)
    indent = indent or 0
    local width = PANE_W - 24 - indent
    local l = guiCreateLabel(indent, win.y, width, LINE_H, text, false, win.pane)
    guiSetFont(l, font or "default-normal")
    guiLabelSetHorizontalAlign(l, "left", true)
    local c = colour or WHITE
    guiLabelSetColor(l, c[1], c[2], c[3])
    local rows = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        guiSetText(l, part ~= "" and part or " ")
        rows = rows + math.max(1, math.ceil((guiLabelGetTextExtent(l) + 4) / width))
    end
    guiSetText(l, text)
    guiSetSize(l, width, rows * LINE_H + 2, false)
    win.y = win.y + rows * LINE_H + 2
    win.lines[#win.lines + 1] = l
end

local function gap()
    win.y = win.y + 8
end

-- how many of each item type the recipe asks for, tool included
local function needed(r)
    local n = {}
    for _, ing in ipairs(r.ingredients) do
        n[ing.uname] = (n[ing.uname] or 0) + ing.count
    end
    if r.tool then
        n[r.tool] = (n[r.tool] or 0) + 1
    end
    return n
end

-- one "you need" line, green when carried in that number, red when not, plain until the server has answered
local function needLine(text, uname, need)
    local carried = win.carried
    if not carried then
        return addLine(text, WHITE, 12)
    end
    if (carried[uname] or 0) >= need then
        addLine(text .. "  - " .. L(TEXTS.have), GREEN, 12)
    else
        addLine(text .. "  - " .. L(TEXTS.missing), RED, 12)
    end
end

local function stepText(step)
    local args = {}
    for i, a in ipairs(step.args) do
        args[i] = type(a) == "table" and itemName(a.item) or a
    end
    return lang.format(step.fmt, unpack(args))
end

local function showRecipe(r)
    clearPane()
    guiSetText(win.title, r and itemName(r.result.uname) or "")
    if not r then
        return
    end
    local colour = COLOURS[r.kind] or WHITE
    guiLabelSetColor(win.title, colour[1], colour[2], colour[3])
    addLine(L(KIND_NAMES[r.kind] or r.kind), colour, 0, "default-bold-small")
    gap()
    -- what it takes; the machines and cookers are places, not things to carry, so they get no tick
    addLine(L(TEXTS.need), YELLOW, 0, "default-bold-small")
    local need = needed(r)
    for _, ing in ipairs(r.ingredients) do
        local name = itemName(ing.uname)
        local text = (ing.count > 1 and (ing.count .. "x " .. name) or name)
            .. " ("
            .. L(ing.keep and TEXTS.kept or TEXTS.usedUp)
            .. ")"
        needLine(text, ing.uname, need[ing.uname])
    end
    if r.tool then
        local text = lang.format("Tool: %s", itemName(r.tool))
        if r.kind == "machines" or r.kind == "cooking" then
            addLine(text, WHITE, 12)
        else
            needLine(text, r.tool, need[r.tool])
        end
    end
    gap()
    addLine(L(TEXTS.steps), YELLOW, 0, "default-bold-small")
    local steps = craft.steps(r)
    if steps then
        for i, step in ipairs(steps) do
            addLine(i .. ".  " .. stepText(step), WHITE, 12)
        end
    elseif r.instructions then
        addLine(r.instructions, WHITE, 12)
    end
    if r.note then
        gap()
        addLine(L(r.note), COLOURS.workbench)
    end
    if r.removalTool then
        gap()
        addLine(lang.format("Can be taken down again with a %s.", itemName(r.removalTool)), GREY)
    end
    guiScrollPaneSetVerticalScrollPosition(win.pane, 0)
end

local function selected()
    local row = guiGridListGetSelectedItem(win.grid)
    return row and row >= 0 and win.shown[row + 1] or nil
end

-- fill the list with what the filter and the search let through, keeping the selected recipe when it stays
local function refill()
    local keep = selected()
    guiGridListClear(win.grid)
    win.shown = {}
    local pick = 0
    for _, r in ipairs(win.recipes) do
        if matches(r) then
            local row = guiGridListAddRow(win.grid)
            local c = COLOURS[r.kind] or WHITE
            guiGridListSetItemText(win.grid, row, 1, itemName(r.result.uname), false, false)
            guiGridListSetItemText(win.grid, row, 2, L(KIND_NAMES[r.kind] or r.kind), false, false)
            guiGridListSetItemColor(win.grid, row, 2, c[1], c[2], c[3])
            win.shown[#win.shown + 1] = r
            if r == keep then
                pick = row
            end
        end
    end
    if #win.shown > 0 then
        guiGridListSetSelectedItem(win.grid, pick, 1)
    end
    showRecipe(win.shown[pick + 1])
end

local function setFilter(kind)
    filter = kind
    -- the active filter's text in its method colour (yellow for All), the others grey
    for k, button in pairs(win.filters) do
        local c = k == kind and (COLOURS[k] or YELLOW) or GREY
        guiSetProperty(button, "NormalTextColour", string.format("FF%02X%02X%02X", c[1], c[2], c[3]))
        guiSetProperty(button, "HoverTextColour", string.format("FF%02X%02X%02X", c[1], c[2], c[3]))
    end
    refill()
end

local function close()
    if not win then
        return
    end
    if isElement(win.window) then
        destroyElement(win.window)
    end
    removeEventHandler("onClientKey", root, win.onKey)
    showCursor(false)
    guiSetInputMode(win.inputMode)
    win = nil
end

local function open()
    close()
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, L("Recipes"), false)
    guiWindowSetSizable(window, false)
    win = { window = window, lines = {}, y = 0, shown = {}, filters = {}, inputMode = guiGetInputMode() }
    win.recipes = allRecipes()
    win.search = {}
    for _, r in ipairs(win.recipes) do
        win.search[r] = searchText(r)
    end

    local searchLabel = guiCreateLabel(14, 32, 70, 22, L(TEXTS.search), false, window)
    guiSetFont(searchLabel, "default-bold-small")
    win.edit = guiCreateEdit(84, 28, LIST_W - 70, 26, query, false, window)

    -- the filters: All and one per method
    local kinds = { "all" }
    for _, k in ipairs(KINDS) do
        kinds[#kinds + 1] = k
    end
    local bw = math.floor((W - 28) / #kinds)
    for i, k in ipairs(kinds) do
        local x = 14 + (i - 1) * bw
        local button = guiCreateButton(x, 62, bw - 4, 26, L(k == "all" and TEXTS.all or KIND_NAMES[k]), false, window)
        win.filters[k] = button
        addEventHandler("onClientGUIClick", button, function()
            setFilter(k)
        end, false)
    end

    win.grid = guiCreateGridList(14, 98, LIST_W, H - 154, false, window)
    guiGridListSetSortingEnabled(win.grid, false)
    guiGridListAddColumn(win.grid, L("Recipe"), 0.6)
    guiGridListAddColumn(win.grid, "", 0.34)
    win.title = guiCreateLabel(PANE_X, 98, PANE_W, 24, "", false, window)
    guiSetFont(win.title, "default-bold-small")
    win.pane = guiCreateScrollPane(PANE_X, 124, PANE_W, H - 180, false, window)

    local closeButton = guiCreateButton((W - 120) / 2, H - 44, 120, 30, L("Close"), false, window)
    addEventHandler("onClientGUIClick", closeButton, close, false)
    addEventHandler("onClientGUIClick", win.grid, function()
        showRecipe(selected())
    end, false)
    addEventHandler("onClientGUIChanged", win.edit, function()
        query = lower(guiGetText(win.edit) or "")
        refill()
    end, false)
    win.onKey = function(key, press)
        if press and key == "escape" then
            cancelEvent()
            close()
        end
    end
    addEventHandler("onClientKey", root, win.onKey)
    showCursor(true)
    guiSetInputMode("no_binds")
    guiBringToFront(win.edit)
    guiEditSetCaretIndex(win.edit, utf8 and utf8.len(query) or #query)
    setFilter(filter)
    triggerServerEvent("recipeCarriedRequested", localPlayer)
end

-- what the character carries, for the green and red "you need" lines
addEventHandler("recipeCarriedSent", localPlayer, function(counts)
    if not win then
        return
    end
    win.carried = type(counts) == "table" and counts or {}
    showRecipe(selected())
end)

addCommandHandler("recipes", open)
addCommandHandler("recipe", open)
addEventHandler("onClientResourceStop", resourceRoot, close)
