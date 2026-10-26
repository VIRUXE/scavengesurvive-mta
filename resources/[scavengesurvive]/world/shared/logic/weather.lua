-- Weather and clock (upstream core/server/weather.pwn + player.pwn): one global weather drawn from a weighted
-- list, re-rolled with a 10 % chance every 10 minutes; the in-game clock follows the host's real time.
-- Pure logic: rng() returns a float in [0,1); the caller supplies the tick and the real-time table.
local weather = {}
weather.CHECK_MS = 600000 -- upstream cooldown: at least 10 minutes between weather changes
weather.CHECK_INTERVAL_MS = 60000 -- evaluate change chance every minute once cooldown expires
weather.CHANGE_CHANCE = 10 -- percent chance per minute once CHECK_MS has passed
weather.MINUTE_MS = 60000 -- one game minute per real minute: the clock is the host's clock
weather.CLOCK_SYNC_MS = 60000

-- GTA weather ids (SA-MP and MTA share them) with upstream's selection chance
weather.TYPES = {
    { id = 0, name = "EXTRASUNNY_LS", chance = 1.0 },
    { id = 1, name = "SUNNY_LS", chance = 1.0 },
    { id = 2, name = "EXTRASUNNY_SMOG_LS", chance = 1.0 },
    { id = 3, name = "SUNNY_SMOG_LS", chance = 1.0 },
    { id = 4, name = "CLOUDY_LS", chance = 1.0 },
    { id = 5, name = "SUNNY_SF", chance = 1.0 },
    { id = 6, name = "EXTRASUNNY_SF", chance = 1.0 },
    { id = 7, name = "CLOUDY_SF", chance = 1.0 },
    { id = 8, name = "RAINY_SF", chance = 0.3 },
    { id = 9, name = "FOGGY_SF", chance = 1.0 },
    { id = 10, name = "SUNNY_LV", chance = 1.0 },
    { id = 11, name = "EXTRASUNNY_LV", chance = 1.0 },
    { id = 12, name = "CLOUDY_LV", chance = 0.6 },
    { id = 13, name = "EXTRASUNNY_COUNTRYSIDE", chance = 0.8 },
    { id = 14, name = "SUNNY_COUNTRYSIDE", chance = 0.9 },
    { id = 15, name = "CLOUDY_COUNTRYSIDE", chance = 0.5 },
    { id = 16, name = "RAINY_COUNTRYSIDE", chance = 0.4 },
    { id = 17, name = "EXTRASUNNY_DESERT", chance = 1.0 },
    { id = 18, name = "SUNNY_DESERT", chance = 1.0 },
    { id = 19, name = "SANDSTORM_DESERT", chance = 0.3 },
}

local byName = {}
for _, t in ipairs(weather.TYPES) do
    byName[t.name] = t
end

function weather.isValid(id)
    return type(id) == "number" and id >= 0 and id <= #weather.TYPES - 1 and id == math.floor(id)
end

-- "8", "RAINY_SF" or "rainy_sf" -> 8; nil when unknown
function weather.parse(text)
    local n = tonumber(text)
    if n then
        return weather.isValid(n) and n or nil
    end
    local t = type(text) == "string" and byName[string.upper(text)]
    return t and t.id or nil
end

function weather.name(id)
    local t = weather.TYPES[id + 1]
    return t and t.name or tostring(id)
end

-- upstream OnGameModeInit: random(19) -> 0..18, so the server never boots into the sandstorm
function weather.initial(rng)
    return math.floor(rng() * 19)
end

-- every type whose chance beats an independent roll (upstream builds this list before picking)
function weather.candidates(rng)
    local out = {}
    for _, t in ipairs(weather.TYPES) do
        if rng() < t.chance then
            out[#out + 1] = t.id
        end
    end
    return out
end

-- a new weather id; the chance-1.0 types always qualify, so the list is never empty (the guard mirrors upstream).
-- When excludeId is given and other candidates qualify, prefers a different weather so transitions don't stall.
function weather.pick(rng, excludeId)
    local list = weather.candidates(rng)
    if #list == 0 then
        return 0
    end
    if excludeId and #list > 1 then
        local filtered = {}
        for _, id in ipairs(list) do
            if id ~= excludeId then
                filtered[#filtered + 1] = id
            end
        end
        if #filtered > 0 then
            list = filtered
        end
    end
    return list[math.floor(rng() * #list) + 1]
end

function weather.shouldChange(sinceLastChangeMs, rng)
    return sinceLastChangeMs > weather.CHECK_MS and rng() * 100 < weather.CHANGE_CHANCE
end

-- hour, minute from an MTA getRealTime() table (upstream gettime(): the host's local clock)
function weather.clock(realTime)
    return realTime.hour, realTime.minute
end

return weather
