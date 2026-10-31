-- How one upstream map object is placed on a client. Pure logic; the client passes the resolved SA-MP model id.
-- Object rows are { model, x, y, z, rx, ry, rz, world, interior, range } (tools/convert/maps.py).
local placement = {}
placement.BUILDING_LIMIT = 3000 -- createBuilding rejects |x| or |y| beyond this (the ocean rigs are objects)
placement.OBJECT_MODEL_MAX = 397 -- default.ide models (weapons etc.): createBuilding rejects part of this range
placement.FRAME_BUDGET_MS = 5 -- build time spent per frame while the world is being created
-- GTA:SA object.dat 6:SWINGDOOR models (dynamic2.ide Gen_doorINT01..05, Gen_doorEXT10): createBuilding makes them
-- rigid walls, and setElementFrozen locks their hinge, so they must be unfrozen CObjects to swing open.
placement.SWING_DOORS = {
    [1491] = true,
    [1492] = true,
    [1494] = true,
    [1499] = true,
    [1502] = true,
    [1523] = true,
}

-- Wire fence panels of the roadblocks: createBuilding cannot break, so they are objects with setObjectBreakable.
placement.BREAKABLE = {
    [1651] = true,
}

-- SA-MP window001 and lsmall_window01: upstream glazes the house shells with them, but the shells now carry their own
-- glass (tools/glaze_house_windows.py), so a pane inside one of the openings in shared/glazed_windows.lua is dropped.
placement.PANES = {
    [19466] = true,
    [19325] = true,
}
placement.SHELL_REACH = 20 -- metres from a shell's origin to its farthest window, with margin
-- how far a pane's centre may sit past the end of an opening and still be the one upstream put in it: a pane slid
-- 0.13 to 0.8 m along the wall hangs over the brick beside the glass
placement.PANE_SLIP = 1.0

-- true when pane row p sits in an opening that shell row s glazes; openings = glazed_windows.lua[s[1]]
function placement.inGlazedOpening(p, s, openings)
    local a = math.rad(-s[7])
    local dx, dy = p[2] - s[2], p[3] - s[3]
    local x, y, z = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a), p[4] - s[4]
    for _, w in ipairs(openings) do
        local ox, oy, oz = x - w[1], y - w[2], z - w[3]
        local depth, along = ox * w[4] + oy * w[5], ox * -w[5] + oy * w[4]
        if math.abs(depth) < 0.4 and math.abs(along) <= w[6] + placement.PANE_SLIP and math.abs(oz) <= w[7] + 0.1 then
            return true
        end
    end
    return false
end

-- shell rows of `rows` whose model has an entry in data (glazed_windows.lua, shell_doors.lua), by SHELL_REACH cell
local function shellGrid(rows, data)
    local cell = placement.SHELL_REACH
    local grid = {}
    for _, o in ipairs(rows) do
        if data[o[1]] then
            local key = math.floor(o[2] / cell) .. ":" .. math.floor(o[3] / cell)
            grid[key] = grid[key] or {}
            table.insert(grid[key], o)
        end
    end
    return function(p, fn)
        local cx, cy = math.floor(p[2] / cell), math.floor(p[3] / cell)
        for gx = cx - 1, cx + 1 do
            for gy = cy - 1, cy + 1 do
                for _, s in ipairs(grid[gx .. ":" .. gy] or {}) do
                    local found = fn(s)
                    if found then
                        return found
                    end
                end
            end
        end
        return nil
    end
end

-- rows without the panes the shells glaze themselves, and how many were dropped; glazed = glazed_windows.lua
function placement.dropGlazedPanes(rows, glazed)
    local near = shellGrid(rows, glazed)
    local kept, dropped = {}, 0
    for _, o in ipairs(rows) do
        local glazedBy = placement.PANES[o[1]]
            and near(o, function(s)
                return placement.inGlazedOpening(o, s, glazed[s[1]])
            end)
        if glazedBy then
            dropped = dropped + 1
        else
            kept[#kept + 1] = o
        end
    end
    return kept, dropped
end

-- Gen_doorINT01..05: what upstream hangs in the shells' entrances, 1.5 m by 2.5 m and off their openings; the shells'
-- fitted doors (shell_doors.lua, tools/fit_house_doors.py) take their place.
placement.UPSTREAM_DOORS = {
    [1491] = true,
    [1492] = true,
    [1494] = true,
    [1499] = true,
    [1502] = true,
}
placement.FITTED_DOOR_MIN, placement.FITTED_DOOR_MAX = 20101, 20199 -- their port model ids (models/doors.lua)

-- door row d of shell row s (shell_doors.lua) hung in that copy of the shell; src gives world, interior, range
function placement.hangDoor(s, d, src)
    local c, si = math.cos(math.rad(s[7])), math.sin(math.rad(s[7]))
    local wx, wy = s[2] + d[6] * c - d[7] * si, s[3] + d[6] * si + d[7] * c
    return { d[5], wx, wy, s[4] + d[8], 0, 0, (s[7] + d[9]) % 360, src[8], src[9], src[10] }
end

-- which of doors (shell_doors.lua[s[1]]) upstream's door row p is, in shell row s's copy, or nil
function placement.fittedDoor(p, s, doors)
    local a = math.rad(-s[7])
    local dx, dy = p[2] - s[2], p[3] - s[3]
    local x, y, z = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a), p[4] - s[4]
    local rz = (p[7] - s[7]) % 360
    for k, d in ipairs(doors) do
        local turn = math.abs((rz - d[4] + 180) % 360 - 180)
        if math.abs(x - d[1]) < 0.3 and math.abs(y - d[2]) < 0.3 and math.abs(z - d[3]) < 0.3 and turn < 5 then
            return k
        end
    end
    return nil
end

-- rows with upstream's doors in the shells' entrances swapped for the fitted ones, and a fitted door hung in every
-- entrance upstream left empty in its copy of the shell; returns the rows, how many were swapped and how many added
function placement.fitShellDoors(rows, doors)
    local near = shellGrid(rows, doors)
    local out, swapped, hung = {}, 0, {}
    for i, o in ipairs(rows) do
        local fit = placement.UPSTREAM_DOORS[o[1]]
            and near(o, function(s)
                local k = placement.fittedDoor(o, s, doors[s[1]])
                if k then
                    hung[s] = hung[s] or {}
                    hung[s][k] = true
                    return placement.hangDoor(s, doors[s[1]][k], o)
                end
            end)
        out[i] = fit or o
        swapped = swapped + (fit and 1 or 0)
    end
    local added = 0
    for _, s in ipairs(rows) do
        for k, d in ipairs(doors[s[1]] or {}) do
            if not (hung[s] and hung[s][k]) then
                out[#out + 1] = placement.hangDoor(s, d, s)
                added = added + 1
            end
        end
    end
    return out, swapped, added
end

function placement.isSampModel(model)
    return model >= 18631 or (model >= 11682 and model <= 11753)
end

function placement.isSwingDoor(model)
    return placement.SWING_DOORS[model] == true
        or (model >= placement.FITTED_DOOR_MIN and model <= placement.FITTED_DOOR_MAX)
end

function placement.isBreakable(model)
    return placement.BREAKABLE[model] == true
end

-- SA-MP virtual world / interior (-1 = any) -> MTA dimension / interior
function placement.where(world, interior)
    local dim = (world and world > 0) and world or 0
    local int = (interior and interior > 0) and interior or 0
    return dim, int
end

-- "building" (static, cheapest), "object" (dimensioned, interior, far away, default.ide or SA-MP model) or
-- "skip" (SA-MP model with no loaded replacement: a stand-in would be wrong in a map, so nothing is placed)
function placement.kind(o, sampId)
    local model = o[1]
    if placement.isSampModel(model) then
        if not sampId then
            return "skip"
        end
        return "object" -- allocated ids are not vanilla models, which is all createBuilding accepts
    end
    if math.abs(o[2]) > placement.BUILDING_LIMIT or math.abs(o[3]) > placement.BUILDING_LIMIT then
        return "object"
    end
    local dim, int = placement.where(o[8], o[9])
    if dim ~= 0 or int ~= 0 then
        return "object"
    end
    if model <= placement.OBJECT_MODEL_MAX or placement.isSwingDoor(model) or placement.isBreakable(model) then
        return "object"
    end
    return "building"
end

-- counts per kind for a zone's object list; resolve(model) -> loaded id or false
function placement.tally(objects, resolve)
    local t = { building = 0, object = 0, skip = 0 }
    for _, o in ipairs(objects) do
        local k = placement.kind(o, placement.isSampModel(o[1]) and resolve(o[1]) or nil)
        t[k] = t[k] + 1
    end
    return t
end

return placement
