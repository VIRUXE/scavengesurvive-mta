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

-- the lowest studio dimension no occupant holds; used is a set of dimensions
function studio.freeDimension(used)
    local d = studio.DIMENSION_BASE
    while used[d] do
        d = d + 1
    end
    return d
end

return studio
