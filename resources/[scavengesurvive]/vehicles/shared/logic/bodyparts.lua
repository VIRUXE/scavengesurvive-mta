-- Removable vehicle body parts: which models have them, where each slot sits on the car and how a slot's saved state
-- reads. Pure logic: no MTA calls at file scope. A model joins by getting an entry in MODELS (and its part items:
-- <prefix><Slot>Good / <prefix><Slot>Bad, see tools/bobcat_parts.py).
local M = {}

M.REACH = 1.8 -- metres from a slot's point within which a player can work on it
M.DOOR_MISSING = 4 -- setVehicleDoorState: 0 intact .. 4 gone
M.PANEL_MISSING = 3 -- setVehiclePanelState: 0 intact .. 3 gone

-- door: MTA door id (0 bonnet, 1 boot, 2..5 the side doors); panel: MTA panel id (5 front bumper, 6 rear bumper)
-- x, y: the slot's point in the vehicle's local frame; groundDrop: metres from the origin down to the ground
M.MODELS = {
    [422] = {
        prefix = "Bobcat",
        groundDrop = 0.7,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.4 },
            { name = "Tailgate", door = 1, x = 0, y = -2.2 },
            { name = "LeftDoor", door = 2, x = -1.05, y = 0.25 },
            { name = "RightDoor", door = 3, x = 1.05, y = 0.25 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.25 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.35 },
        },
    },
}

local byUname = {}
for model, def in pairs(M.MODELS) do
    for _, slot in ipairs(def.slots) do
        slot.missing = slot.door and M.DOOR_MISSING or M.PANEL_MISSING
        if slot.door == 0 then
            slot.path = "$.hood"
        elseif slot.door == 1 then
            slot.path = "$.tailgate"
        elseif slot.door then
            slot.path = string.format("$.doors[%d]", slot.door - 2)
        else
            slot.path = string.format("$.panels[%d]", slot.panel)
        end
        byUname[def.prefix .. slot.name .. "Good"] = { model = model, slot = slot, good = true }
        byUname[def.prefix .. slot.name .. "Bad"] = { model = model, slot = slot, good = false }
    end
end

-- the part item `uname` -> model id, slot, good (false for a Bad part); nil when it is not a body part
function M.partOf(uname)
    local p = byUname[uname]
    if p then
        return p.model, p.slot, p.good
    end
    return nil
end

-- the item a slot yields: Good while it is intact or only dented, Bad once it hangs broken
function M.uname(model, slot, good)
    return M.MODELS[model].prefix .. slot.name .. (good and "Good" or "Bad")
end

-- "missing" | "bad" | "good" for a slot in MTA state `state`
function M.condition(slot, state)
    if state == nil or state == false then
        return "missing"
    end
    if state >= slot.missing then
        return "missing"
    end
    return state >= 2 and "bad" or "good"
end

-- the state a freshly fitted part leaves the slot in
function M.installState(good)
    return good and 0 or 2
end

-- the slot of `model` nearest to the local point (lx, ly) within REACH, or nil
function M.nearestSlot(model, lx, ly)
    local def = M.MODELS[model]
    if not def then
        return nil
    end
    local best, bestD = nil, M.REACH * M.REACH
    for _, slot in ipairs(def.slots) do
        local d = (lx - slot.x) ^ 2 + (ly - slot.y) ^ 2
        if d <= bestD then
            best, bestD = slot, d
        end
    end
    return best
end

-- A part fitted by hand sits loose until a Wrench secures it: driving shakes it off. Above LOOSE_KMH it comes off with
-- a chance per second that grows with speed; braking hard (LOOSE_BRAKE_KMH lost within a second) throws off every one.
M.LOOSE_KMH = 15
M.LOOSE_BRAKE_KMH = 25
M.LOOSE_FULL_KMH = 75 -- from here a loose part is shaken off almost at once

-- kmh: speed now, lastKmh: speed a second ago, roll: a random number in [0, 1); returns "all" | "one" | nil
function M.comesOff(kmh, lastKmh, roll)
    if (lastKmh or 0) - kmh >= M.LOOSE_BRAKE_KMH then
        return "all"
    end
    if kmh <= M.LOOSE_KMH then
        return nil
    end
    local chance = math.min(0.9, (kmh - M.LOOSE_KMH) / (M.LOOSE_FULL_KMH - M.LOOSE_KMH))
    if roll < chance then
        return "one"
    end
    return nil
end

-- where a detached part lands, in the vehicle's local frame (a little outside its slot)
function M.dropPoint(slot)
    return slot.x * 1.4, slot.y * 1.1
end

return M
