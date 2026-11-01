-- Carmour: defences fixed onto a vehicle (upstream core/vehicle/carmour.pwn only bolted fixed object lists onto every
-- vehicle of a type; the port lets players do it). Only the towable Airstream (model 610) takes them for now.
-- A defence held at the trailer is first attached: aimed with the camera, it lies on the shell at full size where the
-- player looks (shared/logic/carmour_place.lua; a door defence only on the door, stretched to fit it). An attached
-- panel weighs on the trailer but protects nothing and a Crowbar pries it off again. Welding it on with the Welder's
-- torch fortifies the trailer: every welded panel adds its hitpoints to the walk-in door (which has DOOR_BASE_HP
-- alone) and, while any is welded on, the trailer cannot be damaged. Damage eats the welded panels (the door's
-- first), then the door's own hitpoint, which breaks its lock; it knocks every attached, unwelded panel off.
-- A vehicle's armour is { base, next, panels = { record, ... } } stored as JSON in vehicles.carmour; a record is
-- { id, u = uname, hp, w = welded, door, c = centre, l, s = long and short side (unit), sa, sb = door stretch }.
-- Pure: no MTA calls at file scope.
local M = {}

M.DOOR_BASE_HP = 1 -- the door alone: one hit breaks its lock
M.MASS_PER_PANEL = 180 -- kg added to the trailer per panel on it, welded or not
M.TOW_ACCEL_PENALTY = 0.08 -- of the tower's stock engine acceleration per panel carried by the trailer behind it
M.TOW_ACCEL_FLOOR = 0.4 -- the tower never drops below this share of its stock acceleration
M.GAS_CAPACITY = 11 -- kg in a full Gas Bottle (items/shared/logic/gas.lua), its item data { gas = kg }, none meaning full
M.GAS_PER_WELD = 2.2 -- kg one weld burns: a full bottle is five welds
M.FUEL_PER_WELD = 5 -- Generator fuel (of 100) one weld burns
M.WELD_MS = 8000
M.PRY_MS = 3000 -- a Crowbar taking an attached panel off
M.GENERATOR_REACH = 8.0 -- the Welder's cable: a Generator with fuel this near the Welder powers it
M.LEAD = 5.0 -- metres of lead between the Welder and its torch
M.WORK_REACH = 1.6 -- the player this near a panel's box welds or pries it
M.ATTACH_REACH = 4.5 -- the player this near the spot a panel is attached to
M.GROUND_DROP = 0.75 -- metres from the trailer's origin down to the ground, where a knocked-off panel lands

function M.new()
    return { base = M.DOOR_BASE_HP, next = 1, panels = {} }
end

local function vec3(t)
    if type(t) ~= "table" then
        return nil
    end
    local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
    if not (x and y and z) then
        return nil
    end
    return { x, y, z }
end

-- the armour from its decoded JSON (a missing or odd value is a bare door; panels of unknown types are dropped)
function M.decode(t, panels)
    local st = M.new()
    if type(t) ~= "table" then
        return st
    end
    st.base = tonumber(t.base) or M.DOOR_BASE_HP
    st.next = math.max(1, math.floor(tonumber(t.next) or 1))
    for _, p in ipairs(type(t.panels) == "table" and t.panels or {}) do
        local c, l, s = vec3(p.c), vec3(p.l), vec3(p.s)
        local known = type(p.u) == "string" and (panels == nil or panels[p.u] ~= nil)
        if known and c and l and s then
            local id = math.floor(tonumber(p.id) or st.next)
            st.panels[#st.panels + 1] = {
                id = id,
                u = p.u,
                hp = math.max(1, math.floor(tonumber(p.hp) or 1)),
                w = p.w == true,
                door = p.door == true,
                c = c,
                l = l,
                s = s,
                sa = tonumber(p.sa) or 1,
                sb = tonumber(p.sb) or 1,
            }
            st.next = math.max(st.next, id + 1)
        end
    end
    return st
end

local function round(v)
    return math.floor(v * 10000 + 0.5) / 10000
end

-- the armour as a table that survives JSON
function M.encode(st)
    local panels = {}
    for i, p in ipairs(st.panels) do
        panels[i] = {
            id = p.id,
            u = p.u,
            hp = p.hp,
            w = p.w,
            door = p.door,
            c = { round(p.c[1]), round(p.c[2]), round(p.c[3]) },
            l = { round(p.l[1]), round(p.l[2]), round(p.l[3]) },
            s = { round(p.s[1]), round(p.s[2]), round(p.s[3]) },
            sa = round(p.sa),
            sb = round(p.sb),
        }
    end
    return { base = st.base, next = st.next, panels = panels }
end

local function copy(st)
    return M.decode(M.encode(st))
end

-- every panel on the vehicle, welded or not (what it weighs)
function M.panelCount(st)
    return #st.panels
end

-- the welded panels (what protects it)
function M.weldedCount(st)
    local n = 0
    for _, p in ipairs(st.panels) do
        if p.w then
            n = n + 1
        end
    end
    return n
end

-- the walk-in door's hitpoints: its own plus every welded panel's
function M.doorHp(st)
    local hp = st.base
    for _, p in ipairs(st.panels) do
        if p.w then
            hp = hp + p.hp
        end
    end
    return hp
end

function M.find(st, id)
    for i, p in ipairs(st.panels) do
        if p.id == id then
            return p, i
        end
    end
    return nil
end

-- the state with a placement record (carmour_place.place) attached as an unwelded panel of uname with hp
function M.attach(st, rec, uname, hp)
    local out = copy(st)
    local id = out.next
    out.next = id + 1
    out.panels[#out.panels + 1] = {
        id = id,
        u = uname,
        hp = math.max(1, math.floor(tonumber(hp) or 1)),
        w = false,
        door = rec.door == true,
        c = rec.c,
        l = rec.l,
        s = rec.s,
        sa = rec.sa or 1,
        sb = rec.sb or 1,
    }
    return out, id
end

-- the state with panel id welded on
function M.weld(st, id)
    local out = copy(st)
    local p = M.find(out, id)
    if p then
        p.w = true
    end
    return out
end

-- the state without panel id, and the record taken off
function M.remove(st, id)
    local out = copy(st)
    local p, i = M.find(out, id)
    if p then
        table.remove(out.panels, i)
    end
    return out, p
end

-- Damage to the vehicle's armour: every attached, unwelded panel falls off; the welded ones take it, the door's
-- first; what is left wears the door's own hitpoint down. Returns the next state, the records that came off (shed
-- welded ones, knocked-off unwelded ones, each with .knocked) and whether the door's lock broke (the hitpoint is
-- then given back: a bare door with a broken lock).
function M.applyDamage(st, dmg)
    local out = copy(st)
    local off = {}
    local left = tonumber(dmg) or 0
    if left <= 0 then
        return out, off, false
    end
    local keep = {}
    for _, p in ipairs(out.panels) do
        if p.w then
            keep[#keep + 1] = p
        else
            p.knocked = true
            off[#off + 1] = p
        end
    end
    table.sort(keep, function(a, b)
        if a.door ~= b.door then
            return a.door
        end
        return a.id < b.id
    end)
    local stay = {}
    for _, p in ipairs(keep) do
        if left > 0 then
            local take = math.min(p.hp, left)
            p.hp = p.hp - take
            left = left - take
        end
        if p.hp > 0 then
            stay[#stay + 1] = p
        else
            off[#off + 1] = p
        end
    end
    out.panels = stay
    local broken = false
    if left > 0 and #stay == 0 then
        out.base = out.base - left
        if out.base <= 0 then
            broken = true
            out.base = M.DOOR_BASE_HP
        end
    end
    return out, off, broken
end

-- the nearest panel to point p (the vehicle's frame) whose box lies within reach, among those `want(p)` accepts
function M.nearest(st, place, geo, p, reach, want)
    local frames = geo.panels
    local best, bestD = nil, reach
    for _, rec in ipairs(st.panels) do
        local frame = frames[rec.u]
        if frame and (want == nil or want(rec)) then
            local d = place.distanceTo(place.effective(geo, rec), frame, p)
            if d <= bestD then
                best, bestD = rec, d
            end
        end
    end
    return best
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

-- kg of gas left in a Gas Bottle from its item data (either JSON shape)
function M.gasOf(data)
    local d = type(data) == "table" and data or {}
    if type(d[1]) == "table" then
        d = d[1]
    end
    local gas = tonumber(d.gas)
    if gas == nil then
        return M.GAS_CAPACITY
    end
    return math.max(0, math.min(M.GAS_CAPACITY, gas))
end

return M
