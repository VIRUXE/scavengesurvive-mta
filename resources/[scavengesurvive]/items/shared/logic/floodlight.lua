-- The Flood Light (the port's own, server/floodlight.lua): a work light on a tripod that lights the room it stands in
-- (world/client/blackout.fx). It runs off a Tool Battery installed in it, which goes flat in BATTERY_MINUTES, or off
-- a fuelled Generator lying within GENERATOR_REACH, which burns GEN_FUEL_PER_MIN while it lights it and spares the
-- battery. Item data { lit = 1 | nil, battery = charge | nil }: the charge in the Tool Battery's own units (0 ..
-- BATTERY_CHARGES, vehicles/shared/logic/carmour.lua, which the Angle Grinder spends a whole one of per pass), kept
-- fractional here; a Tool Battery taken out keeps it as its { charge = n }.
local UNAME = "FloodLight"
local BATTERY_UNAME = "ToolBattery"
local BATTERY_CHARGES = 3 -- a full Tool Battery (carmour.BATTERY_CHARGES)
local BATTERY_MINUTES = 10 -- a full Tool Battery lights it this long
local GEN_FUEL_PER_MIN = 1.0 -- Generator fuel (of machines.MAX_FUEL, 100) burnt a minute while it lights one

-- the light (flood_light.dff, tools/make_props.py FLOOD_LAMP / FLOOD_AIM): where on the model it comes from and the
-- way it points
local LAMP = { 0.0, 0.058, 1.4345 }
local AIM = { 0.0, 0.966, -0.259 }

-- the messages the server shows (formatted in the player's language)
-- lang:begin
local TEXT = {
    NOPOWER = "No power: install a Tool Battery, or run a fuelled Generator within 8 metres",
    HASBATTERY = "There is a battery in it already",
    FLAT = "That Tool Battery is flat",
    INSTALLED = "Tool Battery installed: %d%%",
    REMOVED = "Tool Battery taken out: %d%%",
    NOBATTERY = "There is no battery in it",
    ON_BATTERY = "Flood Light on: battery %d%%",
    ON_GENERATOR = "Flood Light on: running off the Generator",
    OFF = "Flood Light off",
}
-- lang:end

local function first(data)
    local d = type(data) == "table" and data or {}
    return type(d[1]) == "table" and d[1] or d
end

-- the item data as a plain table (either JSON shape)
local function dataOf(data)
    local d = first(data)
    return { lit = tonumber(d.lit) == 1 and 1 or nil, battery = tonumber(d.battery) }
end

local function isLit(data)
    return dataOf(data).lit == 1
end

-- the installed battery's charge, or nil when there is none
local function battery(data)
    local b = dataOf(data).battery
    return b and math.max(0, math.min(BATTERY_CHARGES, b)) or nil
end

-- a Tool Battery's charge from its own item data: none is a full one (carmour.chargeOf), fractional ones kept
local function toolCharge(data)
    local n = tonumber(first(data).charge)
    return n == nil and BATTERY_CHARGES or math.max(0, math.min(BATTERY_CHARGES, n))
end

local function percent(charge)
    return math.floor((tonumber(charge) or 0) / BATTERY_CHARGES * 100 + 0.5)
end

-- what one draw of `seconds` takes from a battery, and from a Generator's tank
local function batteryDraw(seconds)
    return BATTERY_CHARGES * seconds / (BATTERY_MINUTES * 60)
end

local function fuelDraw(seconds)
    return GEN_FUEL_PER_MIN * seconds / 60
end

-- the light's origin and aim in the world for an object matrix (getElementMatrix): x, y, z, dx, dy, dz
local function lampPose(m)
    local function apply(v, w)
        return m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3] + m[4][1] * w,
            m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3] + m[4][2] * w,
            m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3] + m[4][3] * w
    end
    local x, y, z = apply(LAMP, 1)
    local dx, dy, dz = apply(AIM, 0)
    return x, y, z, dx, dy, dz
end

return {
    UNAME = UNAME,
    BATTERY_UNAME = BATTERY_UNAME,
    BATTERY_CHARGES = BATTERY_CHARGES,
    GENERATOR_REACH = 8.0, -- the Flood Light's cable, the Welder's (carmour.GENERATOR_REACH)
    TICK_MS = 30000, -- the server draws power this often
    REACH = 2.5, -- metres a player works it from
    -- how far the light reaches (its cone is the world shader's, world/client/blackout.lua CONE), its colour, and
    -- createLight's point light for peds and vehicles, which the world shader does not reach
    RADIUS = 14.0,
    COLOUR = { 1.0, 0.93, 0.8 },
    PED_LIGHT_RADIUS = 10.0,
    TEXT = TEXT,
    data = dataOf,
    isLit = isLit,
    battery = battery,
    toolCharge = toolCharge,
    percent = percent,
    batteryDraw = batteryDraw,
    fuelDraw = fuelDraw,
    lampPose = lampPose,
}
