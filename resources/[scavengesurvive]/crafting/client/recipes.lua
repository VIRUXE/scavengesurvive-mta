-- luacheck: max line length 140
-- /recipes: the recipe browser (upstream core/player/recipes.pwn), reworked so nobody needs a help page. A search
-- box (result, ingredient or tool name) and method filters over a list of recipes with their item pictures; the
-- selected recipe shows what it takes as picture tiles, green or red against what the character carries (the
-- server's recipeCarriedSent), and numbered steps saying exactly where and how to make it. Clicking an ingredient
-- that has a recipe of its own opens that recipe.
-- GUI functions that postdate the generated luacheck lists:
-- luacheck: read_globals guiSetSize guiCreateScrollPane guiGetInputMode guiSetPosition guiCreateStaticImage
-- luacheck: read_globals guiLabelSetColor guiLabelSetHorizontalAlign guiLabelGetTextExtent guiCreateEdit
-- luacheck: read_globals guiEditSetCaretIndex guiBringToFront guiScrollPaneSetVerticalScrollPosition utf8
-- luacheck: read_globals guiScrollPaneGetVerticalScrollPosition guiStaticImageLoadImage
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
-- item uname -> render in client/icons/ (tools/recipe_icons.py)
local ICONS = loadModule("client/icons.lua")
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local L = lang.text

local W, H = 840, 580
local LIST_X, LIST_Y, LIST_W = 14, 98, 320
local LIST_H = H - LIST_Y - 54
local ROW_H, ROW_ICON = 40, 32
local ROW_W = LIST_W - 22 -- leaves the scroll bar its room
local PANE_X = LIST_X + LIST_W + 14
local PANE_W = W - PANE_X - 14
local HEAD_ICON, HEAD_H = 64, 84
local BODY_W = PANE_W - 24
local TILE_W, TILE_H, TILE_ICON, TILE_GAP = 80, 98, 48, 6
local LINE_H = 16
local SOLID = "client/white.png" -- tinted through ImageColours for every panel and highlight
local WHITE, GREY, RED = { 255, 255, 255 }, { 170, 170, 170 }, { 255, 110, 110 }
local GREEN, YELLOW = { 110, 220, 110 }, { 255, 255, 0 }
-- panel tints, AARRGGBB
local BG = {
    row = "00000000",
    rowHover = "22FFFFFF",
    rowSelected = "40FFFFFF",
    head = "50000000",
    tile = "60000000",
    have = "7028A028",
    missing = "70B42828",
}
-- each method's colour: its tag in the list, its filter and the selected recipe's name
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
    tool = "tool",
    place = "place",
    ready = "You carry everything it takes.",
    short = "You are missing %d of %d.",
    hint = "Click an item with a recipe of its own to see how it is made.",
    steps = "How to make it:",
    none = "No recipe matches.",
}
-- lang:end

local lower = utf8 and utf8.lower or string.lower
local win = nil -- the open window's elements and state
local filter, query = "all", "" -- kept between openings while the resource runs

local function itemName(uname)
    local name = lang.itemName(uname)
    return (name and name ~= "") and name or uname
end

local function iconPath(uname)
    local file = uname and ICONS[uname]
    return file and ("client/icons/" .. file) or nil
end

local function tint(el, argb)
    guiSetProperty(el, "ImageColours", string.format("tl:%s tr:%s bl:%s br:%s", argb, argb, argb, argb))
end

local function solid(x, y, w, h, argb, parent)
    local el = guiCreateStaticImage(x, y, w, h, SOLID, false, parent)
    tint(el, argb)
    return el
end

local function hex(c, alpha)
    return string.format("%s%02X%02X%02X", alpha or "FF", c[1], c[2], c[3])
end

local function label(x, y, w, h, text, parent, font, colour)
    local l = guiCreateLabel(x, y, w, h, text, false, parent)
    guiSetFont(l, font or "default-normal")
    local c = colour or WHITE
    guiLabelSetColor(l, c[1], c[2], c[3])
    return l
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

-- the places a recipe is made at (a machine, a cooker) are not carried, so they are never ticked
local function isPlace(r)
    return r.kind == "machines" or r.kind == "cooking"
end

-- what the recipe asks to carry: { uname, count, keep, tool }, the tool last
local function needs(r)
    local out = {}
    for _, ing in ipairs(r.ingredients) do
        out[#out + 1] = { uname = ing.uname, count = ing.count, keep = ing.keep }
    end
    if r.tool then
        out[#out + 1] = { uname = r.tool, count = 1, tool = true, place = isPlace(r) }
    end
    return out
end

-- true / false against what the character carries, nil while the server has not answered or for a place
local function has(need, total)
    if not win.carried or need.place then
        return nil
    end
    return (win.carried[need.uname] or 0) >= total[need.uname]
end

-- the detail pane: rebuilt for every recipe shown
local function clearBody()
    for _, el in ipairs(win.body) do
        if isElement(el) then
            destroyElement(el)
        end
    end
    win.body, win.y = {}, 0
end

local function keep(el)
    win.body[#win.body + 1] = el
    return el
end

-- a wrapped line of text at win.y
local function addLine(text, colour, indent, font)
    indent = indent or 0
    local width = BODY_W - indent
    local l = keep(label(indent, win.y, width, LINE_H, text, win.pane, font, colour))
    guiLabelSetHorizontalAlign(l, "left", true)
    local rows = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        guiSetText(l, part ~= "" and part or " ")
        rows = rows + math.max(1, math.ceil((guiLabelGetTextExtent(l) + 4) / width))
    end
    guiSetText(l, text)
    guiSetSize(l, width, rows * LINE_H + 2, false)
    win.y = win.y + rows * LINE_H + 2
end

local function gap(n)
    win.y = win.y + (n or 8)
end

local selectRecipe -- forward: selecting a recipe from a tile click

-- one item tile: its picture, how many, its name, a tag (kept, tool, place) and a green or red panel
local function addTile(x, y, need, ok)
    local bg =
        keep(solid(x, y, TILE_W, TILE_H, ok == true and BG.have or ok == false and BG.missing or BG.tile, win.pane))
    local path = iconPath(need.uname)
    if path then
        guiCreateStaticImage((TILE_W - TILE_ICON) / 2, 8, TILE_ICON, TILE_ICON, path, false, bg)
    end
    if need.count > 1 then
        local n = label(TILE_W - 34, 2, 30, 16, need.count .. "x", bg, "default-bold-small", YELLOW)
        guiLabelSetHorizontalAlign(n, "right")
    end
    local tag = need.place and TEXTS.place or need.tool and TEXTS.tool or need.keep and TEXTS.kept
    if tag then
        label(4, 2, TILE_W - 36, 16, L(tag), bg, "default-small", GREY)
    end
    local recipe = win.makes[need.uname]
    local name =
        label(2, TILE_ICON + 12, TILE_W - 4, TILE_H - TILE_ICON - 14, itemName(need.uname), bg, "default-small")
    guiLabelSetHorizontalAlign(name, "center", true)
    if recipe then
        -- an item with a recipe of its own is named in that recipe's colour and opens it
        local c = COLOURS[recipe.kind] or WHITE
        guiLabelSetColor(name, c[1], c[2], c[3])
        addEventHandler("onClientGUIClick", bg, function()
            selectRecipe(recipe, true)
        end)
    end
    return recipe ~= nil
end

local function stepText(step)
    local args = {}
    for i, a in ipairs(step.args) do
        args[i] = type(a) == "table" and itemName(a.item) or a
    end
    return lang.format(step.fmt, unpack(args))
end

-- the header: the result's picture, its name in the method's colour, the method and whether you carry it all
local function showHead(r)
    local h = win.head
    local path = r and iconPath(r.result.uname)
    if path then
        guiStaticImageLoadImage(h.icon, path)
    end
    guiSetVisible(h.icon, path ~= nil)
    guiSetVisible(h.panel, r ~= nil)
    if not r then
        return
    end
    local c = COLOURS[r.kind] or WHITE
    local count = r.result.count or 1
    guiSetText(h.name, (count > 1 and (count .. "x ") or "") .. itemName(r.result.uname))
    guiLabelSetColor(h.name, c[1], c[2], c[3])
    guiSetText(h.kind, L(KIND_NAMES[r.kind] or r.kind))
    local list, total = needs(r), {}
    for _, n in ipairs(list) do
        total[n.uname] = (total[n.uname] or 0) + n.count
    end
    local carryable, missing = 0, 0
    for _, n in ipairs(list) do
        local ok = has(n, total)
        if ok ~= nil then
            carryable = carryable + 1
            missing = missing + (ok and 0 or 1)
        end
    end
    if not win.carried or carryable == 0 then
        guiSetText(h.status, "")
    elseif missing == 0 then
        guiSetText(h.status, L(TEXTS.ready))
        guiLabelSetColor(h.status, GREEN[1], GREEN[2], GREEN[3])
    else
        guiSetText(h.status, lang.format(TEXTS.short, missing, carryable))
        guiLabelSetColor(h.status, RED[1], RED[2], RED[3])
    end
end

local function showRecipe(r)
    clearBody()
    showHead(r)
    if not r then
        guiSetVisible(win.pane, false)
        return
    end
    guiSetVisible(win.pane, true)
    addLine(L(TEXTS.need), YELLOW, 0, "default-bold-small")
    gap(4)
    local list, total = needs(r), {}
    for _, n in ipairs(list) do
        total[n.uname] = (total[n.uname] or 0) + n.count
    end
    local perRow = math.max(1, math.floor((BODY_W + TILE_GAP) / (TILE_W + TILE_GAP)))
    local linked = false
    for i, n in ipairs(list) do
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        linked = addTile(col * (TILE_W + TILE_GAP), win.y + row * (TILE_H + TILE_GAP), n, has(n, total)) or linked
    end
    win.y = win.y + math.ceil(#list / perRow) * (TILE_H + TILE_GAP)
    if linked then
        addLine(L(TEXTS.hint), GREY, 0, "default-small")
    end
    gap(10)
    addLine(L(TEXTS.steps), YELLOW, 0, "default-bold-small")
    gap(2)
    local steps = craft.steps(r)
    if steps then
        for i, step in ipairs(steps) do
            addLine(i .. ".  " .. stepText(step), WHITE, 8)
        end
    elseif r.instructions then
        addLine(r.instructions, WHITE, 8)
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

-- the list: one row per recipe, built once and shown or hidden by the filter and the search
local function paintRow(row)
    local argb = row.r == win.selected and BG.rowSelected or row == win.hover and BG.rowHover or BG.row
    tint(row.bg, argb)
    guiSetVisible(row.accent, row.r == win.selected)
end

local function scrollTo(row)
    local content, view = #win.shown * ROW_H, LIST_H
    if content <= view then
        return
    end
    local y = row.y
    local top = guiScrollPaneGetVerticalScrollPosition(win.list) / 100 * (content - view)
    if y < top then
        top = y
    elseif y + ROW_H > top + view then
        top = y + ROW_H - view
    else
        return
    end
    guiScrollPaneSetVerticalScrollPosition(win.list, top / (content - view) * 100)
end

selectRecipe = function(r, reveal)
    if reveal and r and not matches(r) then
        -- opened from a tile: clear what hides it
        query, filter = "", "all"
        win.quiet = true
        guiSetText(win.edit, "")
        win.quiet = false
        win.setFilter("all")
    end
    local old = win.selected
    win.selected = r
    for _, row in ipairs(win.rows) do
        if row.r == r or row.r == old then
            paintRow(row)
            if row.r == r and row.visible then
                scrollTo(row)
            end
        end
    end
    showRecipe(r)
end

local function refill()
    win.shown = {}
    local y = 0
    for _, row in ipairs(win.rows) do
        row.visible = matches(row.r)
        guiSetVisible(row.bg, row.visible)
        -- a hidden row still counts towards the pane's scroll height, so it waits at the top
        guiSetPosition(row.bg, 0, row.visible and y or 0, false)
        if row.visible then
            row.y = y
            y = y + ROW_H
            win.shown[#win.shown + 1] = row
        end
    end
    guiSetVisible(win.empty, #win.shown == 0)
    guiScrollPaneSetVerticalScrollPosition(win.list, 0)
    local keepIt = false
    for _, row in ipairs(win.shown) do
        keepIt = keepIt or row.r == win.selected
    end
    selectRecipe(keepIt and win.selected or (win.shown[1] and win.shown[1].r))
end

-- arrow keys walk the shown rows
local function step(delta)
    for i, row in ipairs(win.shown) do
        if row.r == win.selected then
            local nextRow = win.shown[math.max(1, math.min(#win.shown, i + delta))]
            return selectRecipe(nextRow.r)
        end
    end
end

local function buildRow(r)
    local row = { r = r, y = 0 }
    local c = COLOURS[r.kind] or WHITE
    row.bg = solid(0, 0, ROW_W, ROW_H, BG.row, win.list)
    row.accent = solid(0, 0, 3, ROW_H, hex(c), row.bg)
    guiSetVisible(row.accent, false)
    local path = iconPath(r.result.uname)
    if path then
        guiCreateStaticImage(8, (ROW_H - ROW_ICON) / 2, ROW_ICON, ROW_ICON, path, false, row.bg)
    end
    local x = 8 + ROW_ICON + 8
    label(x, 4, ROW_W - x - 4, 18, itemName(r.result.uname), row.bg, "default-bold-small")
    label(x, 21, ROW_W - x - 4, 16, L(KIND_NAMES[r.kind] or r.kind), row.bg, "default-small", c)
    -- the row's pieces pass their clicks and hovers up to it
    addEventHandler("onClientGUIClick", row.bg, function()
        selectRecipe(r)
    end)
    addEventHandler("onClientMouseEnter", row.bg, function()
        local old = win.hover
        win.hover = row
        if old and old ~= row then
            paintRow(old)
        end
        paintRow(row)
    end)
    addEventHandler("onClientMouseLeave", row.bg, function()
        -- moving onto the row's own icon or text enters it again straight after
        if win.hover == row then
            win.hover = nil
            paintRow(row)
        end
    end)
    return row
end

-- CEGUI gives the wheel to the picture or text under the cursor, not the scroll pane, so the panes scroll by hand
local WHEEL_PX = ROW_H * 3
local function wheelScroll(pane, contentH, viewH)
    addEventHandler("onClientMouseWheel", pane, function(dir)
        local range = contentH() - viewH
        if range <= 0 then
            return
        end
        local top = guiScrollPaneGetVerticalScrollPosition(pane) / 100 * range - dir * WHEEL_PX
        guiScrollPaneSetVerticalScrollPosition(pane, math.max(0, math.min(range, top)) / range * 100)
    end)
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
    win = { window = window, body = {}, y = 0, rows = {}, shown = {}, filters = {}, inputMode = guiGetInputMode() }
    win.recipes = allRecipes()
    win.search, win.makes = {}, {}
    for _, r in ipairs(win.recipes) do
        win.search[r] = searchText(r)
        win.makes[r.result.uname] = win.makes[r.result.uname] or r
    end

    label(14, 32, 70, 22, L(TEXTS.search), window, "default-bold-small")
    win.edit = guiCreateEdit(84, 28, LIST_W - 70, 26, query, false, window)

    -- the filters: All and one per method
    local kinds = { "all" }
    for _, k in ipairs(KINDS) do
        kinds[#kinds + 1] = k
    end
    local bw = math.floor((W - 28) / #kinds)
    for i, k in ipairs(kinds) do
        local button = guiCreateButton(
            14 + (i - 1) * bw,
            62,
            bw - 4,
            26,
            L(k == "all" and TEXTS.all or KIND_NAMES[k]),
            false,
            window
        )
        win.filters[k] = button
        addEventHandler("onClientGUIClick", button, function()
            win.setFilter(k)
        end, false)
    end
    win.setFilter = function(kind)
        filter = kind
        -- the active filter's text in its method colour (yellow for All), the others grey
        for k, button in pairs(win.filters) do
            local c = hex(k == kind and (COLOURS[k] or YELLOW) or GREY)
            guiSetProperty(button, "NormalTextColour", c)
            guiSetProperty(button, "HoverTextColour", c)
        end
        refill()
    end

    solid(LIST_X, LIST_Y, LIST_W, LIST_H, BG.head, window)
    win.list = guiCreateScrollPane(LIST_X, LIST_Y, LIST_W, LIST_H, false, window)
    win.empty = label(LIST_X + 10, LIST_Y + 10, LIST_W - 20, 20, L(TEXTS.none), window, "default-normal", GREY)
    for _, r in ipairs(win.recipes) do
        win.rows[#win.rows + 1] = buildRow(r)
    end

    local head = { panel = solid(PANE_X, LIST_Y, PANE_W, HEAD_H - 8, BG.head, window) }
    head.icon = guiCreateStaticImage(8, (HEAD_H - 8 - HEAD_ICON) / 2, HEAD_ICON, HEAD_ICON, SOLID, false, head.panel)
    local tx = 8 + HEAD_ICON + 12
    head.name = label(tx, 8, PANE_W - tx - 8, 20, "", head.panel, "default-bold-small")
    head.kind = label(tx, 28, PANE_W - tx - 8, 18, "", head.panel, "default-normal", GREY)
    head.status = label(tx, 48, PANE_W - tx - 8, 18, "", head.panel, "default-normal")
    win.head = head
    win.pane = guiCreateScrollPane(PANE_X, LIST_Y + HEAD_H, PANE_W, LIST_H - HEAD_H, false, window)

    wheelScroll(win.list, function()
        return #win.shown * ROW_H
    end, LIST_H)
    wheelScroll(win.pane, function()
        return win.y
    end, LIST_H - HEAD_H)

    local closeButton = guiCreateButton((W - 120) / 2, H - 44, 120, 30, L("Close"), false, window)
    addEventHandler("onClientGUIClick", closeButton, close, false)
    addEventHandler("onClientGUIChanged", win.edit, function()
        if win.quiet then
            return
        end
        query = lower(guiGetText(win.edit) or "")
        refill()
    end, false)
    win.onKey = function(key, press)
        if not press then
            return
        end
        if key == "escape" then
            cancelEvent()
            close()
        elseif key == "arrow_d" or key == "arrow_u" then
            step(key == "arrow_d" and 1 or -1)
        end
    end
    addEventHandler("onClientKey", root, win.onKey)
    showCursor(true)
    guiSetInputMode("no_binds")
    guiBringToFront(win.edit)
    guiEditSetCaretIndex(win.edit, utf8 and utf8.len(query) or #query)
    win.setFilter(filter)
    triggerServerEvent("recipeCarriedRequested", localPlayer)
end

-- what the character carries, for the green and red tiles
addEventHandler("recipeCarriedSent", localPlayer, function(counts)
    if not win then
        return
    end
    win.carried = type(counts) == "table" and counts or {}
    showRecipe(win.selected)
end)

addCommandHandler("recipes", open)
addCommandHandler("recipe", open)
addEventHandler("onClientResourceStop", resourceRoot, close)
