-- Replay (docs/superpowers/specs/2026-11-23-replay-design.md): the 5 Hz flight recorder that fills replay_chunk, the
-- event buffer that fills replay_event with what only the recorder can see (hits), and the staff sessions that rebuild
-- a time range for one viewer (server/session.lua, started by staff's /replay).
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

local function loadFile(path)
    local f = assert(fileOpen(path, true), "replay: cannot open " .. path)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=replay/" .. path))()
end

local ctx = {
    db = db,
    net = net,
    log = log,
    kinds = loadFile("shared/logic/kinds.lua"),
    codec = loadFile("shared/logic/codec.lua"),
    timespec = loadFile("shared/logic/timespec.lua"),
    ready = false,
}

function ctx.setting(key, default)
    local v = get(key)
    if v == nil or v == false then
        return default
    end
    return v
end

local events = loadFile("server/events.lua")(ctx)
local recorder = loadFile("server/recorder.lua")(ctx)
local session = loadFile("server/session.lua")(ctx)
ctx.events, ctx.recorder, ctx.session = events, recorder, session

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("replay") then
        outputServerLog("[replay] no database connection, nothing is recorded")
        return
    end
    ctx.ready = true
    recorder.start()
    events.start()
    outputServerLog("[replay] recorder " .. (recorder.enabled() and "on" or "off"))
end)

addEventHandler("onResourceStop", resourceRoot, function()
    recorder.stop()
    events.stop()
    session.stopAll("resource stopped")
end)

-- exports (see meta.xml)
function startSession(staff, spec)
    return session.start(staff, spec)
end

function stopSession(staff, reason)
    return session.stop(staff, reason or "stopped")
end

function isReplaying(staff)
    return session.isActive(staff)
end

function getKinds()
    return ctx.kinds
end

-- the command's time words -> from, to (unix seconds) or nil and a message; see shared/logic/timespec.lua
function parseRange(tokens, now)
    return ctx.timespec.parseRange(tokens, now or getRealTime().timestamp)
end

-- dev check: builds a session without a viewer and returns nothing; read the outcome with getDryRun (JSON)
function dryRun(target, from, to)
    return session.dryRun({ target = tostring(target), from = tonumber(from), to = tonumber(to) })
end

function getDryRun()
    return session.lastDry and toJSON(session.lastDry, true) or false
end
