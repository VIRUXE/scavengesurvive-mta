-- The driver's dashboard, bottom centre: an analog cluster (speedometer, tachometer, fuel gauge, voltmeter and a row
-- of tell-tale lamps), lit from the vehicle's state (battery, damage, fuel, headlights) and playing a short
-- "performance" when the engine is cranked or stalls, so each way a start can fail looks different (vehicles'
-- engineCranked / engineStalled).
-- Pure logic: no MTA calls at file scope. Levels are percent, times are milliseconds.
local M = {}

-- vehicles/shared/logic/battery.lua START_MIN: under it the engine will not turn over
M.BATTERY_FLAT = 10
M.BATTERY_LOW = 25
M.FUEL_LOW = 0.15 -- share of the tank: the lamp comes on
M.FUEL_RESERVE = 0.05 -- the lamp goes red
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
    { key = "lgt", label = "LGT", colour = GREEN },
    { key = "dor", label = "DOR", colour = GREEN },
}
M.RED = RED
-- the low-fuel lamp: the pump tell-tale in the middle of the row
M.FUEL_LAMP = { key = "fuel", colour = AMBER }

-- Speed in km/h from an element velocity (the same scale the tachometer's gear bands use).
function M.kmh(vx, vy, vz)
    return math.sqrt((vx or 0) ^ 2 + (vy or 0) ^ 2 + (vz or 0) ^ 2) * 180
end

-- The speedometer's full scale for a handling top speed: rounded up to a step, never under 120 or over 320.
function M.speedScale(maxKmh)
    local top = math.max(120, math.min(320, (maxKmh or 160) * 1.1))
    local step = top > 160 and 40 or 20
    return math.ceil(top / step) * step
end

-- The numbered step on a speedometer of full scale `top`.
function M.speedStep(top)
    return top > 160 and 40 or 20
end

-- The voltmeter: 8 .. 16 V, red under VOLTS_LOW. Returns the needle's share 0 .. 1.
M.VOLTS_MIN, M.VOLTS_MAX, M.VOLTS_LOW = 8, 16, 10.5
function M.voltShare(v)
    return math.max(0, math.min(1, ((v or 0) - M.VOLTS_MIN) / (M.VOLTS_MAX - M.VOLTS_MIN)))
end

-- The needle's position on the fuel gauge: 0 (E) .. 1 (F).
function M.fuelShare(fuel, maxFuel)
    if (maxFuel or 0) <= 0 then
        return 0
    end
    return math.max(0, math.min(1, (fuel or 0) / maxFuel))
end

-- What each crank outcome looks like (the code vehicles sends; false: it started):
--   bulb  every lamp lit for its first ms, as a real dash checks its bulbs when the key turns
--   crank how the needle moves while the starter turns: "catch" fires up, "click" a solenoid clicking on a flat
--         battery, "grind" a starter fighting a wrecked engine, "steady" an even crank that never catches
--   ms    how long the starter turns; steady = the lamp that then stays lit for FLASH_MS (a lamp never flashes on a
--         failed start)
--   sound the file in hud/sounds (without .wav) played with it, cut to the same beats (tools/make_ignition_sounds.py)
M.FLASH_MS = 4000
M.CRANKS = {
    OK = { bulb = 700, crank = "catch", ms = 1400, sound = "crank_start" },
    ACC = { bulb = 700, ms = 700, sound = "acc_on" }, -- the key turned to ACC: only the bulb check, no starter
    NO_BATTERY = { ms = 0 }, -- nothing at all: the dash stays dark and silent
    BATTERY_FLAT = { crank = "click", ms = 1300, flicker = true, sound = "crank_flat" },
    -- a dead starter motor: the solenoid clicks on a healthy battery (no lamp: the charge lamp is the alternator's)
    STARTER_BAD = { bulb = 700, crank = "dead", ms = 1300, sound = "crank_dead" },
    DAMAGED = { bulb = 700, crank = "grind", ms = 2200, steady = "chk", sound = "crank_grind" },
    NO_FUEL = { bulb = 700, crank = "steady", ms = 2200, steady = "fuel", sound = "crank_steady" },
}
-- A stall: the needle drops, CHK (bar an empty tank) comes on (STALL_MS), the cause
-- flashes.
M.STALL_MS = 1500
M.STALLS = { NO_FUEL = "fuel", DAMAGED = "chk", STALL = "chk", BATTERY_FLAT = "chk", NO_BATTERY = "chk" }
M.STALL_SOUND = "engine_stall"

-- The sound file (hud/sounds, no extension) a performance plays, or nil for a silent one: p = { kind, code } as in
-- sample.
function M.soundFor(p)
    if p.kind == "stall" then
        return M.STALL_SOUND
    end
    local spec = M.CRANKS[p.code or "OK"] or M.CRANKS.OK
    return spec.sound
end

-- The ignition switch beside the strip: where the key points in each position, in degrees clockwise from straight up.
M.KEY_ORDER = { "off", "acc", "start" }
M.KEY_ANGLES = { off = -45, acc = 0, start = 45 }
M.KEY_DEG_PER_S = 700

-- Where the key sits: START while the starter turns (the performance's cranking phase), ACC with the key left there
-- or the engine running (the barrel has no position of its own for that: START springs back to ACC), else OFF.
function M.keyPosition(s, shot)
    if shot and shot.start then
        return "start"
    elseif s.engine or s.acc then
        return "acc"
    end
    return "off"
end

-- One step of the shown key angle towards `target` degrees.
function M.keyStep(angle, target, dtMs)
    local rate = M.KEY_DEG_PER_S * (dtMs or 0) / 1000
    if math.abs(target - angle) <= rate then
        return target
    end
    return angle + (target > angle and rate or -rate)
end

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

-- The lamps for a vehicle state: s = { bay, battery (percent, nil: none fitted), alternator (false: bad), engine,
-- lights, health, fuel, maxFuel, locked }. Returns key -> { mode, colour (nil: the lamp's own) }.
function M.lamps(s)
    local out = { fuel = { mode = "off" } }
    for _, lamp in ipairs(M.LAMPS) do
        out[lamp.key] = { mode = "off" }
    end
    -- BAT is the charge lamp: it means the alternator is not charging (s.alternator == false, with the engine
    -- running). A low, flat or missing battery or the key in ACC do not light it, and nothing in vehicles fails an
    -- alternator yet, so it stays dark until something sets that.
    if s.alternator == false and s.engine then
        out.bat.mode = "on"
    end
    local hp = s.health or 1000
    if hp <= M.HEALTH_WRECKED then
        out.chk = { mode = "on", colour = RED }
    elseif hp <= M.HEALTH_BROKEN then
        out.chk.mode = "on"
    elseif hp <= M.HEALTH_WORN then
        out.chk.mode = "on"
    end
    if (s.maxFuel or 0) > 0 then
        local share = (s.fuel or 0) / s.maxFuel
        if (s.fuel or 0) <= 0 then
            out.fuel = { mode = "on", colour = RED }
        elseif share <= M.FUEL_RESERVE then
            out.fuel = { mode = "on", colour = RED }
        elseif share <= M.FUEL_LOW then
            out.fuel.mode = "on"
        end
    end
    if s.lights then
        out.lgt.mode = "on"
    end
    -- DOR is the door lock: lit green while the doors are open to anyone, red while they are locked
    out.dor = { mode = "on", colour = s.locked and RED or GREEN }
    return out
end

-- The panel has power: the key is in ACC or the engine runs, and the bonnet has a battery under it (bikes and boats
-- keep no battery level).
function M.powered(s)
    return (s.engine or s.acc or false) and (not s.bay or type(s.battery) == "number")
end

-- The voltage the needle shows for a charge, 14.1 V while the alternator charges it. Read as a gauge, not a
-- chemistry: a battery too flat to start (under BATTERY_FLAT) sits in the red, VOLTS_MIN .. VOLTS_LOW, and a dead one
-- pins the needle at the stop; from BATTERY_FLAT up it climbs VOLTS_LOW .. 12.7 V (full).
function M.volts(s)
    if not M.powered(s) then
        return 0
    end
    if s.engine then
        return 14.1
    end
    local level = math.max(0, math.min(100, s.bay and s.battery or 100))
    if level < M.BATTERY_FLAT then
        return M.VOLTS_MIN + (M.VOLTS_LOW - M.VOLTS_MIN) * level / M.BATTERY_FLAT
    end
    return M.VOLTS_LOW + (12.7 - M.VOLTS_LOW) * (level - M.BATTERY_FLAT) / (100 - M.BATTERY_FLAT)
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
-- keys lit), start (the key is in START) }, each nil when the performance leaves it to the live state; nil when it
-- is over.
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
            -- the engine cutting out: CHK comes on unless the cause is plain (an empty tank is no fault)
            out.solid = { chk = p.code ~= "NO_FUEL" or nil }
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
    out.start = spec.crank ~= nil -- the key is held in START while the starter turns
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
