-- The toxic cloud (server half): one cloud at a time forms off a map edge every few hours and drifts across the
-- map. Its place is a function of its plan and its age (shared/logic/cloud.lua), so clients are told the plan once
-- and draw it themselves; the server keeps the map strips over it and ends it when it has left the map.
-- A restart of this resource ends the cloud in the air: nothing of it is saved.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=toxic/" .. path))()
end
local geom = loadstring(exports.lib:getModule("geom"), "=lib/geom.lua")()
local cloudLogic = loadFile("shared/logic/cloud.lua")
local enclosure = loadFile("shared/logic/enclosure.lua")

local SCHEDULE_TICK_MS = 60 * 1000
local MAP_TICK_MS = 2000
local STRIPS = 5
local settings = {}
local active = nil -- { cloud, startedTick, areas = { radararea }, rows, why }
local nextAt = nil -- tick the next cloud may form at
local mapTimer = nil
local exposure = nil -- server/exposure.lua, once the settings are in

local function setting(key, default)
    return tonumber(settings[key]) or default
end

local function age()
    return (getTickCount() - active.startedTick) / 1000
end

local function scheduleNext()
    local wait = setting("toxic.interval_s", 10800) + math.random() * setting("toxic.jitter_s", 3600)
    nextAt = getTickCount() + wait * 1000
end

local function moveAreas()
    local cx, cy = cloudLogic.centre(active.cloud, age())
    for i, area in ipairs(active.areas) do
        local row = active.rows[i]
        setElementPosition(area, cx + row[1], cy + row[2]) -- a radar area lies flat: two coordinates
    end
end

local function finish(why)
    if not active then
        return false
    end
    for _, area in ipairs(active.areas) do
        if isElement(area) then
            destroyElement(area)
        end
    end
    if isTimer(mapTimer) then
        killTimer(mapTimer)
    end
    log.event("toxic.cloudEnded", { seed = active.cloud.seed, age_s = math.floor(age()), why = why or "passed" })
    active = nil
    triggerClientEvent(root, "toxicCloudEnded", resourceRoot)
    scheduleNext()
    return true
end

-- x, y nil: a cloud that crosses the map from an edge; given: one that forms there and drifts away.
local function begin(x, y, why)
    if active then
        return false, "a cloud is already in the air"
    end
    local radius, speed = setting("toxic.radius_m", 500), setting("toxic.speed_ms", 8)
    local seed = math.random(1, 2 ^ 30)
    local cloud
    if tonumber(x) and tonumber(y) then
        cloud = cloudLogic.planAt(math.random, radius, speed, seed, x, y)
    else
        cloud = cloudLogic.plan(math.random, radius, speed, seed)
    end
    active = { cloud = cloud, startedTick = getTickCount(), areas = {}, rows = cloudLogic.strips(radius, STRIPS) }
    for i, row in ipairs(active.rows) do
        active.areas[i] = createRadarArea(cloud.x0 + row[1], cloud.y0 + row[2], row[3], row[4], 150, 190, 40, 130)
    end
    mapTimer = setTimer(function()
        if age() >= active.cloud.duration then
            finish("passed")
        else
            moveAreas()
        end
    end, MAP_TICK_MS, 0)
    triggerClientEvent(root, "toxicCloudStarted", resourceRoot, cloud, 0)
    log.event("toxic.cloudStarted", {
        seed = seed,
        x = math.floor(cloud.x0),
        y = math.floor(cloud.y0),
        radius = radius,
        duration_s = math.floor(cloud.duration),
        why = why or "schedule",
    })
    return true
end

-- Exports ------------------------------------------------------------------------------------------------------

function startCloud(x, y, why)
    return begin(x, y, why)
end

function stopCloud(why)
    return finish(why or "staff")
end

-- Gas strength 0..1 at a point right now (0 with no cloud in the air).
function concentrationAt(x, y, z)
    if not active then
        return 0
    end
    return cloudLogic.concentration(active.cloud, age(), x, y, z)
end

-- For staff: the cloud in the air ({ x, y, radius, left_s }) or nil, then the seconds until the next may form.
function cloudStatus()
    if not active then
        return nil, nextAt and math.max(0, math.floor((nextAt - getTickCount()) / 1000)) or nil
    end
    local cx, cy = cloudLogic.centre(active.cloud, age())
    return {
        x = cx,
        y = cy,
        radius = active.cloud.radius,
        left_s = math.max(0, math.floor(active.cloud.duration - age())),
    }
end

-- For staff and tests: the gas strength around a player and the openness of where they stand, or nil when clear.
function exposureOf(player)
    if not exposure or not isElement(player) then
        return nil
    end
    return exposure.of(player)
end

net.handler("toxicCloudRequested", function(player)
    if active then
        triggerClientEvent(player, "toxicCloudStarted", resourceRoot, active.cloud, age())
    end
end, { rate = 2 })

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("toxic") then
        return
    end
    db.settings(function(map)
        settings = map or {}
        scheduleNext()
        exposure = loadFile("server/exposure.lua")({
            geom = geom,
            enclosure = enclosure,
            net = net,
            concentrationAt = concentrationAt,
            setting = setting,
        })
        setTimer(function()
            if active or getTickCount() < nextAt then
                return
            end
            if getPlayerCount() < setting("toxic.min_players", 1) then
                return
            end
            begin()
        end, SCHEDULE_TICK_MS, 0)
    end)
end)
