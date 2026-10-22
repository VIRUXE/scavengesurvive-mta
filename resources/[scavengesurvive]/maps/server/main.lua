-- Server-side zone colshapes built from data/zones.lua (tools/convert/maps.py, upstream pyss/data/regions.json).
-- Exposes getZoneAt(x, y) and getPlayerZone(player) and emits onPlayerZoneEnter / onPlayerZoneLeave.
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()

local function readLua(path)
    local f = fileOpen(path, true)
    if not f then
        return nil
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=maps/" .. path))()
end

local zones = readLua("shared/logic/zones.lua")
local polygons = {} -- zoneName -> normalized vertex array
local byCol = {} -- colshape -> zoneName
local byZone = {} -- zoneName -> colshape
local playerZone = {} -- player -> zoneName

function getZoneAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then
        return false
    end
    for _, name in ipairs(zones.ORDER) do
        local col = byZone[name]
        if col and isInsideColShape(col, x, y, 0) then
            return name
        end
        local poly = polygons[name]
        if poly and zones.contains(poly, x, y) then
            return name
        end
    end
    return false
end

function getPlayerZone(player)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false
    end
    if playerZone[player] then
        return playerZone[player]
    end
    if getElementDimension(player) ~= 0 then
        return false
    end
    local x, y = getElementPosition(player)
    return getZoneAt(x, y)
end

local function setPlayerZone(p, nextZone)
    local prev = playerZone[p]
    if prev == nextZone then
        return
    end
    playerZone[p] = nextZone
    if prev then
        triggerEvent("onPlayerZoneLeave", p, prev)
    end
    if nextZone then
        triggerEvent("onPlayerZoneEnter", p, nextZone)
    end
end

addEventHandler("onColShapeHit", resourceRoot, function(hitElement, matchingDimension)
    local zone = byCol[source]
    if not zone or not matchingDimension or not isElement(hitElement) or getElementType(hitElement) ~= "player" then
        return
    end
    setPlayerZone(hitElement, zone)
end)

addEventHandler("onColShapeLeave", resourceRoot, function(leaveElement, matchingDimension)
    local zone = byCol[source]
    if not zone or not matchingDimension or not isElement(leaveElement) or getElementType(leaveElement) ~= "player" then
        return
    end
    if playerZone[leaveElement] ~= zone then
        return
    end
    local x, y = getElementPosition(leaveElement)
    local now = getElementDimension(leaveElement) == 0 and (getZoneAt(x, y) or nil) or nil
    if now == zone then
        now = nil
    end
    setPlayerZone(leaveElement, now)
end)

addEventHandler("onPlayerSpawn", root, function()
    local x, y = getElementPosition(source)
    local now = getElementDimension(source) == 0 and (getZoneAt(x, y) or nil) or nil
    setPlayerZone(source, now)
end)

addEventHandler("onPlayerQuit", root, function()
    playerZone[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local raw = readLua("data/zones.lua") or {}
    local count = 0
    for _, name in ipairs(zones.ORDER) do
        local pts = raw[name]
        if type(pts) == "table" and #pts >= 3 then
            local norm = zones.normalize(pts)
            polygons[name] = norm
            local col = createColPolygon(unpack(zones.colPolygonArgs(norm)))
            if col then
                setColPolygonHeight(col, zones.FLOOR_Z, false)
                byCol[col] = name
                byZone[name] = col
                count = count + 1
            end
        end
    end
    for _, p in ipairs(getElementsByType("player")) do
        if getElementDimension(p) == 0 then
            local x, y = getElementPosition(p)
            playerZone[p] = getZoneAt(x, y) or nil
        end
    end
    util.log("maps", "info", "%d zone colshapes created", count)
end)
