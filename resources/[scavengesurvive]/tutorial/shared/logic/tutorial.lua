-- The tutorial's fixed content (upstream core/player/tutorial.pwn) and the text clean-up. Pure: no MTA calls.
local M = {}

M.DIMENSION_BASE = 61000
M.DIMENSION_COUNT = 1000
M.TIP_MS = 20000
M.INTRO_MS = 25000
M.DRIVE_TIP_DELAY_MS = 21000 -- after the Bobcat's repair tip (20 s) has run its course
M.CHECK_MS = 1000
M.VEHICLE_RETRY_MS = 10000 -- a Bobcat asked for and not there after this long is asked for again

-- The tutorial is complete when the Bobcat is repaired (the "a bit broken" band, vehicles HEALTH_CHUNK_3), refuelled
-- past what it started with, running, and driven at a walking pace or faster.
M.REPAIRED_HEALTH = 650
M.REFUELLED_LITRES = 1.0
M.DRIVEN_KMH = 5

M.SPAWN = { x = 1078.36194, y = 2139.40771, z = 10.64758, rz = 180.0 }

-- upstream's kit: uname, position, random heading, data. Upstream laid the tools and wheels in a line right in front
-- of the Bobcat; here the bonnet opens with empty hands and F there would pick a tool up instead, so everything but
-- the Satchel lies 4 m further back (KIT_SHIFT_Y), out of the pickup radius of a player at the bonnet.
local KIT_SHIFT_Y = 4.0
M.ITEMS = {
    { uname = "Satchel", x = 1078.70325, y = 2132.96069, z = 9.85179 },
    { uname = "Wrench", x = 1077.57263, y = 2125.35938 + KIT_SHIFT_Y, z = 9.85153, spin = true },
    { uname = "Screwdriver", x = 1076.52942, y = 2125.82959 + KIT_SHIFT_Y, z = 9.85156, spin = true },
    { uname = "Hammer", x = 1074.94214, y = 2126.51489 + KIT_SHIFT_Y, z = 9.85160, spin = true },
    { uname = "Wheel", x = 1073.59448, y = 2127.05786 + KIT_SHIFT_Y, z = 9.85164, spin = true },
    { uname = "Wheel", x = 1073.4965, y = 2125.6582 + KIT_SHIFT_Y, z = 9.8516, spin = true },
    -- a Petrol Can with 10 L: the Bobcat's tank starts all but empty. Keyed, as vehicles reads and writes a can's
    -- fill (data.amount); the Petrol Can holds only petrol (items/shared/logic/liquids.lua)
    { uname = "GasCan", x = 1071.55, y = 2124.92 + KIT_SHIFT_Y, z = 9.8516, spin = true, data = { amount = 10 } },
}

M.VEHICLE = {
    uname = "Bobcat",
    x = 1075.4344,
    y = 2121.3606,
    z = 10.7901,
    rz = 355.6799,
    health = 321.9,
    maxStartFuel = 1.0, -- litres, a random amount up to this
    tires = { 0, 1, 1, 0 },
    loot = { "world_civilian", 5 },
}

-- A random damage set as upstream's SetVehicleDamageData call: seven panels 0-3, four doors 0-4, four lights 0-1,
-- and the two flat tyres.
function M.damage(rng)
    local panels, doors, lights = {}, {}, {}
    for i = 1, 7 do
        panels[i] = rng(0, 3)
    end
    for i = 1, 4 do
        doors[i] = rng(0, 4)
        lights[i] = rng(0, 1)
    end
    return { panels = panels, doors = doors, lights = lights, tires = M.VEHICLE.tires }
end

-- Upstream's strings carry SA-MP codes: `~>~` (an arrow glyph) becomes ">>", `~n~` a line break and `#RRGGBB` goes.
-- They also name /exit (MTA's console takes that for "quit"; the tutorial cannot be left before it is completed), so a
-- sentence naming /exit is dropped; the goal replaces it.
function M.clean(text)
    text = tostring(text or "")
    text = text:gsub("~>~", ">>"):gsub("~n~", "\n"):gsub("#%x%x%x%x%x%x", "")
    text = text:gsub("%s*[^%.!]*/exit[^%.!]*[%.!]", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- true when the vehicle and its driver meet the completion conditions (see REPAIRED_HEALTH)
function M.completed(health, fuel, engineOn, kmh)
    return engineOn == true
        and (tonumber(health) or 0) >= M.REPAIRED_HEALTH
        and (tonumber(fuel) or 0) > M.REFUELLED_LITRES
        and (tonumber(kmh) or 0) >= M.DRIVEN_KMH
end

-- The key of the tip an item move earns: (from, to) as itemMoved reports them, containerKind the kind of the
-- container a held item went into ("inventory", "bag" or anything else).
function M.moveTipKey(from, to, containerKind)
    if from == "held" and to == "bag" then
        return "TUTORACCBAG"
    elseif from == "held" and to == "world" then
        return "TUTORDROITM"
    elseif from == "held" and to == "container" then
        if containerKind == "inventory" then
            return "TUTORINVADD"
        elseif containerKind == "bag" then
            return "TUTORADDBAG"
        end
        return "TUTORADDCNT"
    end
    return nil
end

return M
