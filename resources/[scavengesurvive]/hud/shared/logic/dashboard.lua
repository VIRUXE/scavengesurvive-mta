-- The driver's dashboard, bottom centre: a strip of warning lamps over a tachometer and a voltmeter, lit from the
-- vehicle's state (battery, damage, fuel, headlights) and playing a short "performance" when the engine is
-- cranked or stalls, so each way a start can fail looks different (vehicles' engineCranked / engineStalled).
-- Pure logic: no MTA calls at file scope. Levels are percent, times are milliseconds.
local M = {}

-- vehicles/shared/logic/battery.lua START_MIN: under it the engine will not turn over
M.BATTERY_FLAT = 10
M.BATTERY_LOW = 25
M.FUEL_LOW = 0.15 -- share of the tank: the lamp comes on
M.FUEL_RESERVE = 0.05 -- the lamp flashes
-- vehicles/shared/logic/vehicle.lua HEALTH_CHUNK_1..3: wrecked (no start), broken (stalls), a bit broken
M.HEALTH_WRECKED, M.HEALTH_BROKEN, M.HEALTH_WORN = 300, 450, 650

M.IDLE_RPM, M.MAX_RPM, M.REDLINE = 800, 7000, 0.85
M.SHIFT = 0.9 -- the share of the scale the needle reaches at the top of a gear, just into the red
M.SLOW_MS, M.FAST_MS = 500, 125 -- half periods of a slow and a fast flash

local RED = { 0xFF, 0x22, 0x22 }
local AMBER = { 0xFF, 0xA8, 0x00 }
local GREEN = { 0x33, 0xFF, 0x33 }

-- left to right; colour is the lamp's lit colour
M.LAMPS = {
    { key = "bat", label = "BAT", colour = RED },
    { key = "chk", label = "CHK", colour = AMBER },
    { key = "fuel", label = "FUEL", colour = AMBER },
    { key = "lgt", label = "LGT", colour = GREEN },
}
M.RED = RED

-- What each crank outcome looks like (the code vehicles sends; false: it started):
--   bulb  every lamp lit for its first ms, as a real dash checks its bulbs when the key turns
--   crank how the needle moves while the starter turns: "catch" fires up, "click" a solenoid clicking on a flat
--         battery, "grind" a starter fighting a wrecked engine, "steady" an even crank that never catches
--   ms    how long the starter turns; flash = the lamp that then flashes fast for FLASH_MS
M.FLASH_MS = 4000
M.CRANKS = {
    OK = { bulb = 700, crank = "catch", ms = 1400 },
    ACC = { bulb = 700, ms = 700 }, -- the key turned to ACC: only the bulb check, no starter
    NO_BATTERY = { ms = 0 }, -- nothing at all: the dash stays dark
    BATTERY_FLAT = { crank = "click", ms = 1300, flash = "bat", flicker = true },
    -- a dead starter motor: the solenoid clicks on a healthy battery, so BAT just stays lit (no flash, the battery
    -- is fine)
    STARTER_BAD = { bulb = 700, crank = "dead", ms = 1300, steady = "bat" },
    DAMAGED = { bulb = 700, crank = "grind", ms = 2200, flash = "chk" },
    NO_FUEL = { bulb = 700, crank = "steady", ms = 2200, flash = "fuel" },
}
-- A stall: the needle drops, BAT and CHK come on as the alternator stops (STALL_MS), the cause flashes.
M.STALL_MS = 1500
M.STALLS = { NO_FUEL = "fuel", DAMAGED = "chk", STALL = "chk", BATTERY_FLAT = "bat", NO_BATTERY = "bat" }

-- mode -> lit at tick `now`: "off" | "on" | "slow" | "fast"
function M.lit(mode, now)
    if mode == "on" then
        return true
    elseif mode == "slow" then
        return math.floor((now or 0) / M.SLOW_MS) % 2 == 0
    elseif mode == "fast" then
        return math.floor((now or 0) / M.FAST_MS) % 2 == 0
    end
    return false
end

-- The lamps for a vehicle state: s = { bay, battery (percent, nil: none fitted), engine, lights, health, fuel,
-- maxFuel }. Returns key -> { mode, colour (nil: the lamp's own) }.
function M.lamps(s)
    local out = {}
    for _, lamp in ipairs(M.LAMPS) do
        out[lamp.key] = { mode = "off" }
    end
    if s.bay and type(s.battery) == "number" then
        if s.battery < M.BATTERY_FLAT then
            out.bat.mode = "fast"
        elseif s.battery < M.BATTERY_LOW then
            out.bat.mode = "slow"
        elseif s.lights and not s.engine then
            out.bat.mode = "on" -- headlights running the battery down
        end
    end
    local hp = s.health or 1000
    if hp <= M.HEALTH_WRECKED then
        out.chk = { mode = "fast", colour = RED }
    elseif hp <= M.HEALTH_BROKEN then
        out.chk.mode = "slow"
    elseif hp <= M.HEALTH_WORN then
        out.chk.mode = "on"
    end
    if (s.maxFuel or 0) > 0 then
        local share = (s.fuel or 0) / s.maxFuel
        if (s.fuel or 0) <= 0 then
            out.fuel = { mode = "fast", colour = RED }
        elseif share <= M.FUEL_RESERVE then
            out.fuel.mode = "slow"
        elseif share <= M.FUEL_LOW then
            out.fuel.mode = "on"
        end
    end
    if s.lights then
        out.lgt.mode = "on"
    end
    return out
end

-- The panel has power: the key is in ACC or the engine runs, and the bonnet has a battery under it (bikes and boats
-- keep no battery level).
function M.powered(s)
    return (s.engine or s.acc or false) and (not s.bay or type(s.battery) == "number")
end

-- Resting voltage of a lead-acid battery from its charge, 14.1 V while the alternator charges it.
function M.volts(s)
    if not M.powered(s) then
        return 0
    end
    if s.engine then
        return 14.1
    end
    local level = s.bay and s.battery or 100
    return 11.6 + 1.1 * math.max(0, math.min(100, level)) / 100
end

-- The needle with the engine running: the share of the current gear's speed band (handling maxVelocity split
-- evenly over numberOfGears), a rev bump on the throttle standing still. gear 0 is reverse.
function M.rpm(kmh, gear, maxKmh, gears, throttle)
    local band = math.max(1, (maxKmh or 160) / math.max(1, gears or 5))
    local g = math.max(1, gear or 1)
    local frac = math.max(0, math.min(1, ((kmh or 0) - (g - 1) * band) / band))
    if (kmh or 0) < 5 and throttle then
        frac = math.max(frac, 0.35)
    end
    return M.IDLE_RPM + frac * (M.MAX_RPM * M.SHIFT - M.IDLE_RPM)
end

-- One step of the shown needle towards `target` (needles lag; it falls faster than it climbs).
function M.needle(shown, target, dtMs)
    local rate = (target > shown and 6000 or 9000) * (dtMs or 0) / 1000
    if math.abs(target - shown) <= rate then
        return target
    end
    return shown + (target > shown and rate or -rate)
end

-- A playing performance at `elapsed` ms: { rpm, volts, glow (backlight 0..1), bulb, flash (lamp key), solid (lamp
-- keys lit) }, each nil when the performance leaves it to the live state; nil when it is over.
-- p = { kind = "crank" | "stall", code }, rng () -> [0, 1).
function M.sample(p, elapsed, rng)
    rng = rng or math.random
    if p.kind == "stall" then
        local flash = M.STALLS[p.code] or "chk"
        if elapsed > M.FLASH_MS then
            return nil
        end
        local out = { flash = flash }
        if elapsed < M.STALL_MS then
            out.solid = { bat = true, chk = true }
        end
        return out
    end
    local spec = M.CRANKS[p.code or "OK"] or M.CRANKS.OK
    local total = (spec.ms or 0) + ((spec.flash or spec.steady) and M.FLASH_MS or 0)
    if elapsed > total then
        return nil
    end
    local out = { bulb = spec.bulb and elapsed < spec.bulb or false }
    if elapsed >= (spec.ms or 0) then
        out.flash = spec.flash
        out.solid = spec.steady and { [spec.steady] = true } or nil
        return out
    end
    local t = elapsed
    if spec.crank == "catch" then
        if t < 600 then
            out.rpm, out.volts = 220 + 60 * math.sin(t / 45), 10.4 + 0.3 * rng()
        elseif t < 900 then
            out.rpm = 1600 * (t - 600) / 300 + 250
        else
            out.rpm = 1850 - (1850 - M.IDLE_RPM) * (t - 900) / 500
        end
    elseif spec.crank == "click" then
        -- the solenoid clicks every 220 ms: a twitch of the needle, the lights sag on each click
        local click = t % 220 < 60
        out.rpm = click and 30 + 30 * rng() or 0
        out.volts = (click and 6.2 or 8.4) + 0.6 * rng()
    elseif spec.crank == "dead" then
        -- the same solenoid click, but the battery holds up: only a small sag on each click
        local click = t % 220 < 60
        out.rpm = click and 30 + 30 * rng() or 0
        out.volts = (click and 10.8 or 11.8) + 0.3 * rng()
    elseif spec.crank == "grind" then
        -- a starter that binds: uneven, catching and dropping
        local bind = math.floor(t / 170) % 3 == 0
        out.rpm = bind and 40 + 60 * rng() or 180 + 160 * rng()
        out.volts = 9.6 + 0.8 * rng()
    elseif spec.crank == "steady" then
        out.rpm = 240 + 45 * math.sin(t / 70)
        out.volts = 10.2 + 0.2 * math.sin(t / 70)
    end
    if spec.flicker then
        out.glow = 0.15 + 0.35 * rng()
    end
    return out
end

return M
