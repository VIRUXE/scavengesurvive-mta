-- /additem with no arguments: a CEGUI window whose edit box filters every item type as you type. MTA gives scripts
-- no access to the chat box's input, so the completion list lives in a window of its own. Up/Down move the
-- selection, Tab completes the edit, Enter (or a double click) spawns the selected row, Escape closes. An item with
-- contents (a liquid, a gun's magazine, a gas bottle, ...) gets a panel of fields under the list (shared/logic/
-- item_contents.lua), filled at "Full"; Empty zeroes the numbers, Random spawns what a loot spawn would give.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local logic = loadFile("shared/logic/item_picker.lua", "=dev/item_picker_logic.lua")
local contents = loadFile("shared/logic/item_contents.lua", "=dev/item_contents_logic.lua")

local W, H = 480, 440
local MAX_FIELDS = 3
local FIELD_Y, FIELD_STEP = 268, 28
local picker = nil -- { window, edit, grid, status, rows, medical, fields, controls, panel, panelFor }

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

local function destroyPanel()
    for _, e in ipairs(picker.panel) do
        if isElement(e) then
            destroyElement(e)
        end
    end
    picker.panel, picker.controls, picker.fields, picker.panelFor = {}, {}, {}, nil
end

local function setField(f, value)
    local c = picker.controls[f.key]
    if f.kind == "choice" then
        for i, choice in ipairs(f.choices) do
            if choice == value then
                guiComboBoxSetSelected(c, i - 1)
            end
        end
    else
        guiSetText(c, tostring(value))
    end
end

local function applyPreset(which)
    local values = contents.preset(picker.fields, which)
    for _, f in ipairs(picker.fields) do
        if values[f.key] ~= nil then
            setField(f, values[f.key])
        end
    end
end

local function fieldValues()
    local values = {}
    for _, f in ipairs(picker.fields) do
        local c = picker.controls[f.key]
        if f.kind == "choice" then
            local i = guiComboBoxGetSelected(c)
            values[f.key] = i and i >= 0 and guiComboBoxGetItemText(c, i) or nil
        else
            values[f.key] = guiGetText(c)
        end
    end
    return values
end

-- Rebuilds the contents panel for the selected row (nothing when it is already the one shown).
local function buildContents()
    local row = selectedRow()
    local uname = row and row.uname
    if picker.panelFor == uname then
        return
    end
    destroyPanel()
    picker.panelFor = uname
    local def = uname and itemDef(uname)
    if not def then
        return
    end
    local cal = def.categoryData and def.categoryData.calibre
    local ctx = { ammoTypes = cal and exports.data:ammoTypesForCalibre(cal) or {}, medical = picker.medical }
    local fields = contents.fields(def, ctx)
    if #fields == 0 then
        return
    end
    local window, panel = picker.window, picker.panel
    for i = 1, math.min(#fields, MAX_FIELDS) do
        local f, y = fields[i], FIELD_Y + (i - 1) * FIELD_STEP
        picker.fields[i] = f
        panel[#panel + 1] = guiCreateLabel(12, y + 3, 100, 20, f.label, false, window)
        if f.kind == "choice" then
            local combo = guiCreateComboBox(120, y, 200, 24 + 20 * math.min(#f.choices, 5), "", false, window)
            for _, choice in ipairs(f.choices) do
                guiComboBoxAddItem(combo, choice)
            end
            picker.controls[f.key] = combo
            panel[#panel + 1] = combo
        else
            local edit = guiCreateEdit(120, y, 90, 24, "", false, window)
            picker.controls[f.key] = edit
            panel[#panel + 1] = edit
            panel[#panel + 1] =
                guiCreateLabel(218, y + 3, 120, 20, string.format("%g to %g", f.min, f.max), false, window)
        end
    end
    local y = FIELD_Y + MAX_FIELDS * FIELD_STEP
    for i, button in ipairs({ { "Full", "full" }, { "Empty", "empty" } }) do
        local b = guiCreateButton(120 + (i - 1) * 76, y - 4, 70, 22, button[1], false, window)
        addEventHandler("onClientGUIClick", b, function()
            applyPreset(button[2])
        end, false)
        panel[#panel + 1] = b
    end
    applyPreset("full")
end

local function spawn(mode)
    local row = selectedRow()
    if not row then
        return setStatus("no item selected", false)
    end
    buildContents()
    setStatus("spawning " .. row.uname .. "...", true)
    triggerServerEvent("devItemSpawnRequested", localPlayer, row.uname, mode, mode == "random" and {} or fieldValues())
end

local function move(delta)
    local count = #picker.rows
    if count == 0 then
        return
    end
    local cur = guiGridListGetSelectedItem(picker.grid)
    local target = math.max(0, math.min(count - 1, (cur and cur >= 0 and cur or 0) + delta))
    guiGridListSetSelectedItem(picker.grid, target, 1)
    buildContents()
end

local function open(preselect, medical)
    if picker then
        return guiBringToFront(picker.edit)
    end
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, "Spawn item", false)
    guiWindowSetSizable(window, false)
    local edit = guiCreateEdit(12, 30, W - 24, 26, preselect or "", false, window)
    local grid = guiCreateGridList(12, 62, W - 24, 190, false, window)
    guiGridListAddColumn(grid, "Name", 0.38)
    guiGridListAddColumn(grid, "uname", 0.30)
    guiGridListAddColumn(grid, "Category", 0.2)
    guiGridListAddColumn(grid, "ID", 0.1)
    local status = guiCreateLabel(12, 376, W - 24, 20, "Type to filter, Enter spawns, Esc closes", false, window)
    local spawnButton = guiCreateButton(12, 400, 120, 28, "Spawn", false, window)
    local randomButton = guiCreateButton(140, 400, 120, 28, "Spawn random", false, window)
    local closeButton = guiCreateButton(W - 132, 400, 120, 28, "Close", false, window)
    picker = {
        window = window,
        edit = edit,
        grid = grid,
        status = status,
        rows = {},
        medical = type(medical) == "table" and medical or {},
        fields = {},
        controls = {},
        panel = {},
    }
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    guiBringToFront(edit)
    guiEditSetCaretIndex(edit, #(preselect or ""))
    refill()
    buildContents()
    addEventHandler("onClientGUIChanged", edit, function()
        refill()
        buildContents()
    end, false)
    addEventHandler("onClientGUIClick", grid, buildContents, false)
    addEventHandler("onClientGUIDoubleClick", grid, function()
        spawn("values")
    end, false)
    addEventHandler("onClientGUIClick", spawnButton, function()
        spawn("values")
    end, false)
    addEventHandler("onClientGUIClick", randomButton, function()
        spawn("random")
    end, false)
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
        spawn("values")
    elseif key == "tab" then
        local row = selectedRow()
        if row then
            guiSetText(picker.edit, row.uname)
            guiEditSetCaretIndex(picker.edit, #row.uname)
            refill()
            buildContents()
        end
        cancelEvent()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
