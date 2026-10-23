local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local weather
do
    local f = fileOpen("shared/logic/weather.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    weather = assert(loadstring(src, "=world/weather.lua"))()
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
    setMinuteDuration(weather.MINUTE_MS)
    syncClock()
    apply(weather.initial(math.random), "at start")
    setTimer(syncClock, weather.CLOCK_SYNC_MS, 0)
    setTimer(function()
        if weather.shouldChange(getTickCount() - lastChange, math.random) then
            apply(weather.pick(math.random), "rolled")
        end
    end, weather.CHECK_MS, 0)
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
