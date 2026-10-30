-- Buttons and the doors they move (upstream libraries ScavengeSurvive/button and door, used by the zone files'
-- gates and doors, the puzzles and Area 69). A button is a spot in a world with a prompt; a press there either moves
-- the doors it belongs to, takes the player to the button it links to (upstream LinkTP), or is handled by whoever
-- registered it (a puzzle). Pure: the world resource keeps one registry on the server and one on each client, built
-- from the same definitions, and only door states travel between them.
local M = {}

-- a button is pressed within this reach (upstream buttons are 1.0 m areas, streamed at 4 m)
M.REACH = 1.5
M.FREEZE_MS = 1000 -- upstream FreezePlayer(playerid, 1000) after a teleport
M.MIN_MOVE_MS = 200

function M.new()
    -- doorsOf: button id -> the doors it moves (kept here, not on the button tables the definitions share)
    return { buttons = {}, byId = {}, doors = {}, doorIds = {}, states = {}, doorsOf = {} }
end

-- b = { id, x, y, z, world, label [, to = linked button id] [, owner = handler name] }
function M.addButton(reg, b)
    assert(not reg.byId[b.id], "duplicate button " .. tostring(b.id))
    reg.buttons[#reg.buttons + 1] = b
    reg.byId[b.id] = b
    return b
end

-- d = { id, model, world, closed = { x, y, z, rx, ry, rz }, open = {...}, speed, closeDelay, buttons = { ids } }
-- door.inc defaults: speed 1.0, closeDelay 3000 (shut that long after it opened; -1 stays where it was moved)
function M.addDoor(reg, d)
    assert(not reg.doors[d.id], "duplicate door " .. tostring(d.id))
    d.speed = d.speed or 1.0
    d.closeDelay = d.closeDelay or 3000
    reg.doors[d.id] = d
    reg.doorIds[#reg.doorIds + 1] = d.id
    reg.states[d.id] = "closed"
    for _, bid in ipairs(d.buttons or {}) do
        assert(reg.byId[bid], "door " .. d.id .. " has no button " .. tostring(bid))
        reg.doorsOf[bid] = reg.doorsOf[bid] or {}
        table.insert(reg.doorsOf[bid], d.id)
    end
    return d
end

local function dist(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- the closest button within reach of a point in a world and its distance, or nil; hidden(b) true leaves a button
-- out (a puzzle's button that is gone)
function M.buttonAt(reg, x, y, z, world, hidden)
    local best, bestD = nil, M.REACH
    for _, b in ipairs(reg.buttons) do
        if b[4] == (world or 0) and not (hidden and hidden(b)) then
            local d = dist(b[1], b[2], b[3], x, y, z)
            if d <= bestD then
                best, bestD = b, d
            end
        end
    end
    return best, best and bestD or nil
end

-- how long a door takes between its poses (MoveDynamicObject at `speed` m/s; a door that mostly turns moves cm)
function M.doorMs(d)
    local c, o = d.closed, d.open
    return math.max(M.MIN_MOVE_MS, math.floor(dist(c[1], c[2], c[3], o[1], o[2], o[3]) / d.speed * 1000 + 0.5))
end

-- the pose a door is drawn at in a state
function M.pose(d, state)
    return state == "open" and d.open or d.closed
end

-- door.inc _door_onButton: a closed door opens, an open one shuts. Appends to `out` the effects
-- { "changed" } and, for a door that shuts by itself, { "autoclose", door id, ms after the press }.
function M.toggleDoor(reg, id, out)
    local d = reg.doors[id]
    reg.states[id] = reg.states[id] == "open" and "closed" or "open"
    out[#out + 1] = { "changed" }
    if reg.states[id] == "open" and d.closeDelay >= 0 then
        out[#out + 1] = { "autoclose", id, M.doorMs(d) + d.closeDelay }
    end
    return out
end

-- door.inc _door_closeDelay ran out; false when it was shut already
function M.autoClose(reg, id)
    if reg.states[id] ~= "open" then
        return false
    end
    reg.states[id] = "closed"
    return true
end

-- What a plain button does: moves its doors, or takes the player to its linked button
-- ({ "teleport", x, y, z, world }). Buttons owned by a handler are left to it.
function M.press(reg, id)
    local out, b = {}, reg.byId[id]
    if not b then
        return out
    end
    for _, did in ipairs(reg.doorsOf[id] or {}) do
        M.toggleDoor(reg, did, out)
    end
    local t = b.to and reg.byId[b.to]
    if t then
        out[#out + 1] = { "teleport", t[1], t[2], t[3], t[4] }
    end
    return out
end

return M
