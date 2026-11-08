-- Engine-bay parts (battery and starter motor): tight, loose or missing.
-- Pure logic: no MTA calls at file scope. Charge and starter life live beside this state, not inside it.
-- A missing slot keeps no value on the car. A NULL starter life with a tight state is still a fresh motor
-- (rows from before starter motors were tracked). A NULL battery charge is an empty slot.
local M = {}

M.MISSING = 0
M.LOOSE = 1
M.TIGHT = 2

M.REPAIR = "repair_engine"
M.UNBOLT_BATTERY = "unbolt_battery"
M.TIGHTEN_BATTERY = "tighten_battery"
M.UNBOLT_STARTER = "unbolt_starter"
M.TIGHTEN_STARTER = "tighten_starter"

-- lang:begin
M.LABELS = {
    repair_engine = "Repair engine",
    unbolt_battery = "Unbolt battery",
    tighten_battery = "Tighten battery",
    unbolt_starter = "Unbolt starter motor",
    tighten_starter = "Tighten starter motor",
}
-- lang:end

local function stateNum(state)
    if state == false then
        return 0
    end
    return tonumber(state)
end

-- charge nil, or an explicit missing state: the slot is empty. Anything else with a charge is tight unless loose.
function M.normalizeBattery(charge, state)
    state = stateNum(state)
    if charge == nil or state == M.MISSING then
        return nil, M.MISSING
    end
    if state == M.LOOSE then
        return charge, M.LOOSE
    end
    return charge, M.TIGHT
end

-- A missing state drops the life. No state at all (a row from before this column) is tight, and a nil life then
-- still means a fresh motor.
function M.normalizeStarter(life, state)
    state = stateNum(state)
    if state == nil then
        state = M.TIGHT
    end
    if state == M.MISSING then
        return nil, M.MISSING
    end
    if life == false then
        life = nil
    end
    if state ~= M.LOOSE then
        state = M.TIGHT
    end
    return life, state
end

function M.connected(state)
    return state == M.TIGHT
end

-- Which loose part empty hands lift. The two parts are independent; with both loose the battery goes first.
function M.pickup(batteryState, starterState)
    if batteryState == M.LOOSE then
        return "battery"
    end
    if starterState == M.LOOSE then
        return "starter"
    end
    return nil
end

-- Entries for the ratchet menu at the open bonnet, only those that apply.
-- repairTool is vehicles.repairToolForHealth (nil when the engine needs no more field repair).
function M.menuEntries(repairTool, batteryState, starterState)
    local out = {}
    if repairTool == "Ratchet" then
        out[#out + 1] = { id = M.REPAIR, label = M.LABELS.repair_engine }
    end
    if batteryState == M.TIGHT then
        out[#out + 1] = { id = M.UNBOLT_BATTERY, label = M.LABELS.unbolt_battery }
    elseif batteryState == M.LOOSE then
        out[#out + 1] = { id = M.TIGHTEN_BATTERY, label = M.LABELS.tighten_battery }
    end
    if starterState == M.LOOSE then
        out[#out + 1] = { id = M.TIGHTEN_STARTER, label = M.LABELS.tighten_starter }
    elseif starterState == M.TIGHT then
        out[#out + 1] = { id = M.UNBOLT_STARTER, label = M.LABELS.unbolt_starter }
    end
    return out
end

function M.hasEntry(entries, id)
    for _, entry in ipairs(entries or {}) do
        if entry.id == id then
            return true
        end
    end
    return false
end

return M
