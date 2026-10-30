-- Pure logic for /house (server/houses.lua): the SA-MP house shells the maps place, in a fixed order, and a spot
-- on the ground a couple of metres outside one of a shell's entrances (maps/shared/shell_doors.lua), facing it.
local houses = {}

houses.SHELLS = {
    [19489] = "sfhouse1",
    [19491] = "sfhouse2",
    [19493] = "sfhouse3",
    [19495] = "sfhouse4",
    [19497] = "lvhouse1",
    [19499] = "lvhouse2",
    [19501] = "lvhouse3",
    [19503] = "lvhouse4",
    [19505] = "lshouse1",
    [19507] = "lshouse2",
    [19509] = "lshouse3",
    [19511] = "lshouse4",
}

houses.LEAF_HALF = 0.45 -- a fitted leaf runs along its rz from the hinge; about half its width to the doorway's middle
houses.STAND_OFF = 2.5 -- metres from the doorway to the spot
houses.LIFT = 1.0 -- ped centre above the door's bottom edge (the floor)

-- zones: zone name -> maps/data/<ZONE>.lua table; returns every shell row as
-- { model, name, x, y, z, rz, zone }, zones in name order, rows in file order
function houses.collect(zones)
    local names = {}
    for zone in pairs(zones) do
        names[#names + 1] = zone
    end
    table.sort(names)
    local list = {}
    for _, zone in ipairs(names) do
        for _, o in ipairs(zones[zone].objects or {}) do
            local name = houses.SHELLS[o[1]]
            if name then
                list[#list + 1] = { model = o[1], name = name, x = o[2], y = o[3], z = o[4], rz = o[7], zone = zone }
            end
        end
    end
    return list
end

-- door indices of a shell's entrance list, lowest (ground floor) first, ties in list order
function houses.entrances(doors)
    local order = {}
    for k in ipairs(doors or {}) do
        order[#order + 1] = k
    end
    table.sort(order, function(a, b)
        local za, zb = doors[a][3], doors[b][3]
        if za ~= zb then
            return za < zb
        end
        return a < b
    end)
    return order
end

-- world spot outside entrance d ({ ux, uy, uz, urz, model, x, y, z, rz }) of house h, on the side of the doorway
-- farther from the shell origin, and the ped heading (MTA rz) that faces the doorway: x, y, z, rz
function houses.spotOutside(h, d)
    local r = math.rad(d[9])
    local mx, my = d[6] + math.cos(r) * houses.LEAF_HALF, d[7] + math.sin(r) * houses.LEAF_HALF
    local nx, ny = -math.sin(r), math.cos(r)
    local ax, ay = mx + nx * houses.STAND_OFF, my + ny * houses.STAND_OFF
    local bx, by = mx - nx * houses.STAND_OFF, my - ny * houses.STAND_OFF
    if bx * bx + by * by > ax * ax + ay * ay then
        ax, ay = bx, by
    end
    local c, s = math.cos(math.rad(h.rz)), math.sin(math.rad(h.rz))
    local wx, wy = h.x + ax * c - ay * s, h.y + ax * s + ay * c
    local fx, fy = (mx - ax) * c - (my - ay) * s, (mx - ax) * s + (my - ay) * c
    local heading = math.deg(math.atan2(-fx, fy)) % 360
    return wx, wy, h.z + d[8] + houses.LIFT, heading
end

-- where to stand for house h: outside its nth entrance (1 = lowest), or above the shell origin when it has none;
-- returns x, y, z, rz, the entrance number used (0 without doors) and how many entrances it has
function houses.spot(h, doors, nth)
    local order = houses.entrances(doors)
    if #order == 0 then
        return h.x, h.y, h.z + 2, h.rz, 0, 0
    end
    local n = ((nth or 1) - 1) % #order + 1
    local x, y, z, rz = houses.spotOutside(h, doors[order[n]])
    return x, y, z, rz, n, #order
end

-- next house index for /house <arg> from current (0 = none yet): nil/"next", "prev", a number or a shell name
-- (the next house of that name after current); returns the index, or nil and a reason
function houses.pick(list, current, arg)
    local count = #list
    if count == 0 then
        return nil, "no house shells in the maps"
    end
    current = current or 0
    if arg == nil or arg == "" or arg == "next" then
        return current % count + 1
    end
    if arg == "prev" then
        return current < 2 and count or current - 1
    end
    local n = tonumber(arg)
    if n then
        n = math.floor(n)
        if n < 1 or n > count then
            return nil, string.format("house number out of range 1-%d", count)
        end
        return n
    end
    local name = arg:lower()
    for step = 1, count do
        local i = (current + step - 1) % count + 1
        if list[i].name == name then
            return i
        end
    end
    return nil, string.format("no house named %s", arg)
end

-- "sfhouse2 x3, lshouse1 x20, ..." in name order
function houses.summary(list)
    local counts, names = {}, {}
    for _, h in ipairs(list) do
        if not counts[h.name] then
            names[#names + 1] = h.name
        end
        counts[h.name] = (counts[h.name] or 0) + 1
    end
    table.sort(names)
    local parts = {}
    for _, name in ipairs(names) do
        parts[#parts + 1] = string.format("%s x%d", name, counts[name])
    end
    return table.concat(parts, ", ")
end

return houses
