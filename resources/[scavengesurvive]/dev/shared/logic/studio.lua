-- Green-screen photo studio: a closed chroma-green box the client draws around a frozen player in a private
-- dimension, plus a camera that orbits them, so rcon screenshots show only the ped and what it carries.
-- Pure logic: no MTA calls; angles are degrees, yaw 0 puts the camera in front of a ped facing north (+y).
local studio = {}

studio.CENTRE = { x = 0, y = 0, z = 2500 } -- where the ped stands (its origin, about 1 m above its feet)
studio.FEET = 1.0 -- ped origin above the floor
studio.HALF = 6 -- the box spans CENTRE +-HALF on x and y
studio.HEIGHT = 8 -- floor to ceiling
studio.MARGIN = 0.3 -- the camera keeps this far from the walls
studio.DIMENSION_BASE = 60000 -- one dimension per occupant: 60000, 60001, ...
studio.COLOUR = 0xFF00FF00 -- ARGB pure chroma green
studio.FLOOR_MODEL = 8661 -- flat 40 x 20 slab (gnhtelgrnd_lvs), made invisible, so the ped stands instead of falling

-- name -> { yaw, dist, height, lookZ }: height is the camera above the ped origin, lookZ the target above it
studio.PRESETS = {
    front = { 0, 3.5, 0.3, 0.0 },
    back = { 180, 3.5, 0.3, 0.0 },
    left = { 270, 3.5, 0.3, 0.0 },
    right = { 90, 3.5, 0.3, 0.0 },
    threequarter = { 35, 3.2, 0.6, 0.0 },
    top = { 0, 1.2, 3.5, 0.0 },
    face = { 0, 1.0, 0.65, 0.65 },
    hands = { 30, 1.4, 0.1, -0.1 },
}
studio.DEFAULT = "threequarter"

-- the six faces of the box from (x1,y1,z1) to (x2,y2,z2), two triangles each: 36 { x, y, z } vertices
function studio.boxTriangles(x1, y1, z1, x2, y2, z2)
    local c = {
        { x1, y1, z1 },
        { x2, y1, z1 },
        { x2, y2, z1 },
        { x1, y2, z1 },
        { x1, y1, z2 },
        { x2, y1, z2 },
        { x2, y2, z2 },
        { x1, y2, z2 },
    }
    local faces = {
        { 1, 2, 3, 4 }, -- floor
        { 5, 8, 7, 6 }, -- ceiling
        { 1, 5, 6, 2 }, -- south
        { 2, 6, 7, 3 }, -- east
        { 3, 7, 8, 4 }, -- north
        { 4, 8, 5, 1 }, -- west
    }
    local out = {}
    for _, f in ipairs(faces) do
        for _, i in ipairs({ f[1], f[2], f[3], f[1], f[3], f[4] }) do
            out[#out + 1] = { c[i][1], c[i][2], c[i][3] }
        end
    end
    return out
end

-- the studio box around the ped origin (px, py, pz)
function studio.box(px, py, pz)
    local h, floor = studio.HALF, pz - studio.FEET
    return studio.boxTriangles(px - h, py - h, floor, px + h, py + h, floor + studio.HEIGHT)
end

-- camera position and target orbiting the ped origin; returns cx, cy, cz, tx, ty, tz
function studio.cameraMatrix(px, py, pz, yaw, dist, height, lookZ)
    local r = math.rad(yaw)
    return px + dist * math.sin(r), py + dist * math.cos(r), pz + height, px, py, pz + (lookZ or 0)
end

-- Point lights for the ped (createLight lights peds but never objects, so worn items keep the stock shading).
-- The key light sits on the camera's side, up and close, so every preset is lit from the front; the fill comes
-- from the far side at half strength to soften the shadows. Entries: { x, y, z, radius, r, g, b }.
studio.KEY = { dist = 1.6, height = 1.0, radius = 4, colour = { 255, 250, 240 } }
studio.FILL = { yaw = 150, dist = 1.8, height = 0.2, radius = 3.5, colour = { 120, 125, 140 } }

local function lightAt(px, py, pz, yaw, l)
    local r = math.rad(yaw)
    return { px + l.dist * math.sin(r), py + l.dist * math.cos(r), pz + l.height, l.radius, unpack(l.colour) }
end

function studio.lights(px, py, pz, yaw)
    return { lightAt(px, py, pz, yaw, studio.KEY), lightAt(px, py, pz, yaw + studio.FILL.yaw, studio.FILL) }
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- a camera spec from command words: a preset name, or "yaw dist height [lookZ]"; nil and a message on junk.
-- Distance and height are clamped so the camera stays inside the box.
function studio.parseCam(args)
    args = args or {}
    local name = args[1] or studio.DEFAULT
    local p = studio.PRESETS[name]
    local yaw, dist, height, lookZ
    if p then
        yaw, dist, height, lookZ = p[1], p[2], p[3], p[4]
    else
        yaw, dist, height, lookZ = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4] or 0)
        if not yaw or not dist or not height or not lookZ then
            return nil, "usage: <preset|yaw dist height [lookZ]>; presets: " .. studio.presetNames()
        end
    end
    local reach = studio.HALF - studio.MARGIN
    local floor, ceiling = -studio.FEET + studio.MARGIN, studio.HEIGHT - studio.FEET - studio.MARGIN
    return {
        yaw = yaw % 360,
        dist = clamp(dist, 0.3, reach),
        height = clamp(height, floor, ceiling),
        lookZ = clamp(lookZ, floor, ceiling),
    }
end

function studio.presetNames()
    local names = {}
    for k in pairs(studio.PRESETS) do
        names[#names + 1] = k
    end
    table.sort(names)
    return table.concat(names, ", ")
end

-- Model mode: instead of the ped, one or more object models sit on the set (the ped waits out of sight under the
-- floor). MODEL_DROP is how far under; PED_RADIUS is the size of subject the camera presets frame, so a model's
-- camera is the same preset scaled by its own size.
studio.MODEL_DROP = 30
studio.PED_RADIUS = 2.0
studio.MODEL_GAP = 0.15 -- between models in a row, as a fraction of the largest one
studio.MODEL_LIMIT = 12

-- "20245,1337@90/0/0" (or the same as separate words): model ids, each with an optional rotation rx/ry/rz.
-- Returns { { model = id, rx = , ry = , rz = }, ... }, or nil and a message.
function studio.parseModels(spec)
    local list = {}
    for word in tostring(spec or ""):gmatch("[^,%s]+") do
        local id, rot = word:match("^(%d+)@?(.*)$")
        local rx, ry, rz = 0, 0, 0
        if rot and rot ~= "" then
            rx, ry, rz = rot:match("^(-?[%d%.]+)/(-?[%d%.]+)/(-?[%d%.]+)$")
            rx, ry, rz = tonumber(rx), tonumber(ry), tonumber(rz)
        end
        if not id or not rx or not ry or not rz then
            return nil, "usage: <model>[@rx/ry/rz][,<model>...], e.g. 20245,20245@90/0/0"
        end
        list[#list + 1] = { model = tonumber(id), rx = rx, ry = ry, rz = rz }
    end
    if #list == 0 or #list > studio.MODEL_LIMIT then
        return nil, "give 1 to " .. studio.MODEL_LIMIT .. " models"
    end
    return list
end

-- The axis-aligned extents, about the object's origin, of a model box (x1..z2) turned by `m`, an element matrix
-- (rows right, forward, up). Returns { x1, y1, z1, x2, y2, z2 }.
function studio.turnedBounds(x1, y1, z1, x2, y2, z2, m)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, x in ipairs({ x1, x2 }) do
        for _, y in ipairs({ y1, y2 }) do
            for _, z in ipairs({ z1, z2 }) do
                for axis = 1, 3 do
                    local v = x * m[1][axis] + y * m[2][axis] + z * m[3][axis]
                    lo[axis] = math.min(lo[axis], v)
                    hi[axis] = math.max(hi[axis], v)
                end
            end
        end
    end
    return { lo[1], lo[2], lo[3], hi[1], hi[2], hi[3] }
end

-- Lines models up along x, the row centred on the origin in all three axes. `bounds` is a list of turnedBounds
-- results; returns each model's origin as { x, y, z } and the radius of the sphere holding the whole row.
function studio.layoutModels(bounds)
    local largest, width = 0, 0
    for _, b in ipairs(bounds) do
        largest = math.max(largest, b[4] - b[1], b[5] - b[2], b[6] - b[3])
        width = width + (b[4] - b[1])
    end
    local gap = largest * studio.MODEL_GAP
    width = width + gap * (#bounds - 1)
    local origins, x, depth, height = {}, -width / 2, 0, 0
    for i, b in ipairs(bounds) do
        origins[i] = { x - b[1], -(b[2] + b[5]) / 2, -(b[3] + b[6]) / 2 }
        x = x + (b[4] - b[1]) + gap
        depth = math.max(depth, b[5] - b[2])
        height = math.max(height, b[6] - b[3])
    end
    return origins, math.sqrt(width * width + depth * depth + height * height) / 2
end

-- a ped preset scaled to a row of models of that radius, kept inside the box; returns yaw, dist, height, lookZ
function studio.fitCam(cam, radius)
    local scale = math.max(radius, 0.05) / studio.PED_RADIUS
    local reach = studio.HALF - studio.MARGIN
    local floor, ceiling = -studio.FEET + studio.MARGIN, studio.HEIGHT - studio.FEET - studio.MARGIN
    return cam.yaw,
        clamp(cam.dist * scale, 0.1, reach),
        clamp(cam.height * scale, floor, ceiling),
        clamp(cam.lookZ * scale, floor, ceiling)
end

-- the lowest studio dimension no occupant holds; used is a set of dimensions
function studio.freeDimension(used)
    local d = studio.DIMENSION_BASE
    while used[d] do
        d = d + 1
    end
    return d
end

-- rcon "hold <player> <command|key> <ms>" (#98): keeps a bound command and its key marked as held until now + ms;
-- ms = 0 releases it early without pressing the command again.
function studio.holdSet(heldUntil, command, boundKey, now, ms)
    local name = type(command) == "string" and string.lower(command)
    if not name or name == "" then
        return false
    end
    local untilTick = ms > 0 and (now + ms) or nil
    heldUntil[name] = untilTick
    if type(boundKey) == "string" and boundKey ~= "" then
        heldUntil[string.lower(boundKey)] = untilTick
    end
    return ms > 0
end

function studio.holdActive(heldUntil, name, now)
    name = type(name) == "string" and string.lower(name)
    local untilTick = name and heldUntil[name]
    if not untilTick then
        return false
    end
    if now < untilTick then
        return true
    end
    heldUntil[name] = nil
    return false
end

return studio
