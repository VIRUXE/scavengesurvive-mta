-- A Gas Bottle's gas: item data {"gas": kg}. A bottle that carries no data counts as full. The loot roll
-- (loot/shared/logic/roll.lua gasBottleData) writes the same shape with the same capacity, and a trailer's mounted
-- bottles (vehicles.gas_bottles) keep it per slot, so a stove or heater can read them with M.of.
local M = {}

M.UNAME = "GasBottle"
M.CAPACITY = 11.0 -- kg of propane in a full bottle (tools/port_tools.py GAS_BOTTLE_CAPACITY)
M.MIN_ROLL = 0.5

local function unwrap(data)
    if type(data) == "string" then
        local ok, decoded = pcall(fromJSON, data)
        return ok and type(decoded) == "table" and decoded or {}
    end
    return type(data) == "table" and data or {}
end

-- kg of gas left, 0..CAPACITY
function M.of(data)
    local d = unwrap(data)
    local gas = d.gas == nil and M.CAPACITY or tonumber(d.gas) or 0
    return math.max(0, math.min(M.CAPACITY, gas))
end

-- A random fill for a bottle found lying about: rng() is a float in [0, 1)
function M.roll(rng)
    local gas = M.MIN_ROLL + rng() * (M.CAPACITY - M.MIN_ROLL)
    return math.floor(gas * 10 + 0.5) / 10
end

-- "Gas Bottle (6.3/11 kg)"
function M.label(name, data)
    return string.format("%s (%.1f/%d kg)", name, M.of(data), M.CAPACITY)
end

return M
