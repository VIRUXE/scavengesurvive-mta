-- /additem with no arguments: a CEGUI window whose edit box filters every item type as you type. MTA gives scripts
-- no access to the chat box's input, so the completion list lives in a window of its own. Up/Down move the
-- selection, Tab completes the edit, Enter (or a double click) spawns the selected row, Escape closes.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local logic = loadFile("shared/logic/item_picker.lua", "=dev/item_picker_logic.lua")

local W, H = 480, 440
local picker = nil -- { window, edit, grid, spec, values, status, rows }

local function itemDef(uname)
    return exports.data:itemType(uname)
end

local function selectedRow()
    local r = guiGridListGetSelectedItem(picker.grid)
    return r and r >= 0 and picker.rows[r + 1] or nil
end

local function setStatus(text, ok)
    guiSetText(picker.status, text)
    if ok then
        guiLabelSetColor(picker.status, 180, 255, 180)
    else
        guiLabelSetColor(picker.status, 255, 160, 160)
    end
end

local function refill()
    guiGridListClear(picker.grid)
    picker.rows = logic.filter(exports.data:itemTypes(), itemDef, guiGetText(picker.edit), logic.LIMIT)
    for _, row in ipairs(picker.rows) do
        local r = guiGridListAddRow(picker.grid)
        guiGridListSetItemText(picker.grid, r, 1, row.name, false, false)
        guiGridListSetItemText(picker.grid, r, 2, row.uname, false, false)
        guiGridListSetItemText(picker.grid, r, 3, row.category, false, false)
        guiGridListSetItemText(picker.grid, r, 4, tostring(row.id), false, false)
    end
    if #picker.rows > 0 then
        guiGridListSetSelectedItem(picker.grid, 0, 1)
    end
end

local function close()
    if not picker then
        return
    end
    destroyElement(picker.window)
    picker = nil
    guiSetInputMode("allow_binds")
    showCursor(false)
end

local function spawn()
    local row = selectedRow()
    if not row then
        return setStatus("no item selected", false)
    end
    local spec, values = guiGetText(picker.spec), guiGetText(picker.values)
    setStatus("spawning " .. row.uname .. "...", true)
    triggerServerEvent("devItemSpawnRequested", localPlayer, row.uname, spec, values)
end

local function move(delta)
    local count = #picker.rows
    if count == 0 then
        return
    end
    local cur = guiGridListGetSelectedItem(picker.grid)
    local target = math.max(0, math.min(count - 1, (cur and cur >= 0 and cur or 0) + delta))
    guiGridListSetSelectedItem(picker.grid, target, 1)
end

local function open()
    if picker then
        return guiBringToFront(picker.edit)
    end
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, "Spawn item", false)
    guiWindowSetSizable(window, false)
    local edit = guiCreateEdit(12, 30, W - 24, 26, "", false, window)
    local grid = guiCreateGridList(12, 62, W - 24, 270, false, window)
    guiGridListAddColumn(grid, "Name", 0.38)
    guiGridListAddColumn(grid, "uname", 0.30)
    guiGridListAddColumn(grid, "Category", 0.2)
    guiGridListAddColumn(grid, "ID", 0.1)
    guiCreateLabel(12, 342, 110, 20, "Extradata spec", false, window)
    local spec = guiCreateEdit(120, 340, 80, 24, "", false, window)
    guiCreateLabel(210, 342, 50, 20, "Values", false, window)
    local values = guiCreateEdit(262, 340, W - 274, 24, "", false, window)
    local status = guiCreateLabel(12, 374, W - 24, 20, "Type to filter, Enter spawns, Esc closes", false, window)
    local spawnButton = guiCreateButton(12, 400, 120, 28, "Spawn", false, window)
    local closeButton = guiCreateButton(W - 132, 400, 120, 28, "Close", false, window)
    picker = { window = window, edit = edit, grid = grid, spec = spec, values = values, status = status, rows = {} }
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    guiBringToFront(edit)
    guiEditSetCaretIndex(edit, 0)
    refill()
    addEventHandler("onClientGUIChanged", edit, refill, false)
    addEventHandler("onClientGUIDoubleClick", grid, spawn, false)
    addEventHandler("onClientGUIClick", spawnButton, spawn, false)
    addEventHandler("onClientGUIClick", closeButton, close, false)
end

addEventHandler("devItemPickerOpened", root, open)

addEventHandler("devItemSpawnAnswered", root, function(ok, text)
    if picker then
        setStatus(text, ok)
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not picker or not press then
        return
    end
    if key == "escape" then
        close()
        cancelEvent()
    elseif key == "arrow_u" then
        move(-1)
    elseif key == "arrow_d" then
        move(1)
    elseif key == "enter" or key == "num_enter" then
        spawn()
    elseif key == "tab" then
        local row = selectedRow()
        if row then
            guiSetText(picker.edit, row.uname)
            guiEditSetCaretIndex(picker.edit, #row.uname)
            refill()
        end
        cancelEvent()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
