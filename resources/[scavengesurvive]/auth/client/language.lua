-- The language window (CEGUI), shown before the login or register dialog to every player whose account has no
-- language yet. The list is the codes the server sends (authLanguageOffered), each under its own name; Continue
-- (or a double click) answers with authLanguageChosen and the server goes on to the dialog in that language.
-- GUI functions that postdate the generated luacheck lists:
-- luacheck: read_globals guiCreateGridList guiGridListSetSortingEnabled guiGridListAddColumn guiGridListAddRow
-- luacheck: read_globals guiGridListSetItemText guiGridListSetItemData guiGridListGetItemData
-- luacheck: read_globals guiGridListGetSelectedItem guiGridListSetSelectedItem guiGetInputMode
-- luacheck: read_globals guiLabelSetHorizontalAlign
local NAMES = {
    en = "English",
    es = "Español",
    fr = "Français",
    pt = "Português (Portugal)",
    ptbr = "Português (Brasil)",
    ru = "Русский",
    ro = "Română",
    id = "Bahasa Indonesia",
    bhs = "Bosanski / Hrvatski / Srpski",
    cs = "Čeština",
}
local WIN_W, WIN_H = 340, 360
local win

local function close()
    if not win then
        return
    end
    local w = win
    win = nil
    removeEventHandler("onClientKey", root, w.onKey)
    if isElement(w.window) then
        destroyElement(w.window)
    end
    guiSetInputMode(w.inputMode)
    showCursor(false)
end

local function choose()
    if not win then
        return
    end
    local row = guiGridListGetSelectedItem(win.grid)
    local code = row and row >= 0 and guiGridListGetItemData(win.grid, row, 1)
    if not code then
        return
    end
    close()
    triggerServerEvent("authLanguageChosen", localPlayer, code)
end

addEventHandler("authLanguageOffered", root, function(codes)
    close()
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - WIN_W) / 2, (sh - WIN_H) / 2, WIN_W, WIN_H, "Language", false)
    guiWindowSetSizable(window, false)
    local label = guiCreateLabel(10, 28, WIN_W - 20, 20, "Choose your language / Escolhe o teu idioma", false, window)
    guiLabelSetHorizontalAlign(label, "center")
    local grid = guiCreateGridList(10, 54, WIN_W - 20, WIN_H - 112, false, window)
    guiGridListSetSortingEnabled(grid, false)
    guiGridListAddColumn(grid, "Language", 0.9)
    for _, code in ipairs(codes) do
        local row = guiGridListAddRow(grid)
        guiGridListSetItemText(grid, row, 1, NAMES[code] or code, false, false)
        guiGridListSetItemData(grid, row, 1, code)
    end
    guiGridListSetSelectedItem(grid, 0, 1)
    local button = guiCreateButton((WIN_W - 120) / 2, WIN_H - 42, 120, 28, "Continue", false, window)
    local function onKey(key, press)
        if press and (key == "enter" or key == "num_enter") then
            cancelEvent()
            choose()
        end
    end
    win = { window = window, grid = grid, inputMode = guiGetInputMode(), onKey = onKey }
    addEventHandler("onClientKey", root, onKey)
    addEventHandler("onClientGUIClick", button, choose, false)
    addEventHandler("onClientGUIDoubleClick", grid, choose, false)
    showCursor(true)
    guiSetInputMode("no_binds")
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
