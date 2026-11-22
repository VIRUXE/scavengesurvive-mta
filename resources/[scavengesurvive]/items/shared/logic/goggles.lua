-- Night Vision and Thermal Vision goggles (no MTA calls). Worn in the "eyes" gear slot and switched on and off with
-- the goggles key; while on, the wearer's client shows GTA's own vision (client/goggles.lua) and the goggles run
-- down the battery inside them:
--   Night Vision amplifies what little light there is: the dark world shows in green, the daylight glares;
--   Thermal Vision shows heat: the living glow against a cold world by day and by night, and it eats the battery
--     twice as fast.
-- Item data { battery = charge }: the charge in the Tool Battery's own units (0 .. BATTERY_CHARGES, as the Flood
-- Light keeps it, shared/logic/floodlight.lua), kept fractional. Goggles found without data are rolled partly used
-- the first time they are worn (ensure). A Tool Battery used from the hand while goggles are worn trades places with
-- the one inside (swap): the fuller one goes in, the other comes out into the hand.
-- tr(text): a line in the reader's language; the client passes lib lang.text.
local BATTERY_UNAME = "ToolBattery"
local BATTERY_CHARGES = 3 -- a full Tool Battery (carmour.BATTERY_CHARGES)
local LOW = 15 -- % of battery from which the picture starts to flicker
-- mode: what setCameraGoggleEffect takes; minutes: how long a full Tool Battery keeps them on
local GOGGLES = {
    NightVision = { mode = "nightvision", minutes = 40 },
    ThermalVision = { mode = "thermalvision", minutes = 20 },
}

-- Goggles switched off sit pushed up on the forehead: added to the row they are worn at over the eyes
-- (apparel.attachConfig's offsets, { x, y, z, rx, ry, rz } on the head bone: x up the skull, rz the pitch). The
-- model's origin is the head's pivot, so the pitch alone swings them up round the skull.
local UP = { 0.0, 0.0, 0.0, 0.0, 0.0, -28.0 }

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function first(data)
    local d = type(data) == "table" and data or {}
    return type(d[1]) == "table" and d[1] or d
end

local function spec(uname)
    return GOGGLES[uname]
end

-- the charge inside the goggles, 0 .. BATTERY_CHARGES (0 before the first wear)
local function battery(data)
    return clamp(tonumber(first(data).battery) or 0, 0, BATTERY_CHARGES)
end

-- a Tool Battery's charge from its own item data: none is a full one (carmour.chargeOf)
local function toolCharge(data)
    local n = tonumber(first(data).charge)
    return n == nil and BATTERY_CHARGES or clamp(n, 0, BATTERY_CHARGES)
end

-- whole % of a charge, rounded up so a battery reads 1% until it is flat
local function percent(charge)
    return math.ceil(clamp(tonumber(charge) or 0, 0, BATTERY_CHARGES) / BATTERY_CHARGES * 100 - 0.0001)
end

-- Gives goggles their battery when they have none; true when it rolled and the data needs saving. rnd() -> 0..1.
local function ensure(item, rnd)
    if not GOGGLES[item.uname] then
        return false
    end
    if type(item.data) ~= "table" then
        item.data = {}
    end
    if tonumber(first(item.data).battery) ~= nil then
        return false
    end
    item.data = { battery = BATTERY_CHARGES * (20 + math.floor(rnd() * 81)) / 100 }
    return true
end

-- The goggles were on for `seconds`. Returns "flat" when that emptied the battery, true when it only drained.
local function drain(item, seconds)
    local g = GOGGLES[item.uname]
    if not g then
        return false
    end
    local left = math.max(0, battery(item.data) - BATTERY_CHARGES * seconds / (g.minutes * 60))
    item.data = { battery = left }
    return left <= 0 and "flat" or true
end

-- A Tool Battery of this charge goes into the goggles: returns the charge of the one that comes out, or nil when
-- the one inside is no emptier (nothing to gain).
local function swap(item, charge)
    local inside = battery(item.data)
    if charge <= inside then
        return nil
    end
    item.data = { battery = charge }
    return inside
end

-- the attach offsets of goggles pushed up on the forehead
local function upOffsets(offsets)
    local o = {}
    for i = 1, 6 do
        o[i] = offsets[i] + UP[i]
    end
    return o
end

-- "Night Vision (battery 63%)", "Night Vision (battery flat)"; the name alone before the first wear.
local function label(name, uname, data, tr)
    if not GOGGLES[uname] or tonumber(first(data).battery) == nil then
        return name
    end
    local left = percent(battery(data))
    if left <= 0 then
        return string.format("%s (%s)", name, tr("battery flat"))
    end
    return string.format("%s (%s %d%%)", name, tr("battery"), left)
end

return {
    BATTERY_UNAME = BATTERY_UNAME,
    BATTERY_CHARGES = BATTERY_CHARGES,
    LOW = LOW,
    spec = spec,
    battery = battery,
    toolCharge = toolCharge,
    percent = percent,
    ensure = ensure,
    drain = drain,
    swap = swap,
    upOffsets = upOffsets,
    label = label,
}
