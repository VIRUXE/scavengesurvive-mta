-- Run from the repo root: lua tests/lua/loot_budget_test.lua
-- Exercise the real loot server with a FIFO mock database and deferred placement callbacks.
local base = "resources/[scavengesurvive]/"
local realLoadstring = loadstring
local row = { zone = "sf", cap = 1000, alive = 100, allowance = 900, remainder = 0 }
local pending, timers, handlers, events = {}, {}, {}, {}
local failRoll = false
local activePlayers = {}
local playerX, playerY, now = 0, 0, 0
local db = {}
function db.connect()
    return true
end
function db.settings(cb)
    cb({})
end
function db.exec(sql, params, cb)
    if sql:find("SET remainder", 1, true) then
        row.remainder, row.allowance = params[1], math.min(params[2], params[3] - params[4])
    elseif sql:find("SET allowance = LEAST", 1, true) then
        row.allowance = math.min(row.allowance, params[1])
    end
    if cb then
        cb(true)
    end
end
function db.query(sql, _, cb)
    if sql:find("SELECT s.id", 1, true) then
        pending[#pending + 1] = cb
    elseif sql:find("SELECT 1", 1, true) then
        cb({})
    elseif sql:find("SELECT b.zone", 1, true) or sql:find("SELECT zone, allowance", 1, true) then
        cb({ row })
    else
        cb({}) -- love box lookup
    end
end
function db.call(_, _, cb, rolls)
    if failRoll then
        cb({ ok = false, code = "TEST" }, rolls)
        return
    end
    for _, r in ipairs(rolls) do
        row.allowance = row.allowance - #r.items
        row.alive = row.alive + #r.items
    end
    cb({ ok = true }, rolls)
end
local budget = dofile(base .. "lib/modules/budget.lua")
local modules = {
    spawn_guard = dofile(base .. "lib/modules/spawn_guard.lua"),
    db = db,
    net = {},
    util = { log = function() end },
    budget = budget,
    log = { event = function() end },
}
exports = {
    lib = {
        getModule = function(_, name)
            return "module:" .. name
        end,
    },
    data = {
        lootTable = function()
            return {}
        end,
        itemType = function()
            return { category = "generic" }
        end,
    },
}
local roll = {
    pick = function()
        return { "item", "item", "item", "item", "item", "item", "item", "item", "item", "item" }
    end,
    initialItemData = function()
        return nil
    end,
    MEDICAL_DATA = {},
}
loadstring = function(src, name)
    local module = src:match("^module:(.*)")
    if module then
        return function()
            return modules[module]
        end
    end
    if src == "shared/logic/roll.lua" then
        return function()
            return roll
        end
    end
    if src == "shared/logic/drops.lua" then
        return function()
            return {}
        end
    end
    if src == "server/drops.lua" then
        return function()
            return function()
                return { start = function() end, stop = function() end }
            end
        end
    end
    return realLoadstring(src, name)
end
function fileOpen(path)
    return path
end
function fileRead(path)
    return path
end
function fileGetSize()
    return 0
end
function fileClose() end
root, resourceRoot = {}, {}
function addEventHandler(name, _, cb)
    handlers[name] = cb
end
function setTimer(cb, interval)
    timers[interval] = cb
    return cb
end
function isTimer()
    return false
end
function getElementsByType()
    return activePlayers
end
function isElement()
    return true
end
function getElementPosition()
    return playerX, playerY, 0
end
function getTickCount()
    return now
end
function isPedDead()
    return false
end
function toJSON(value)
    return value
end
function triggerEvent(name, _, ...)
    events[#events + 1] = { name, ... }
end

dofile(base .. "loot/server/main.lua")
assert(rollNear(0, 0, 400) == false, "must wait for budget load")
handlers.onResourceStart()
assert(row.allowance == 8, "startup must clamp old bank to one rounded-up interval")
assert(lootAllowances().sf == 8)
local tick = assert(timers[300000])
tick()
assert(row.allowance == 7, "tick grants 7, not old allowance plus 7")
tick()
assert(row.allowance == 8, "fractional remainder carries but unused whole allowance expires")
local function finishQuery()
    local cb = table.remove(pending, 1)
    cb({ { id = 1, x = 1000, y = 1000, z = 10, zone = "sf", table_name = "world", size = 1, weight = 1 } })
end
assert(rollNear(0, 0, 400))
assert(rollNear(0, 0, 400) == false, "overlapping query must not reuse allowance")
local before = row.allowance
tick()
assert(row.allowance == before, "refill must not overwrite in-flight reservations")
finishQuery()
assert(row.allowance == 0 and lootAllowances().sf == 0, "placement consumes only the interval quota")
assert(#events == 1 and events[1][3] == 8, "emit only the committed items")
assert(rollNear(0, 0, 400))
finishQuery()
assert(#events == 1, "no further placement before next refill")
tick()
local available = row.allowance
failRoll = true
assert(rollNear(0, 0, 400))
finishQuery()
assert(lootAllowances().sf == available, "failed transaction restores cached allowance")
assert(#events == 1, "failed transaction must not announce items")
failRoll = false
row.allowance = 0
handlers.onResourceStart()
assert(lootAllowances().sf == 0, "restart must not mint a new quota")
row.alive = row.cap
tick()
assert(row.allowance == 0, "no refill at capacity")
-- Even with serialized DB work, the periodic scan must reach every player.
activePlayers = { {}, {} }
exports.character = {
    getCharacterId = function()
        return 1
    end,
}
for _, player in ipairs(activePlayers) do
    source = player
    handlers.onPlayerSpawn()
end
now = 2000
timers[15000]()
assert(#pending == 0, "initial origin must not activate loot")
playerX, playerY = -2664, 280
timers[15000]()
assert(#pending == 1, "first player starts one query")
finishQuery()
assert(#pending == 1, "second player is visited after the first query completes")
finishQuery()
assert(#pending == 0, "scan completes without duplicate queries")
print("loot budget regression checks passed")
