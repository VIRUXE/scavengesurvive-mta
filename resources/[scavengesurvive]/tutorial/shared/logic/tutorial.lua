-- The tutorial's fixed content (upstream core/player/tutorial.pwn) and the text clean-up. Pure: no MTA calls.
local M = {}

M.DIMENSION_BASE = 61000
M.DIMENSION_COUNT = 1000
M.OFFER_MS = 300000 -- a fresh character may start the tutorial for this long, or until it first moves an item
M.TIP_MS = 20000
M.INTRO_MS = 25000
M.DRIVE_TIP_DELAY_MS = 21000 -- after the Bobcat's repair tip (20 s) has run its course

M.SPAWN = { x = 1078.36194, y = 2139.40771, z = 10.64758, rz = 180.0 }

-- upstream's kit: uname, position, random heading, data
M.ITEMS = {
    { uname = "Satchel", x = 1078.70325, y = 2132.96069, z = 9.85179 },
    { uname = "Wrench", x = 1077.57263, y = 2125.35938, z = 9.85153, spin = true },
    { uname = "Screwdriver", x = 1076.52942, y = 2125.82959, z = 9.85156, spin = true },
    { uname = "Hammer", x = 1074.94214, y = 2126.51489, z = 9.85160, spin = true },
    { uname = "Wheel", x = 1073.59448, y = 2127.05786, z = 9.85164, spin = true },
    { uname = "Wheel", x = 1073.4965, y = 2125.6582, z = 9.8516, spin = true },
    -- a Petrol Can with 10 L: the Bobcat's tank starts all but empty
    { uname = "GasCan", x = 1071.55, y = 2124.92, z = 9.8516, spin = true, data = { 10, "Petrol" } },
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

-- Upstream's strings carry SA-MP codes and name /exit, which MTA's console takes for "quit": `~>~` (an arrow glyph)
-- becomes ">>", `~n~` a line break, `#RRGGBB` goes, and /exit becomes /tutorial (which toggles the tutorial).
function M.clean(text)
    text = tostring(text or "")
    text = text:gsub("~>~", ">>"):gsub("~n~", "\n"):gsub("#%x%x%x%x%x%x", ""):gsub("/exit", "/tutorial")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
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
