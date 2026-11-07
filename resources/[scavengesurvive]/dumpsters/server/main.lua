-- Dumpsters (shared/spots.lua): the interact key next to one opens it as a container (the items resource shows it like
-- a crate), its lid opens for every client while somebody looks inside. A dumpster's container is made and filled on
-- its first opening (world_dumpsters keeps spot -> container) and filled again, once it is empty, dumpsters.refill_s
-- after the last fill. The lid state is derived from who has the container open, polled once a second.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
db.connect("dumpsters")
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=dumpsters/" .. path))()
end
local logic = loadFile("shared/logic/dumpsters.lua")
local spots = loadFile("shared/spots.lua")

local SERVER_REACH = logic.OPEN_REACH + 1.0
local REFILL_S = 7200
local busy = {} -- spot -> true while its container is being made or filled
local viewers = {} -- spot -> { [player] = containerId }
local lidOpen = {} -- spot -> true

local function openList()
    local out = {}
    for spot in pairs(lidOpen) do
        out[#out + 1] = spot
    end
    table.sort(out)
    return out
end

local function setLid(spot, open)
    if (lidOpen[spot] or false) == open then
        return
    end
    lidOpen[spot] = open or nil
    triggerClientEvent(root, "dumpsterLidsChanged", resourceRoot, openList())
end

local function itemSize(uname)
    local t = exports.data:itemType(uname)
    return t and t.size
end

-- create the container and its first fill (cb(containerId) or cb(nil))
local function makeContainer(spot, cb)
    db.exec("INSERT INTO containers (kind, size) VALUES ('supply', ?)", { logic.CAPACITY }, function(ok, _, _, cid)
        local containerId = ok and tonumber(cid)
        if not containerId then
            return cb(nil)
        end
        db.exec("INSERT INTO world_dumpsters (spot, container_id) VALUES (?, ?)", { spot, containerId }, function(ok2)
            cb(ok2 and containerId or nil)
        end)
    end)
end

local function fillContainer(spot, containerId, cb)
    local items = logic.fill(itemSize, math.random)
    local made = 0
    local function nextItem(i)
        if i > #items then
            log.event("world.dumpsterFilled", { spot = spot, container_id = containerId, count = made })
            return cb()
        end
        db.call("item_create_in_container", { items[i], containerId }, function(res)
            if res and res.ok then
                made = made + 1
            end
            nextItem(i + 1)
        end)
    end
    nextItem(1)
end

-- the container of the spot, made on the first call and refilled when empty and old; cb(containerId) or cb(nil)
local function ensure(spot, cb)
    db.one(
        "SELECT d.container_id AS cid, TIMESTAMPDIFF(SECOND, d.filled_at, NOW()) AS age, "
            .. "(SELECT COUNT(*) FROM items i WHERE i.container_id = d.container_id) AS n "
            .. "FROM world_dumpsters d WHERE d.spot = ?",
        { spot },
        function(row)
            if not row then
                return makeContainer(spot, function(cid)
                    if not cid then
                        return cb(nil)
                    end
                    fillContainer(spot, cid, function()
                        cb(cid)
                    end)
                end)
            end
            local refill = tonumber(row.n) == 0 and tonumber(row.age) >= REFILL_S
            if not refill then
                return cb(row.cid)
            end
            db.exec("UPDATE world_dumpsters SET filled_at = NOW() WHERE spot = ?", { spot }, function()
                fillContainer(spot, row.cid, function()
                    cb(row.cid)
                end)
            end)
        end
    )
end

net.handler("dumpsterOpenRequested", function(player, spot)
    spot = tonumber(spot)
    local s = spot and spots[spot]
    if not s or busy[spot] or not isElement(player) or getElementDimension(player) ~= 0 then
        return
    end
    if getElementInterior(player) ~= 0 then
        return
    end
    local px, py, pz = getElementPosition(player)
    if logic.distance(s, px, py, pz) > SERVER_REACH then
        return
    end
    busy[spot] = true
    ensure(spot, function(containerId)
        busy[spot] = nil
        if not isElement(player) then
            return
        end
        local line = { player = player, spot = spot, container_id = containerId or false }
        if not containerId then
            line.ok, line.code = false, "DB_ERROR"
            return log.event("world.dumpsterOpened", line, "warn")
        end
        log.event("world.dumpsterOpened", line)
        local title = lang.textFor(player, logic.TITLE)
        if exports.items:openSupplyContainer(player, containerId, title, logic.CAPACITY, s[1], s[2], s[3] + 0.75) then
            viewers[spot] = viewers[spot] or {}
            viewers[spot][player] = containerId
            setLid(spot, true)
        end
    end)
end, { rate = 5 })

-- the lid closes once nobody has the dumpster's container open any more
setTimer(function()
    for spot, list in pairs(viewers) do
        for player, containerId in pairs(list) do
            if not isElement(player) or exports.items:getOpenContainerId(player) ~= containerId then
                list[player] = nil
            end
        end
        if next(list) == nil then
            viewers[spot] = nil
            setLid(spot, false)
        end
    end
end, 1000, 0)

net.handler("dumpsterLidsRequested", function(player)
    triggerClientEvent(player, "dumpsterLidsChanged", resourceRoot, openList())
end, { rate = 2 })

addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do
        triggerClientEvent(p, "dumpsterLidsChanged", resourceRoot, openList())
    end
    util.log("dumpsters", "info", "%d dumpster spots", #spots)
end)
