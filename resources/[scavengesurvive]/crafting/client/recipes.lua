-- /recipes: a CEGUI recipe browser (upstream core/player/recipes.pwn). Tabs for combination, construction and
-- workbench recipes, each a list of results with the tool and ingredients of the selected one, and a help tab.
-- GUI functions that postdate the generated luacheck lists:
-- luacheck: read_globals guiCreateTabPanel guiCreateTab guiCreateGridList guiGridListSetSortingEnabled
-- luacheck: read_globals guiGridListAddColumn guiGridListAddRow guiGridListSetItemText guiCreateScrollPane
-- luacheck: read_globals guiGridListGetSelectedItem guiGridListSetSelectedItem guiGetInputMode
-- luacheck: read_globals guiLabelSetColor guiLabelSetHorizontalAlign
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
local FONT, WIN_W, WIN_H = "default-normal", 620, 424
local YELLOW, WHITE, GREEN, BLUE = { 255, 255, 0 }, { 255, 255, 255 }, { 51, 170, 51 }, { 51, 204, 255 }
local TABS = { { "Combination", "combine" }, { "Construction", "ground" }, { "Workbench", "workbench" } }

-- upstream Dialog_ShowCraftHelp, with the port's controls: { colour, text } lines, "" for a gap
local HELP = {
    { WHITE, "Crafting is a way to create new items from existing items." },
    { WHITE, "There are three ways to combine items in Scavenge and Survive:" },
    { WHITE, "" },
    { YELLOW, "In Inventory Screens (Aka: Crafting or Combining):" },
    { WHITE, "While viewing your inventory or a container (vehicle trunk, box, bag, etc)" },
    { WHITE, "Select 'Combine' from the item options" },
    { WHITE, "Go back and open the options for another item" },
    { WHITE, "Select 'Combine with ...' to combine the items together" },
    { WHITE, "If a recipe requires more than two items, just repeat." },
    { WHITE, "" },
    { GREEN, "On The Ground (Aka: Constructing):" },
    { WHITE, "Place all the ingredient items on the ground" },
    { WHITE, "Equip the 'Tool' item specified in the recipe page" },
    { WHITE, "Hold the Interact key while close to the ingredients" },
    { WHITE, "" },
    { BLUE, "At a Workbench:" },
    { WHITE, "Place the all ingredient items in the workbench (The workbench acts like a box)" },
    { WHITE, "Equip the 'Tool' item specified in the recipe page" },
    { WHITE, "Hold the Interact key while standing at the workbench" },
}

local win = nil

local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function itemName(uname)
    return lang.itemName(uname)
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

local function label(parent, x, y, w, h, text, colour)
    local l = guiCreateLabel(x, y, w, h, text, false, parent)
    guiSetFont(l, FONT)
    guiLabelSetHorizontalAlign(l, "left", true)
    guiLabelSetColor(l, colour[1], colour[2], colour[3])
    return l
end

-- the text of a recipe's detail pane: the tool, the ingredients and the time
local function detailText(r)
    local lines = {}
    if r.tool then
        lines[#lines + 1] = "Tool: " .. itemName(r.tool)
    end
    lines[#lines + 1] = "Ingredients:"
    for _, line in ipairs(craft.ingredientLines(r, itemName)) do
        lines[#lines + 1] = "    " .. line
    end
    local ms = r.kind == "ground" and r.buildTime or r.kind == "workbench" and craft.workbenchTime(r)
    if ms then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Takes about %.1f s.", ms / 1000)
    end
    if r.removalTool then
        lines[#lines + 1] = "Can be taken down again with a " .. itemName(r.removalTool) .. "."
    end
    return table.concat(lines, "\n")
end

local function recipeTab(panel, name, kind)
    local tab = guiCreateTab(name, panel)
    local recipes = craft.ofKind(kind)
    local grid = guiCreateGridList(6, 6, 220, 292, false, tab)
    guiGridListSetSortingEnabled(grid, false)
    guiGridListAddColumn(grid, "Recipe", 0.85)
    for _, r in ipairs(recipes) do
        local row = guiGridListAddRow(grid)
        guiGridListSetItemText(grid, row, 1, itemName(r.result.uname), false, false)
    end
    local title = label(tab, 238, 8, 340, 20, "", YELLOW)
    local body = label(tab, 238, 32, 340, 260, "", WHITE)
    local function show()
        local row = guiGridListGetSelectedItem(grid)
        local r = recipes[(row or -1) + 1]
        guiSetText(title, r and itemName(r.result.uname) or "")
        guiSetText(body, r and detailText(r) or "")
    end
    addEventHandler("onClientGUIClick", grid, show, false)
    guiGridListSetSelectedItem(grid, 0, 1)
    show()
end

local function helpTab(panel)
    local tab = guiCreateTab("Help", panel)
    local pane = guiCreateScrollPane(6, 6, 578, 292, false, tab)
    local y = 4
    for _, line in ipairs(HELP) do
        if line[2] == "" then
            y = y + 8
        else
            local rows = math.ceil(#line[2] * 6.5 / 540)
            label(pane, 4, y, 548, rows * 15 + 2, line[2], line[1])
            y = y + rows * 15 + 2
        end
    end
end

local function open()
    close()
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - WIN_W) / 2, (sh - WIN_H) / 2, WIN_W, WIN_H, "Recipes", false)
    guiWindowSetSizable(window, false)
    local panel = guiCreateTabPanel(10, 28, WIN_W - 20, 340, false, window)
    for _, t in ipairs(TABS) do
        recipeTab(panel, t[1], t[2])
    end
    helpTab(panel)
    local button = guiCreateButton((WIN_W - 110) / 2, WIN_H - 42, 110, 28, "Close", false, window)
    local function onKey(key, press)
        if press and (key == "escape" or key == "enter" or key == "num_enter") then
            cancelEvent()
            close()
        end
    end
    win = { window = window, inputMode = guiGetInputMode(), onKey = onKey }
    addEventHandler("onClientKey", root, onKey)
    addEventHandler("onClientGUIClick", button, close, false)
    showCursor(true)
    guiSetInputMode("no_binds")
end

addCommandHandler("recipes", open)
addEventHandler("onClientResourceStop", resourceRoot, close)
