-- Client half of /replay (docs/superpowers/specs/2026-11-23-replay-design.md). The server streams a session
-- (Appendix A: actors, vehicles, events, world items) and this file runs the clock and ties the parts together:
-- client/actors.lua (ghost peds and vehicles), client/world.lua (the items and defences as they were, through the
-- items resource), client/camera.lua, client/ui.lua (CEGUI window + dx timeline). While a session runs the live
-- items, vehicles and players are hidden for this client only; everything is restored on stop or resource stop.
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=replay/" .. path))()
end

local interp = loadFile("shared/logic/interp.lua")
local timeline = loadFile("shared/logic/timeline.lua")
local actors = loadFile("client/actors.lua")({ interp = interp })
local world = loadFile("client/world.lua")({ timeline = timeline })
local camera = loadFile("client/camera.lua")()

local KIND_COLORS = {
    item = { 90, 170, 255 },
    building = { 255, 160, 60 },
    vehicle = { 120, 220, 120 },
    death = { 255, 70, 70 },
    shot = { 255, 230, 90 },
    weapon = { 255, 230, 90 },
    container = { 90, 220, 220 },
    chat = { 235, 235, 235 },
    staff = { 200, 130, 255 },
    character = { 255, 120, 200 },
}
local DEFAULT_COLOR = { 190, 190, 190 }
local SEEK_LEAD_MS = 1000 -- jumping to an event lands this long before it
local WORLD_TICK_MS = 200
local UI_TICK_MS = 250

local session = nil -- the running replay, nil when none
local ui

local function kindColor(kind)
    local custom = session and session.kinds and session.kinds[kind]
    local c = custom and custom.color
    if type(c) == "table" and #c >= 3 then
        return c[1], c[2], c[3]
    elseif type(c) == "string" then
        local r, g, b = c:match("^#?(%x%x)(%x%x)(%x%x)$")
        if r then
            return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
        end
    end
    local prefix = tostring(kind):match("^(%w+)")
    local d = KIND_COLORS[prefix] or DEFAULT_COLOR
    return d[1], d[2], d[3]
end

local function wallText(t)
    if not session then
        return "--:--:--"
    end
    local ts = (session.from or 0) + (session.tz or 0) + math.floor(t / 1000)
    local rt = getRealTime(ts, false)
    return string.format("%02d:%02d:%02d", rt.hour, rt.minute, rt.second)
end

-- ---------------------------------------------------------------- hiding what is live
-- Live vehicles and players are made invisible for this client only; items go through items:setWorldHidden.
local hiddenLive = {} -- element -> { alpha, collisions }

local function hideLiveElement(el)
    if el == localPlayer or actors.isGhost(el) or hiddenLive[el] then
        return
    end
    local isVehicle = getElementType(el) == "vehicle"
    hiddenLive[el] = { alpha = getElementAlpha(el), collisions = isVehicle and getElementCollisionsEnabled(el) }
    setElementAlpha(el, 0)
    if isVehicle then
        setElementCollisionsEnabled(el, false)
    end
end

local function hideLiveAll()
    for _, kind in ipairs({ "vehicle", "player" }) do
        for _, el in ipairs(getElementsByType(kind)) do
            hideLiveElement(el)
        end
    end
end

local function restoreLive()
    for el, old in pairs(hiddenLive) do
        if isElement(el) then
            setElementAlpha(el, old.alpha or 255)
            if old.collisions then
                setElementCollisionsEnabled(el, true)
            end
        end
    end
    hiddenLive = {}
end

addEventHandler("onClientElementStreamIn", root, function()
    if session and (getElementType(source) == "vehicle" or getElementType(source) == "player") then
        hideLiveElement(source)
    end
end)

-- ---------------------------------------------------------------- session data
local function sortedInsert(list, items, key)
    for _, it in ipairs(items) do
        list[#list + 1] = it
    end
    table.sort(list, function(a, b)
        return (a[key] or 0) < (b[key] or 0)
    end)
end

local function recompute()
    local tracks = {}
    for _, a in pairs(session.actors) do
        tracks[#tracks + 1] = a.samples
    end
    for _, v in pairs(session.vehicles) do
        tracks[#tracks + 1] = v.samples
    end
    session.clock.idle = timeline.idleSpans(tracks, session.events, session.clock.duration)
    ui.setEvents(session.events)
    local subjects = {}
    for char, a in pairs(session.actors) do
        subjects[#subjects + 1] = { char = char, name = a.name or tostring(char) }
    end
    table.sort(subjects, function(a, b)
        return a.name < b.name
    end)
    ui.setSubjects(subjects, session.focus)
end

-- merges a chunk's parts into the session (Appendix A)
local function merge(part)
    for char, a in pairs(part.actors or {}) do
        char = tonumber(char) or char
        local have = session.actors[char]
        if not have then
            session.actors[char] = { name = a.name, skin = a.skin, role = a.role, samples = {} }
            have = session.actors[char]
        end
        sortedInsert(have.samples, a.samples or {}, "t")
        if a.role == "subject" and not session.focus then
            session.focus = char
        end
    end
    for key, v in pairs(part.vehicles or {}) do
        local have = session.vehicles[key]
        if not have then
            session.vehicles[key] = { id = v.id, model = v.model, colors = v.colors, samples = {} }
            have = session.vehicles[key]
        end
        sortedInsert(have.samples, v.samples or {}, "t")
    end
    if part.events then
        sortedInsert(session.events, part.events, "t")
    end
    if part.world and part.world.items then
        world.add(part.world.items)
    end
end

-- ---------------------------------------------------------------- clock and actions
local lastTick = 0
local lastWorldTick, lastUiTick = 0, 0
local lastSeekSent = 0

local function seek(t, notify)
    timeline.seek(session.clock, t)
    lastWorldTick = 0
    if notify and not session.debug and getTickCount() - lastSeekSent > 350 then
        lastSeekSent = getTickCount()
        triggerServerEvent("replaySeekRequested", localPlayer, session.id, math.floor(session.clock.t))
    end
end

local function parseTime(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then
        return nil
    end
    local sign, rest = text:match("^([%+%-])(%d+)$")
    if sign then
        return session.clock.t + (sign == "-" and -1 or 1) * tonumber(rest) * 1000
    end
    local h, m, s = text:match("^(%d+):(%d+):?(%d*)$")
    if h then
        local want = tonumber(h) * 3600 + tonumber(m) * 60 + (tonumber(s) or 0)
        local base = getRealTime((session.from or 0) + (session.tz or 0), false)
        local baseSec = base.hour * 3600 + base.minute * 60 + base.second
        local delta = want - baseSec
        if delta < 0 then
            delta = delta + 86400
        end
        return delta * 1000
    end
    local n = tonumber(text)
    return n and n * 1000 or nil
end

local actions = {}

function actions.playPause()
    local c = session.clock
    if not c.playing and c.t >= c.duration then
        seek(0)
    end
    c.playing = not c.playing
end

function actions.faster()
    timeline.faster(session.clock)
end

function actions.slower()
    timeline.slower(session.clock)
end

function actions.setCamera(mode)
    camera.setMode(mode)
end

function actions.setSkipIdle(on)
    session.clock.skipIdle = on and true or false
end

function actions.gotoTime(text)
    local t = parseTime(text)
    if t then
        seek(t, true)
    end
end

function actions.setSubject(char)
    session.focus = char
    if not session.debug then
        triggerServerEvent("replaySubjectSwitchRequested", localPlayer, session.id, char)
    end
end

function actions.jumpTo(t)
    seek(t - SEEK_LEAD_MS, true)
end

function actions.scrub(f)
    seek(f * session.clock.duration, true)
end

local stopSession

function actions.stop()
    if session.debug then
        stopSession("stopped")
    else
        triggerServerEvent("replayStopRequested", localPlayer, session.id)
    end
end

local function stepKey(sign)
    return function()
        if session and not ui.cursorOn() then
            seek(session.clock.t + sign * (getKeyState("lshift") and 10000 or 1000), true)
        end
    end
end

local function eventKey(forward)
    return function()
        if not session then
            return
        end
        local c = session.clock
        local t
        if forward then
            t = timeline.nextEventTime(session.events, c.t + SEEK_LEAD_MS)
        else
            t = timeline.prevEventTime(session.events, c.t + SEEK_LEAD_MS)
        end
        if t then
            seek(t - SEEK_LEAD_MS, true)
        end
    end
end

local KEYS = {
    {
        "space",
        function()
            actions.playPause()
        end,
    },
    {
        "]",
        function()
            actions.faster()
        end,
    },
    {
        "[",
        function()
            actions.slower()
        end,
    },
    { "arrow_r", stepKey(1) },
    { "arrow_l", stepKey(-1) },
    { "pgup", eventKey(false) },
    { "pgdn", eventKey(true) },
    {
        "c",
        function()
            camera.cycle()
        end,
    },
    {
        "k",
        function()
            actions.setSkipIdle(not session.clock.skipIdle)
        end,
    },
    {
        "tab",
        function()
            ui.toggleCursor()
        end,
    },
    {
        "backspace",
        function()
            actions.stop()
        end,
    },
}

local function bindKeys(on)
    for _, k in ipairs(KEYS) do
        if on then
            bindKey(k[1], "down", k[2])
        else
            unbindKey(k[1], "down", k[2])
        end
    end
end

-- ---------------------------------------------------------------- frame loop
local function focusPlace()
    local x, y, z, rz, int = actors.where(session.focus)
    if not x then
        -- not on the map yet: the first sample of the focused actor
        local a = session.actors[session.focus]
        local first = a and a.samples[1]
        if first then
            return first.x, first.y, first.z, first.rz or 0, first.int or 0
        end
    end
    return x, y, z, rz, int
end

local function drawTrail(t)
    for _, a in pairs(session.actors) do
        local samples = a.samples
        local i1 = interp.find(samples, math.max(0, t - 45000))
        local i2 = interp.find(samples, t)
        if i2 >= 1 then
            i1 = math.max(1, i1)
            local step = math.max(1, math.floor((i2 - i1) / 160))
            local color = a.role == "subject" and tocolor(255, 120, 90, 200) or tocolor(190, 190, 190, 140)
            local prev
            for i = i1, i2, step do
                local s = samples[i]
                if prev and (s.t - prev.t) < 30000 and s.int == prev.int then
                    dxDrawLine3D(prev.x, prev.y, prev.z - 0.9, s.x, s.y, s.z - 0.9, color, 3)
                end
                prev = s
            end
        end
    end
end

local function drawMarkers(t)
    local events = session.events
    local i = timeline.nextIndex(events, t - 4000)
    local drawn = 0
    while events[i] and events[i].t <= t + 1500 and drawn < 40 do
        local e = events[i]
        if e.x and e.y and e.z then
            local age = t - e.t
            local fade = age < 0 and 1 + age / 1500 or math.max(0, 1 - age / 4000)
            local r, g, b = kindColor(e.kind)
            local a = math.floor(255 * math.max(0.1, fade))
            dxDrawLine3D(e.x, e.y, e.z - 0.8, e.x, e.y, e.z + 1.6, tocolor(r, g, b, a), 3)
            local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 1.8, 0.1, false)
            if sx then
                local text = tostring(e.label or e.kind)
                dxDrawText(
                    text,
                    sx + 1,
                    sy + 1,
                    sx + 1,
                    sy + 1,
                    tocolor(0, 0, 0, a),
                    1,
                    "default-bold",
                    "center",
                    "bottom"
                )
                dxDrawText(text, sx, sy, sx, sy, tocolor(r, g, b, a), 1, "default-bold", "center", "bottom")
            end
            drawn = drawn + 1
        end
        i = i + 1
    end
end

addEventHandler("onClientPreRender", root, function()
    if not session then
        return
    end
    local now = getTickCount()
    local dt = math.min(250, now - lastTick)
    lastTick = now
    local c = session.clock
    timeline.advance(c, dt)
    actors.update(c.t, session)
    local fx, fy, fz, frz, fint = focusPlace()
    camera.update(fx, fy, fz, frz, fint)
    if now - lastWorldTick >= WORLD_TICK_MS then
        lastWorldTick = now
        local cx, cy = camera.position()
        world.update(c.t, cx ~= 0 and cx or fx, cx ~= 0 and cy or fy)
    end
    if now - lastUiTick >= UI_TICK_MS then
        lastUiTick = now
        ui.refresh(c, wallText(c.t), c.playing, timeline.speed(c))
    end
end)

addEventHandler("onClientRender", root, function()
    if not session then
        return
    end
    local c = session.clock
    drawTrail(c.t)
    drawMarkers(c.t)
    actors.drawTracers()
    world.drawLabels(c.t)
    actors.drawTags(session.focus)
    local name = session.subjectName or "?"
    ui.drawBanner(name .. "  " .. wallText(c.t) .. (c.playing and "" or "  (paused)"))
    ui.drawTimeline(c, session.events, c.idle)
end)

-- ---------------------------------------------------------------- start / stop
ui = loadFile("client/ui.lua")({
    timeline = timeline,
    actions = actions,
    kindColor = kindColor,
    wall = wallText,
    onCursor = function(on)
        camera.setCursorVisible(on)
    end,
})
-- the actions table is read by ui at call time (session is a upvalue set below)

local function startSession(info, debug)
    if session then
        stopSession("restarted")
    end
    local duration = math.max(1000, ((info.to or 0) - (info.from or 0)) * 1000)
    session = {
        id = info.id,
        from = info.from or 0,
        to = info.to or 0,
        tz = info.tz or 0,
        kinds = info.kinds or {},
        subjectName = info.subject and info.subject.name,
        actors = {},
        vehicles = {},
        events = {},
        clock = timeline.newClock(duration),
        focus = info.subject and info.subject.char_id or nil,
        debug = debug or false,
        origin = info.origin,
    }
    session.saved = {
        frozen = isElementFrozen(localPlayer),
        input = guiGetInputMode(),
    }
    exports.items:setWorldHidden(true)
    hideLiveAll()
    toggleAllControls(false, true, false)
    setElementFrozen(localPlayer, true)
    ui.open(session)
    bindKeys(true)
    local o = info.origin or {}
    camera.start(o.x or 0, o.y or 0, o.z or 0)
    lastTick = getTickCount()
    session.clock.playing = true
end

function stopSession(reason)
    if not session then
        return
    end
    local s = session
    session = nil
    bindKeys(false)
    ui.close()
    camera.stop()
    actors.clear()
    world.clear()
    exports.items:destroyWorldRows()
    exports.items:setWorldHidden(false)
    restoreLive()
    toggleAllControls(true, true, true)
    setElementFrozen(localPlayer, s.saved.frozen or false)
    outputDebugString("[replay] session ended (" .. tostring(reason) .. ")")
end

addEventHandler("replaySessionStarted", root, function(info)
    startSession(info, false)
end)

addEventHandler("replayChunkReceived", root, function(id, _, _, part)
    if not session or session.id ~= id or type(part) ~= "table" then
        return
    end
    merge(part)
    recompute()
end)

addEventHandler("replaySessionEnded", root, function(id, reason)
    if session and session.id == id then
        stopSession(reason or "ended")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopSession("resource stopped")
end)

-- the items resource restarted: its world builder lost our handles and the hidden flag
addEventHandler("onClientResourceStart", root, function(res)
    if session and getResourceName(res) == "items" then
        world.forgetHandles()
        exports.items:setWorldHidden(true)
    end
end)

-- ---------------------------------------------------------------- exports (debug and tooling)
-- Feeds a synthetic session around the local player (client/debug.lua), for checking the viewer without a server half.
local debugBuild = loadFile("client/debug.lua")

function debugDemo()
    local x, y, z = getElementPosition(localPlayer)
    local info, part = debugBuild(x, y, z, getRealTime().timestamp - 120)
    startSession(info, true)
    merge(part)
    recompute()
    return session.clock.duration
end

function debugStop()
    stopSession("debug")
end

function debugState()
    if not session then
        return "none"
    end
    local total, built = world.counts()
    return string.format(
        "t=%d/%d playing=%s speed=%g cam=%s items=%d built=%d events=%d focus=%s",
        session.clock.t,
        session.clock.duration,
        tostring(session.clock.playing),
        timeline.speed(session.clock),
        camera.mode(),
        total,
        built,
        #session.events,
        tostring(session.focus)
    )
end

function debugControl(name, arg)
    if not session then
        return false
    end
    if name == "seek" then
        seek(tonumber(arg) or 0)
    elseif name == "pause" then
        session.clock.playing = false
    elseif name == "play" then
        session.clock.playing = true
    elseif name == "speed" then
        timeline.setSpeedIndex(session.clock, tonumber(arg) or 3)
    elseif name == "camera" then
        camera.setMode(tostring(arg))
    elseif name == "cursor" then
        ui.setCursor(arg == true or arg == "true")
    elseif name == "skip" then
        actions.setSkipIdle(arg == true or arg == "true")
    end
    return true
end
