-- The /help window in CEGUI: big topic buttons on the left, the chosen topic on the right as short numbered steps
-- (or a table for the keys and the commands), Back / Next to read it like a booklet. MTA's client core owns a
-- console command called "help" and runs it before any script sees the line, so /help typed in the chat never
-- reaches the server: onClientCoreCommand opens the window instead. The server's /help (console, rcon) sends
-- helpOpened. Content and texts live in shared/logic/help.lua.
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local help = loadFile("shared/logic/help.lua", "=chat/help.lua")
local chatLogic = loadFile("shared/logic/chat.lua", "=chat/chat.lua")
local tips = loadFile("shared/logic/tips.lua", "=chat/tips.lua").TIPS
local T = help.T
local TOPICS = help.TOPICS

local BODY_FONT, BUTTON_FONT, HEAD_FONT = "clear-normal", "default-bold-small", "sa-header"
local PAD, MENU_W, BUTTON_H, BUTTON_GAP, FOOT_H = 12, 210, 34, 5, 44
local YELLOW, WHITE, GREY = { 255, 200, 60 }, { 255, 255, 255 }, { 170, 170, 170 }
local TIP_COLOUR, WARN_COLOUR = { 120, 225, 120 }, { 255, 120, 95 }
local SELECTED, NORMAL = "FFFFC83C", "FFFFFFFF"
-- keys the help names that are not item binds: the chat key, and the vehicle radio that chat binds itself to R
local FIXED_KEYS = { radio = "r" }
-- hud's default item keys (hud/client/keys.lua DEFAULTS): putaway stays unbound on purpose (hud answers Y itself,
-- MTA's team chat holds the key), so an unbound command shows its default
local DEFAULT_KEYS =
    { interact = "f", dropitem = "n", putaway = "y", inventory = "h", reloadweapon = "r", chat = "t", enginebay = "e" }

local ui = nil -- the open window: { window, buttons, content = {elements}, page, inputMode }
local lastPage = 1

local ruler = guiCreateLabel(0, 0, 10, 10, "", false)
guiSetVisible(ruler, false)

local function textWidth(text, font)
    guiSetFont(ruler, font)
    guiSetText(ruler, text)
    return guiLabelGetTextExtent(ruler)
end

local function fontHeight(font)
    guiSetFont(ruler, font)
    return guiLabelGetFontHeight(ruler)
end

-- the number of lines text takes word-wrapped at width (greedy, word by word, as CEGUI wraps)
local function wrappedLines(text, font, width)
    local lines, current = 1, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = current == "" and word or current .. " " .. word
        if current ~= "" and textWidth(candidate, font) > width then
            lines = lines + 1
            current = word
        else
            current = candidate
        end
    end
    return lines
end

local function keyOf(command)
    if FIXED_KEYS[command] then
        return FIXED_KEYS[command]
    end
    local bound = getKeyBoundToCommand(command == "chat" and "chatbox" or command)
    return bound or DEFAULT_KEYS[command]
end

local function text(english)
    return help.fill(lang.text(english), keyOf)
end

local function label(parent, x, y, w, h, str, font, colour, wrap)
    local l = guiCreateLabel(x, y, w, h, str, false, parent)
    guiSetFont(l, font)
    guiLabelSetColor(l, colour[1], colour[2], colour[3])
    guiLabelSetHorizontalAlign(l, "left", wrap == true)
    return l
end

local function clearContent()
    for _, el in ipairs(ui.content) do
        if isElement(el) then
            destroyElement(el)
        end
    end
    ui.content = {}
end

-- numbered steps and the topic's tip or warning in a scroll pane
local function showSteps(topic, x, y, w, h)
    local pane = guiCreateScrollPane(x, y, w, h, false, ui.window)
    ui.content[#ui.content + 1] = pane
    local lineH = fontHeight(BODY_FONT) + 1
    local numW = 30
    local textW = w - numW - 24 -- room for the vertical scrollbar
    local cy = 2
    for i, step in ipairs(topic.steps or {}) do
        local str = text(step)
        local lines = wrappedLines(str, BODY_FONT, textW - 4)
        label(pane, 0, cy, numW, lineH, i .. ".", BODY_FONT, YELLOW)
        label(pane, numW, cy, textW, lines * lineH + 2, str, BODY_FONT, WHITE, true)
        cy = cy + lines * lineH + 10
    end
    local note, colour, prefix = topic.tip, TIP_COLOUR, T.tipLabel
    if topic.warn then
        note, colour, prefix = topic.warn, WARN_COLOUR, T.warnLabel
    end
    if note then
        cy = cy + 6
        local str = lang.text(prefix) .. ":  " .. text(note)
        local lines = wrappedLines(str, BODY_FONT, w - 28)
        label(pane, 0, cy, w - 24, lines * lineH + 2, str, BODY_FONT, colour, true)
    end
end

-- a two-column table; rows = { { left, right, colour = "#RRGGBB" } }, the left column yellow unless a colour is set
local function showTable(columns, rows, x, y, w, h)
    local grid = guiCreateGridList(x, y, w, h, false, ui.window)
    ui.content[#ui.content + 1] = grid
    guiSetFont(grid, BODY_FONT)
    guiGridListSetSortingEnabled(grid, false)
    guiGridListSetSelectionMode(grid, 2) -- nothing to select: it is a read-only table
    guiGridListAddColumn(grid, columns[1], 0.3)
    guiGridListAddColumn(grid, columns[2], 0.64)
    for _, row in ipairs(rows) do
        local r = guiGridListAddRow(grid)
        local hex = row.colour and row.colour:match("^#(%x%x%x%x%x%x)$")
        local rowColour = hex
            and { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
        for col = 1, 2 do
            local colour = rowColour or (col == 1 and YELLOW or WHITE)
            guiGridListSetItemText(grid, r, col, tostring(row[col] or ""), false, false)
            guiGridListSetItemColor(grid, r, col, colour[1], colour[2], colour[3])
        end
    end
    return y + h
end

local function commandRows()
    local code = lang.code()
    local upstream = chatLogic.helpWindow(exports.data:t(code, "GENCOMDHELP"), lang.text).rows
    return help.commandRows(upstream, lang.text)
end

local showPage

local function setPage(page)
    page = math.max(1, math.min(#TOPICS, page))
    ui.page, lastPage = page, page
    clearContent()
    for i, button in ipairs(ui.buttons) do
        local colour = i == page and SELECTED or NORMAL
        guiSetProperty(button, "NormalTextColour", colour)
        guiSetProperty(button, "HoverTextColour", colour)
    end
    local topic = TOPICS[page]
    local x = PAD + MENU_W + PAD
    local w = ui.w - x - PAD
    local headH = fontHeight(HEAD_FONT) + 4
    local head = label(ui.window, x, 30, w - 90, headH, lang.text(topic.title), HEAD_FONT, YELLOW)
    local count = label(ui.window, ui.w - PAD - 90, 34, 90, 20, page .. " / " .. #TOPICS, BUTTON_FONT, GREY)
    guiLabelSetHorizontalAlign(count, "right")
    ui.content[#ui.content + 1] = head
    ui.content[#ui.content + 1] = count
    local y = 30 + headH + 8
    local h = ui.h - y - FOOT_H - PAD
    if topic.kind == "keys" then
        local tableH = h - 70
        showTable({ lang.text(T.key), lang.text(T.action) }, help.keyRows(keyOf, lang.text), x, y, w, tableH)
        local str = lang.text(T.tipLabel) .. ":  " .. text(topic.tip)
        local lineH = fontHeight(BODY_FONT) + 1
        local lines = wrappedLines(str, BODY_FONT, w - 4)
        ui.content[#ui.content + 1] =
            label(ui.window, x, y + tableH + 8, w, lines * lineH + 2, str, BODY_FONT, TIP_COLOUR, true)
    elseif topic.kind == "commands" then
        showTable({ lang.text(T.command), lang.text(T.action) }, commandRows(), x, y, w, h)
    else
        showSteps(topic, x, y, w, h)
    end
    guiSetEnabled(ui.backButton, page > 1)
    guiSetEnabled(ui.nextButton, page < #TOPICS)
end
showPage = setPage

local function close()
    if not ui then
        return
    end
    if isElement(ui.window) then
        destroyElement(ui.window)
    end
    removeEventHandler("onClientKey", root, ui.onKey)
    showCursor(false)
    guiSetInputMode(ui.inputMode)
    ui = nil
end

local function open(page)
    if ui then
        return showPage(page or ui.page)
    end
    local sw, sh = guiGetScreenSize()
    local w, h = math.min(980, sw - 40), math.min(660, sh - 40)
    local window = guiCreateWindow((sw - w) / 2, (sh - h) / 2, w, h, lang.text(T.title), false)
    guiWindowSetSizable(window, false)
    guiWindowSetMovable(window, true)
    guiSetAlpha(window, 1) -- opaque: the text must not compete with the world behind it
    ui = { window = window, w = w, h = h, buttons = {}, content = {}, inputMode = guiGetInputMode() }

    -- the topic buttons, squeezed when the screen is short
    local menuTop, menuBottom = 32, h - FOOT_H - PAD
    local step = math.min(BUTTON_H + BUTTON_GAP, (menuBottom - menuTop) / #TOPICS)
    for i, topic in ipairs(TOPICS) do
        local b = guiCreateButton(
            PAD,
            menuTop + (i - 1) * step,
            MENU_W,
            step - BUTTON_GAP,
            lang.text(topic.title),
            false,
            window
        )
        guiSetFont(b, BUTTON_FONT)
        addEventHandler("onClientGUIClick", b, function(button)
            if button == "left" then
                showPage(i)
            end
        end, false)
        ui.buttons[i] = b
    end

    local footY = h - FOOT_H
    label(window, PAD, footY + 4, MENU_W + 40, 36, lang.text(T.hint), "default-small", GREY, true)
    local x = PAD + MENU_W + PAD
    ui.backButton = guiCreateButton(x, footY, 120, 34, lang.text(T.back), false, window)
    ui.nextButton = guiCreateButton(x + 130, footY, 120, 34, lang.text(T.next), false, window)
    local closeButton = guiCreateButton(w - PAD - 120, footY, 120, 34, lang.text(T.close), false, window)
    for _, b in ipairs({ ui.backButton, ui.nextButton, closeButton }) do
        guiSetFont(b, BUTTON_FONT)
        guiSetProperty(b, "NormalTextColour", NORMAL)
        guiSetProperty(b, "HoverTextColour", SELECTED)
    end
    addEventHandler("onClientGUIClick", ui.backButton, function()
        showPage(ui.page - 1)
    end, false)
    addEventHandler("onClientGUIClick", ui.nextButton, function()
        showPage(ui.page + 1)
    end, false)
    addEventHandler("onClientGUIClick", closeButton, close, false)

    -- Escape closes; the arrow keys turn the pages
    ui.onKey = function(key, press)
        if not press or not ui then
            return
        end
        if key == "escape" then
            cancelEvent()
            close()
        elseif key == "arrow_r" or key == "arrow_l" then
            showPage(ui.page + (key == "arrow_r" and 1 or -1))
        end
    end
    addEventHandler("onClientKey", root, ui.onKey)
    showCursor(true)
    guiSetInputMode("no_binds")
    showPage(page or lastPage)
end

local function toggle()
    if ui then
        close()
    else
        open()
    end
end

addEventHandler("onClientCoreCommand", root, function(command)
    if command == "help" then
        toggle()
    end
end)

addEventHandler("helpOpened", localPlayer, function()
    open()
end)

-- A rotating tip from the server (server/main.lua): its index in shared/logic/tips.lua, shown in this player's
-- language with the keys they have bound, as the help window names them.
addEventHandler("chatTipSent", localPlayer, function(index)
    local tip = tips[tonumber(index)]
    if tip then
        outputChatBox(" >  #33CCFF" .. text(tip), 255, 255, 0, true)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
