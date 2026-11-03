-- Server-side checks retained from ScavengeSurvive's SA-MP anticheat. Movement and vehicle
-- synchronization are delegated to MTA; gameplay resources own locked-vehicle and ammo checks.
local LOW_POPULATION = 10
local LOW_POPULATION_BONUS = 100
local PING_GRACE_MS = 10000
local PING_STRIKES = 10 -- require ten consecutive 1 s samples over the limit
local DEFAULT_PING_LIMIT = 400
local DEFAULT_MAX_TAB_OUT_TIME = 60

local pingSince = {}
local pingStrikes = {}
local minimizedSince = {}
local lastTeleportAlert = {}
local spawnedAt = {}
local vehicleExitedAt = {}
local settings = {}
local idleKickEnabled = true
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=anticheat/" .. path))()
end
local fieldsLogic = loadFile("shared/logic/fields.lua")
local fields = loadFile("server/fields.lua")(db, fieldsLogic)
local focusLogic = loadFile("shared/logic/focus.lua")

local function playerName(player)
    return isElement(player) and getPlayerName(player) or "<left>"
end

local function log(player, check, detail)
    outputServerLog(string.format("[anticheat] %s (%s): %s", playerName(player), tostring(check), tostring(detail)))
end

local function kick(player, reason)
    if not isElement(player) then
        return
    end
    log(player, "kick", reason)
    kickPlayer(player, "ScavengeSurvive", reason)
end

-- what the hack-detect and hack-trap modules share: staff on duty are out of every check, a player without a living
-- character (not spawned yet, dead) has nothing to cheat with, and the tick helpers give the upstream grace windows
local ctx = { db = db, loadFile = loadFile, log = log, kick = kick, fields = fieldsLogic }
ctx.water = loadFile("shared/logic/water.lua")
ctx.accuracyLogic = loadFile("shared/logic/accuracy.lua")

function ctx.exempt(player)
    return exports.staff:isOnDuty(player)
end

function ctx.alive(player)
    return exports.character:getCharacterId(player) ~= nil and not isPedDead(player)
end

function ctx.sinceJoin(player)
    return getTickCount() - (pingSince[player] or 0)
end

function ctx.sinceSpawn(player)
    return getTickCount() - (spawnedAt[player] or 0)
end

function ctx.autoBan(player, reason)
    log(player, "ban", reason)
    return exports.staff:autoBan(player, reason)
end

ctx.report = loadFile("server/report.lua")(ctx)
local traps = loadFile("server/traps.lua")(ctx)
local movement = loadFile("server/movement.lua")(ctx)
local vehicles = loadFile("server/vehicles.lua")(ctx)
local accuracy = loadFile("server/accuracy.lua")(ctx)

addEventHandler("onPlayerJoin", root, function()
    pingSince[source] = getTickCount()
    pingStrikes[source] = 0
end)

addEventHandler("onPlayerQuit", root, function()
    pingSince[source] = nil
    pingStrikes[source] = nil
    minimizedSince[source] = nil
    lastTeleportAlert[source] = nil
    spawnedAt[source] = nil
    vehicleExitedAt[source] = nil
    movement.forget(source)
    accuracy.forget(source)
end)

addEventHandler("onPlayerSpawn", root, function()
    spawnedAt[source] = getTickCount()
end)

addEventHandler("onPlayerVehicleExit", root, function()
    vehicleExitedAt[source] = getTickCount()
end)

net.handler("anticheatFocusChanged", function(player, isFocused)
    if isFocused == true then
        minimizedSince[player] = nil
    elseif isFocused == false and not minimizedSince[player] then
        minimizedSince[player] = getTickCount()
        log(player, "focus", "game minimized")
    end
end)

-- Native MTA 1.6 movement monitor. Server-side setElementPosition calls are excluded by MTA,
-- so admin moves, spawn placement, and scripted gameplay teleports do not trip this alert.
addEventHandler("onPlayerTeleport", root, function(oldX, oldY, oldZ, newX, newY, newZ)
    if exports.staff:isOnDuty(source) or getPedOccupiedVehicle(source) or isPedDead(source) then
        return
    end
    local now = getTickCount()
    if
        (pingSince[source] and now - pingSince[source] < 20000)
        or (spawnedAt[source] and now - spawnedAt[source] < 1000)
        or (vehicleExitedAt[source] and now - vehicleExitedAt[source] < 5000)
    then
        return
    end
    local distance = getDistanceBetweenPoints3D(oldX, oldY, oldZ, newX, newY, newZ)
    setElementPosition(source, oldX, oldY, oldZ)
    if lastTeleportAlert[source] and now - lastTeleportAlert[source] < 10000 then
        return
    end
    lastTeleportAlert[source] = now
    local detail = string.format("unexpected position change %.1f m", distance)
    log(source, "teleport", detail)
    local from = string.format("%.0f, %.0f, %.0f", oldX, oldY, oldZ)
    local to = string.format("%.0f, %.0f, %.0f", newX, newY, newZ)
    ctx.report(source, "TELE", string.format("Moved %.0fm (%s > %s)", distance, from, to))
end)

-- MTA counts every client triggerServerEvent, including unregistered/non-remote event attempts.
addEventHandler("onPlayerTriggerEventThreshold", root, function(eventName)
    kick(source, "event flood" .. (eventName and (": " .. tostring(eventName)) or ""))
end)

-- Only a server-only event (added, not remote) is proof of a forged trigger. An event that is not added at all is
-- also what a legitimate client sends while a resource restarts (its client half still running), so that one is
-- logged instead of kicked.
addEventHandler("onPlayerTriggerInvalidEvent", root, function(eventName, isAdded, isRemote)
    local detail = string.format(
        "invalid server event %s (added=%s remote=%s)",
        tostring(eventName),
        tostring(isAdded),
        tostring(isRemote)
    )
    if isAdded then
        kick(source, detail)
    else
        log(source, "event", detail)
    end
end)

-- Preserve the upstream ping policy while tolerating transient spikes. Staff on duty are exempt.
setTimer(function()
    local players = getElementsByType("player")
    local count = #players
    local pingLimit = tonumber(settings["player.ping_limit"]) or DEFAULT_PING_LIMIT
    local limit = pingLimit + (count <= LOW_POPULATION and LOW_POPULATION_BONUS or 0)
    local maxTabOutTime = tonumber(settings["player.max_tab_out_time"]) or DEFAULT_MAX_TAB_OUT_TIME
    local now = getTickCount()

    for _, player in ipairs(players) do
        if not pingSince[player] then
            pingSince[player] = now
            pingStrikes[player] = 0
        end

        local onDuty = exports.staff:isOnDuty(player)
        if now - pingSince[player] >= PING_GRACE_MS then
            if not onDuty and getPlayerPing(player) > limit then
                pingStrikes[player] = (pingStrikes[player] or 0) + 1
                if pingStrikes[player] >= PING_STRIKES then
                    kick(player, string.format("ping exceeded %d ms for 10 seconds", limit))
                end
            else
                pingStrikes[player] = 0
            end
        end

        local minimizedAt = minimizedSince[player]
        if focusLogic.shouldKick(idleKickEnabled, maxTabOutTime, minimizedAt, now, onDuty) then
            kick(player, string.format("game unfocused for over %d seconds", maxTabOutTime))
            minimizedSince[player] = nil
        end
    end
end, 1000, 0)

-- staff's /field calls this after every add or remove
function refreshFields()
    fields.refresh()
end

function isIdleKickEnabled()
    return idleKickEnabled
end

function setIdleKickEnabled(enabled)
    idleKickEnabled = (enabled == true)
    if not idleKickEnabled then
        minimizedSince = {}
    end
    return idleKickEnabled
end

function toggleIdleKick()
    return setIdleKickEnabled(not idleKickEnabled)
end

function getMaxTabOutTime()
    return tonumber(settings["player.max_tab_out_time"]) or DEFAULT_MAX_TAB_OUT_TIME
end

function setMaxTabOutTime(seconds)
    local s = tonumber(seconds)
    if s and s >= 0 then
        settings["player.max_tab_out_time"] = tostring(s)
        return true
    end
    return false
end

setTimer(fields.update, 1000, 0)
setTimer(movement.update, 1000, 0)
setTimer(vehicles.update, 1000, 0)

addEventHandler("onResourceStart", resourceRoot, function()
    -- Pay 'n' Spray and the mod shops repair a vehicle past what the server can (the health check would ban the
    -- driver), so every garage door stays shut
    for garage = 0, 49 do
        setGarageOpen(garage, false)
    end
    if db.connect("anticheat") then
        fields.refresh()
        traps.sync()
        db.settings(function(map)
            settings = map or {}
            if settings["player.idle_kick"] == "0" then
                idleKickEnabled = false
            end
        end)
    end
end)
