-- Survival ranking panel, held open with Tab: on the left every online player with their current life's time alive,
-- on the right the longest lives ever. Times count only while their player is online (server/main.lua); a running
-- one keeps ticking here between the server's snapshots. Drawn with dx in the ui kit's dialog colours.
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local logic = loadFile("shared/logic/ranking.lua", "=ranking/ranking.lua")
logic.tr = lang.text

local KEY = "tab"
local REQUEST_MS = 5000
local COL = {
    box = tocolor(0, 0, 0, 215),
    list = tocolor(0, 0, 0, 240),
    head = tocolor(139, 26, 30, 255), -- the ui list's selected red
    mine = tocolor(139, 26, 30, 110),
    text = tocolor(255, 255, 255, 255),
    dim = tocolor(170, 170, 170, 255),
    running = tocolor(0x33, 0xFF, 0x33, 255),
    resting = tocolor(120, 190, 120, 255), -- alive, player offline
    dead = tocolor(200, 70, 70, 255),
}
local FONT, TITLE_FONT = "default-bold", "bankgothic"

local sw, sh = guiGetScreenSize()
local s = sh / 480 -- the ui canvas scale: one unit of a 640x480 screen
local shown = false
local data = nil -- last rankingSynced payload
local receivedAt = 0
local requestTimer = nil

local function request()
    triggerServerEvent("rankingRequested", localPlayer)
end

local function text(str, x1, y1, x2, y2, colour, scale, font, align)
    dxDrawText(str, x1, y1, x2, y2, colour, scale * s, scale * s, font or FONT, align or "left", "center", true)
end

-- one column: a header bar, the column titles, then rows { name, time, colour, me }
local function column(x, y, w, title, rows, rowH, nRows)
    local pad = 4 * s
    dxDrawRectangle(x, y, w, rowH, COL.head)
    text(title, x + pad, y, x + w - pad, y + rowH, COL.text, 0.55)
    y = y + rowH
    dxDrawRectangle(x, y, w, rowH * (nRows + 1), COL.list)
    text(lang.text("Name"), x + pad + 14 * s, y, x + w, y + rowH, COL.dim, 0.5)
    text(lang.text("Time alive"), x, y, x + w - pad, y + rowH, COL.dim, 0.5, nil, "right")
    for i, r in ipairs(rows) do
        local ry = y + rowH * i
        if r.me then
            dxDrawRectangle(x, ry, w, rowH, COL.mine)
        end
        text(tostring(i) .. ".", x + pad, ry, x + pad + 12 * s, ry + rowH, COL.dim, 0.5, nil, "right")
        text(r.name, x + pad + 14 * s, ry, x + w - 70 * s, ry + rowH, COL.text, 0.55)
        text(r.time, x, ry, x + w - pad, ry + rowH, r.colour, 0.55, nil, "right")
    end
end

local function onlineRows(elapsed)
    local out = {}
    for _, r in ipairs(data.online) do
        local row = { name = r.name, me = r.me }
        if r.state == "alive" then
            row.time = logic.duration(logic.secondsAt(r, elapsed))
            row.colour = r.run and COL.running or COL.resting -- paused: staff on duty
        elseif r.state == "dead" then
            row.time, row.colour = lang.text("Dead"), COL.dead
        else
            row.time, row.colour = "-", COL.dim
        end
        out[#out + 1] = row
    end
    return out
end

local function topRows(elapsed)
    local out = {}
    for _, r in ipairs(data.top) do
        local colour = r.run and COL.running or (r.alive and COL.resting or COL.text)
        out[#out + 1] = {
            name = r.name,
            me = r.me,
            time = logic.duration(logic.secondsAt(r, elapsed)),
            colour = colour,
        }
    end
    return out
end

local function render()
    if not data then
        return
    end
    local elapsed = getTickCount() - receivedAt
    local online, top = onlineRows(elapsed), topRows(elapsed)
    local rowH = 11 * s
    local nRows = math.max(#online, logic.TOP)
    local colW, gap, margin = 190 * s, 8 * s, 8 * s
    local w = colW * 2 + gap + margin * 2
    local titleH = 22 * s
    local h = margin + titleH + rowH * (nRows + 2) + rowH * 1.5 + margin
    local x, y = (sw - w) / 2, math.max(4 * s, (sh - h) / 2)
    dxDrawRectangle(x, y, w, h, COL.box)
    text(
        lang.text("Survival ranking"),
        x + margin,
        y + margin,
        x + w - margin,
        y + margin + titleH,
        COL.text,
        0.6,
        TITLE_FONT
    )
    local count = string.format("%d/%d", data.players or #data.online, data.max or 0)
    text(count, x + margin, y + margin, x + w - margin, y + margin + titleH, COL.dim, 0.6, nil, "right")
    local cy = y + margin + titleH
    column(x + margin, cy, colW, lang.text("Online now"), online, rowH, nRows)
    column(x + margin + colW + gap, cy, colW, lang.text("Longest lives"), top, rowH, nRows)
    local fy = cy + rowH * (nRows + 2) + rowH * 0.25
    text(
        lang.text("Time alive counts only while online. Green: still alive."),
        x + margin,
        fy,
        x + w - margin,
        fy + rowH,
        COL.dim,
        0.5
    )
end

local function show()
    if shown or isChatBoxInputActive() or isConsoleActive() then
        return
    end
    shown = true
    request()
    requestTimer = setTimer(request, REQUEST_MS, 0)
    addEventHandler("onClientRender", root, render)
end

local function hide()
    if not shown then
        return
    end
    shown = false
    if requestTimer and isTimer(requestTimer) then
        killTimer(requestTimer)
    end
    requestTimer = nil
    removeEventHandler("onClientRender", root, render)
end

addEventHandler("rankingSynced", resourceRoot, function(payload)
    if type(payload) ~= "table" or type(payload.online) ~= "table" or type(payload.top) ~= "table" then
        return
    end
    data, receivedAt = payload, getTickCount()
end)

bindKey(KEY, "down", show)
bindKey(KEY, "up", hide)
