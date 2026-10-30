local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
db.connect("world")

local function loadFile(path, name)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, name))()
end

local weather = loadFile("shared/logic/weather.lua", "=world/weather.lua")
local fixtures = loadFile("shared/logic/fixtures.lua", "=world/fixtures.lua")
local fixtureList = loadFile("data/features.lua", "=world/features_data.lua").fixtures

-- upstream creates the zone files' fixed items on every start; here the ones gone from the world are made again,
-- with no despawn time (shared/logic/fixtures.lua)
local function placeFixtures()
    local types = fixtures.types(fixtureList)
    local marks = string.rep("?, ", #types - 1) .. "?"
    local sql = "SELECT type_uname, x, y FROM items WHERE x IS NOT NULL AND type_uname IN (" .. marks .. ")"
    db.query(sql, types, function(rows)
        if not rows then
            return util.log("world", "warn", "fixtures: could not read the world items")
        end
        local missing = fixtures.missing(fixtureList, rows)
        for _, f in ipairs(missing) do
            local args = { f[1], 5, nil, f[2], f[3], f[4], f[5], 0, 0, nil, nil, n = 11 }
            db.call("item_create", args, function(res)
                if not (res and res.ok) then
                    local why = res and res.code or "DB_ERROR"
                    util.log("world", "warn", "fixtures: %s at %f, %f: %s", f[1], f[2], f[3], why)
                end
            end)
        end
        local placed = #fixtureList - #missing
        util.log("world", "info", "fixtures: %d of %d in place, %d made again", placed, #fixtureList, #missing)
    end)
end

local current = 0
local lastChange = 0

local function apply(id, why)
    current, lastChange = id, getTickCount()
    setWeather(id)
    util.log("world", "info", "weather %d (%s) %s", id, weather.name(id), why)
    triggerEvent("weatherChanged", resourceRoot, id)
end

-- MTA keeps every client's weather and clock in sync on its own (setWeather/setTime are global and sent to
-- joiners), so unlike upstream there is no per-player loop; the clock is re-synced to the host each minute
-- because setMinuteDuration only approximates real time.
local function syncClock()
    local hour, minute = weather.clock(getRealTime())
    setTime(hour, minute)
end

addEventHandler("onResourceStart", resourceRoot, function()
    placeFixtures()
    setMinuteDuration(weather.MINUTE_MS)
    syncClock()
    apply(weather.initial(math.random), "at start")
    setTimer(syncClock, weather.CLOCK_SYNC_MS, 0)
    setTimer(function()
        if weather.shouldChange(getTickCount() - lastChange, math.random) then
            apply(weather.pick(math.random, current), "rolled")
        end
    end, weather.CHECK_INTERVAL_MS or 60000, 0)
end)

function getWeather()
    return current
end

-- id or name ("RAINY_SF"); false when unknown. Used by dev /weather and, later, staff level 4.
function setGlobalWeather(idOrName)
    local id = weather.parse(idOrName)
    if not id then
        return false
    end
    apply(id, "set")
    return id
end
