-- Carmour: defence panels welded onto a vehicle (upstream core/vehicle/carmour.pwn only bolted fixed object lists
-- onto every vehicle of a type; the port lets players weld them on). Only the towable Airstream (model 610) has
-- slots for now.
-- A vehicle's armour is { base, slots = { [slot index] = { u = uname, hp } } }, stored as JSON in vehicles.carmour.
-- Every welded panel adds its hitpoints to the walk-in door (which has DOOR_BASE_HP alone), makes the trailer heavier
-- and the vehicle towing it slower. Damage eats the panels first, then the door's own hitpoint, which breaks its lock.
-- The slot layout (a fixed placement for every panel in every slot) is generated: shared/data/carmour_slots.lua.
-- Pure: no MTA calls at file scope.
local M = {}

M.DOOR_BASE_HP = 1 -- the door alone: one hit breaks its lock
M.MASS_PER_PANEL = 180 -- kg added to the trailer per welded panel
M.TOW_ACCEL_PENALTY = 0.08 -- of the tower's stock engine acceleration per panel carried by the trailer behind it
M.TOW_ACCEL_FLOOR = 0.4 -- the tower never drops below this share of its stock acceleration
M.GAS_PER_TANK = 5 -- welds in a fresh Gas Tank (its item data is { gas = n }, no data meaning full)
M.GAS_PER_WELD = 1
M.FUEL_PER_WELD = 5 -- Generator fuel (of 100) one weld burns
M.WELD_MS = 8000
M.PANEL_REACH = 3.0 -- the panel to weld must lie this near the player
M.WELD_REACH = 2.5 -- and the player this near the trailer's side

-- the defence items a weld takes (building/shared/logic/defences.lua: any item with a defence table; these are the
-- ones with a model small enough for a window or a door)
M.PANELS = {
    MetPanel = true,
    CrateDoor = true,
    ShipDoor = true,
    CorPanel = true,
    SmallPanel = true,
    WoodPanel = true,
    InsulPanel = true,
    MetalGate = true,
}

function M.isPanel(uname)
    return M.PANELS[uname] == true
end

-- a vehicle model's armour is wanted at all
function M.hasSlots(slotsByModel, model)
    return slotsByModel ~= nil and slotsByModel[model] ~= nil
end

function M.new()
    return { base = M.DOOR_BASE_HP, slots = {} }
end

-- the armour from its decoded JSON (a missing or odd value is a bare door)
function M.decode(t)
    local st = M.new()
    if type(t) ~= "table" then
        return st
    end
    st.base = tonumber(t.base) or M.DOOR_BASE_HP
    for k, p in pairs(type(t.slots) == "table" and t.slots or {}) do
        local i = tonumber(k)
        if i and type(p) == "table" and type(p.u) == "string" and M.PANELS[p.u] then
            st.slots[i] = { u = p.u, hp = math.max(1, math.floor(tonumber(p.hp) or 1)) }
        end
    end
    return st
end

-- the armour as a table that survives JSON (slot indexes as strings)
function M.encode(st)
    local slots = {}
    for i, p in pairs(st.slots) do
        slots[tostring(i)] = { u = p.u, hp = p.hp }
    end
    return { base = st.base, slots = slots }
end

function M.panelCount(st)
    local n = 0
    for _ in pairs(st.slots) do
        n = n + 1
    end
    return n
end

-- the walk-in door's hitpoints: its own plus every panel's
function M.doorHp(st)
    local hp = st.base
    for _, p in pairs(st.slots) do
        hp = hp + p.hp
    end
    return hp
end

-- the lowest free slot of `slotDefs` (the vehicle model's slot list, door slot first), or nil when all are taken
function M.freeSlot(st, slotDefs)
    for i = 1, #slotDefs do
        if not st.slots[i] then
            return i
        end
    end
    return nil
end

-- the state with a panel welded into slot i (a panel keeps the hitpoints it had lying on the ground)
function M.weld(st, i, uname, hp)
    local out = M.decode(M.encode(st))
    out.slots[i] = { u = uname, hp = math.max(1, math.floor(tonumber(hp) or 1)) }
    return out
end

-- damage to the vehicle's armour: the panels take it in slot order (the door's panel first), what is left wears the
-- door's own hitpoint down. Returns the next state, the slots that were shed and whether the door's lock broke (the
-- hitpoint is then given back, the door is a bare door with a broken lock).
function M.applyDamage(st, dmg, slotDefs)
    local out = M.decode(M.encode(st))
    local shed = {}
    local left = tonumber(dmg) or 0
    for i = 1, #slotDefs do
        local p = out.slots[i]
        if p and left > 0 then
            local take = math.min(p.hp, left)
            p.hp = p.hp - take
            left = left - take
            if p.hp <= 0 then
                out.slots[i] = nil
                shed[#shed + 1] = i
            end
        end
    end
    local broken = false
    if left > 0 and next(out.slots) == nil then
        out.base = out.base - left
        if out.base <= 0 then
            broken = true
            out.base = M.DOOR_BASE_HP
        end
    end
    return out, shed, broken
end

-- the trailer's mass with n panels on it
function M.trailerMass(stock, n)
    return stock + M.MASS_PER_PANEL * n
end

-- the engine acceleration of a vehicle towing a trailer with n panels on it
function M.towAccel(stock, n)
    local share = math.max(M.TOW_ACCEL_FLOOR, 1 - M.TOW_ACCEL_PENALTY * n)
    return stock * share
end

-- welds left in a Gas Tank from its item data (either JSON shape)
function M.gasOf(data)
    local d = type(data) == "table" and data or {}
    if type(d[1]) == "table" then
        d = d[1]
    end
    local gas = tonumber(d.gas)
    if gas == nil then
        return M.GAS_PER_TANK
    end
    return math.max(0, math.floor(gas))
end

return M
