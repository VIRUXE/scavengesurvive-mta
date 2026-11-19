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

-- one table: a header bar, the column titles, then rows { name, me, cells = { { text, colour }, ... } }; the value
-- columns (heads) sit at the right, CELL_W units each
local CELL_W = 58
local function table_(x, y, w, title, heads, rows, rowH, nRows)
    local pad = 4 * s
    local cellW = CELL_W * s
    dxDrawRectangle(x, y, w, rowH, COL.head)
    text(title, x + pad, y, x + w - pad, y + rowH, COL.text, 0.55)
    y = y + rowH
    dxDrawRectangle(x, y, w, rowH * (nRows + 1), COL.list)
    local nameRight = x + w - pad - cellW * #heads
    text(lang.text("Name"), x + pad + 14 * s, y, nameRight, y + rowH, COL.dim, 0.5)
    for k, head in ipairs(heads) do
        local right = x + w - pad - cellW * (#heads - k)
        text(head, right - cellW, y, right, y + rowH, COL.dim, 0.5, nil, "right")
    end
    for i, r in ipairs(rows) do
        local ry = y + rowH * i
        if r.me then
            dxDrawRectangle(x, ry, w, rowH, COL.mine)
        end
        text(tostring(i) .. ".", x + pad, ry, x + pad + 12 * s, ry + rowH, COL.dim, 0.5, nil, "right")
        text(r.name, x + pad + 14 * s, ry, nameRight, ry + rowH, COL.text, 0.55)
        for k, cell in ipairs(r.cells) do
            local right = x + w - pad - cellW * (#heads - k)
            text(cell[1], right - cellW, ry, right, ry + rowH, cell[2], 0.55, nil, "right")
        end
    end
end

local function onlineRows(elapsed)
    local out = {}
    for _, r in ipairs(data.online) do
        local cell
        if r.state == "alive" then
            -- paused (staff on duty): shown, not ticking
            cell = { logic.duration(logic.secondsAt(r.s, r.run, elapsed)), r.run and COL.running or COL.resting }
        elseif r.state == "dead" then
            cell = { lang.text("Dead"), COL.dead }
        else
            cell = { "-", COL.dim }
        end
        out[#out + 1] = { name = r.name, me = r.me, cells = { cell } }
    end
    return out
end

-- best life, then the current one: green while it counts, pale when its player is offline or on duty
local function topRows(elapsed)
    local out = {}
    for _, r in ipairs(data.top) do
        local best = { logic.duration(logic.secondsAt(r.best, r.bestRun, elapsed)), COL.text }
        local cur
        if r.cur then
            cur = { logic.duration(logic.secondsAt(r.cur, r.curRun, elapsed)), r.curRun and COL.running or COL.resting }
        else
            cur = { lang.text("Dead"), COL.dead }
        end
        out[#out + 1] = { name = r.name, me = r.me, cells = { best, cur } }
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
    local leftW, rightW, gap, margin = 170 * s, 230 * s, 8 * s, 8 * s
    local w = leftW + rightW + gap + margin * 2
    local titleH = 22 * s
    local h = margin + titleH + rowH * (nRows + 2) + margin
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
    table_(x + margin, cy, leftW, lang.text("Online now"), { lang.text("Time alive") }, online, rowH, nRows)
    local heads = { lang.text("Best"), lang.text("Current") }
    table_(x + margin + leftW + gap, cy, rightW, lang.text("Top 10 personal bests"), heads, top, rowH, nRows)
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
