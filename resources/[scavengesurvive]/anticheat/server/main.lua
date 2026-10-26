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
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=anticheat/" .. path))()
end
local fields = loadFile("server/fields.lua")(db, loadFile("shared/logic/fields.lua"))

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
    log(source, "teleport", string.format("unexpected position change %.1f m", distance))
end)

-- MTA counts every client triggerServerEvent, including unregistered/non-remote event attempts.
addEventHandler("onPlayerTriggerEventThreshold", root, function(eventName)
    kick(source, "event flood" .. (eventName and (": " .. tostring(eventName)) or ""))
end)

addEventHandler("onPlayerTriggerInvalidEvent", root, function(eventName, isAdded, isRemote)
    kick(
        source,
        string.format(
            "invalid server event %s (added=%s remote=%s)",
            tostring(eventName),
            tostring(isAdded),
            tostring(isRemote)
        )
    )
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
        if minimizedAt and not onDuty then
            local minimizedFor = now - minimizedAt
            if maxTabOutTime <= 0 or minimizedFor >= maxTabOutTime * 1000 then
                kick(player, string.format("game unfocused for over %d seconds", maxTabOutTime))
                minimizedSince[player] = nil
            end
        end
    end
end, 1000, 0)

-- staff's /field calls this after every add or remove
function refreshFields()
    fields.refresh()
end

setTimer(fields.update, 1000, 0)

addEventHandler("onResourceStart", resourceRoot, function()
    if db.connect("anticheat") then
        fields.refresh()
        db.settings(function(map)
            settings = map or {}
        end)
    end
end)
