-- /weather with no arguments: a CEGUI window to pick a weather, who gets it (just you, one player, everyone) and for
-- how long. Nothing is forever: when the time is up the world weather comes back. Enter applies, Escape closes.
local W, H = 420, 470
local DURATIONS = { { 5, "5 minutes" }, { 15, "15 minutes" }, { 30, "30 minutes" }, { 60, "1 hour" } }
local win = nil -- { window, grid, who, dur, status, result, types, targets }

local function statusLine(st)
    local names = {}
    for _, t in ipairs(st.types) do
        names[t.id] = t.name
    end
    local text = string.format("World: %s (%d)", names[st.current] or "?", st.current)
    if st.lockedMs > 0 then
        text = text .. string.format(", held %d min", math.ceil(st.lockedMs / 60000))
    end
    if st.own then
        text = text
            .. string.format(
                " | Yours: %s (%d), %d min left",
                names[st.own] or "?",
                st.own,
                math.ceil(st.ownMs / 60000)
            )
    end
    return text
end

local function setResult(text, ok)
    guiSetText(win.result, text)
    if ok then
        guiLabelSetColor(win.result, 180, 255, 180)
    else
        guiLabelSetColor(win.result, 255, 160, 160)
    end
end

local function close()
    if not win then
        return
    end
    if isElement(win.window) then
        destroyElement(win.window)
    end
    win = nil
    guiSetInputMode("allow_binds")
    showCursor(false)
end

local function target()
    local i = guiComboBoxGetSelected(win.who)
    return win.targets[(i or 0) + 1] or "me"
end

local function send(action)
    local row = guiGridListGetSelectedItem(win.grid)
    local id = row and row >= 0 and win.types[row + 1].id or nil
    if action == "set" and not id then
        return setResult("pick a weather", false)
    end
    local d = DURATIONS[(guiComboBoxGetSelected(win.dur) or 1) + 1]
    triggerServerEvent("devWeatherSetRequested", localPlayer, action, id, target(), d and d[1] or 15)
end

local function open(st)
    if win and isElement(win.window) then
        return guiBringToFront(win.grid)
    end
    if win then -- the window was destroyed from outside: forget it and make a new one
        win = nil
        guiSetInputMode("allow_binds")
        showCursor(false)
    end
    local sw, sh = guiGetScreenSize()
    local window = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, "Weather", false)
    guiWindowSetSizable(window, false)
    local status = guiCreateLabel(12, 28, W - 24, 20, "", false, window)
    local grid = guiCreateGridList(12, 54, W - 24, 280, false, window)
    guiGridListAddColumn(grid, "ID", 0.15)
    guiGridListAddColumn(grid, "Name", 0.8)
    guiCreateLabel(12, 346, 50, 20, "Who", false, window)
    local who = guiCreateComboBox(70, 342, W - 82, 110, "", false, window)
    guiCreateLabel(12, 376, 50, 20, "For", false, window)
    local dur = guiCreateComboBox(70, 372, W - 82, 110, "", false, window)
    local result = guiCreateLabel(12, 404, W - 24, 20, "Enter applies, Esc closes", false, window)
    local apply = guiCreateButton(12, 430, 120, 28, "Apply", false, window)
    local reset = guiCreateButton(W / 2 - 60, 430, 120, 28, "Reset", false, window)
    local closeButton = guiCreateButton(W - 132, 430, 120, 28, "Close", false, window)
    win = {
        window = window,
        grid = grid,
        who = who,
        dur = dur,
        status = status,
        result = result,
        types = st.types,
        targets = { "me", "all" },
    }
    guiComboBoxAddItem(who, "Just me")
    guiComboBoxAddItem(who, "Everyone")
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= localPlayer then
            guiComboBoxAddItem(who, getPlayerName(p))
            win.targets[#win.targets + 1] = p
        end
    end
    guiComboBoxSetSelected(who, 0)
    for _, d in ipairs(DURATIONS) do
        guiComboBoxAddItem(dur, d[2])
    end
    guiComboBoxSetSelected(dur, 1)
    guiSetText(status, statusLine(st))
    for i, t in ipairs(st.types) do
        local r = guiGridListAddRow(grid)
        guiGridListSetItemText(grid, r, 1, tostring(t.id), false, false)
        guiGridListSetItemText(grid, r, 2, t.name, false, false)
        if t.id == (st.own or st.current) then
            guiGridListSetSelectedItem(grid, i - 1, 1)
        end
    end
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    guiBringToFront(grid)
    addEventHandler("onClientGUIDoubleClick", grid, function()
        send("set")
    end, false)
    addEventHandler("onClientGUIClick", apply, function()
        send("set")
    end, false)
    addEventHandler("onClientGUIClick", reset, function()
        send("reset")
    end, false)
    addEventHandler("onClientGUIClick", closeButton, close, false)
end

addEventHandler("devWeatherWindowOpened", root, open)

addEventHandler("devWeatherAnswered", root, function(ok, text, st)
    if not win or not isElement(win.window) then
        return
    end
    setResult(text, ok)
    if st then
        guiSetText(win.status, statusLine(st))
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not win or not press then
        return
    end
    if key == "escape" then
        close()
        cancelEvent()
    elseif key == "enter" or key == "num_enter" then
        send("set")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
