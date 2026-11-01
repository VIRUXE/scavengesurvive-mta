-- Choppable trees (upstream core/world/tree.pwn; data/trees.lua, tools/convert/trees.py): GTA's own trees of the
-- species a Chainsaw fells for Wood Logs. Pure rules: finding the tree within reach, the damage a stretch of cutting
-- does, where the logs land and how the fall is drawn.
local M = {}

M.TOOL = "Chainsaw"
M.YIELD = "WoodLog"
M.SKILL = "Forestry"
M.CELL = 16.0 -- grid cell; the widest reach (a 6 m trunk + 1 m) is well inside one cell around
M.REACH_EXTRA = 1.0 -- upstream's tree area: a sphere of the species' diameter + 1 m
M.MAX_DZ = 3.0 -- the tree's origin sits at its foot, the player's a metre up
M.CHECK_MS = 250
M.MAX_MOVE = 0.8 -- metres the player may shift while cutting
M.BASE_MS = 1000 -- one point of chop damage per second before the Forestry skill
M.LOG_SPREAD = 1.5 -- upstream HARVEST_DROP_MAX_SPHERE_SIZE
M.FALL_MS = 4000 -- the felled tree is drawn falling this long before the logs appear
M.RESPAWN_S = 1814400 -- 3 weeks: a tree grows back far more slowly than loot does

-- species fields of data/trees.lua: { diameter, health, chop damage, pieces, fall }
function M.reach(species)
    return species[1] + M.REACH_EXTRA
end

local function cell(v)
    return math.floor(v / M.CELL)
end

-- data = data/trees.lua ({ species = { [model] = row }, trees = { { model, x, y, z, rz }, ... } }) -> the lookup
function M.index(data)
    local grid = {}
    for i, t in ipairs(data.trees) do
        local cx, cy = cell(t[2]), cell(t[3])
        grid[cx] = grid[cx] or {}
        grid[cx][cy] = grid[cx][cy] or {}
        table.insert(grid[cx][cy], i)
    end
    return { species = data.species, trees = data.trees, grid = grid }
end

-- The nearest standing tree whose reach holds (x, y, z); felled = { [tree] = true }. Returns the tree number.
function M.nearest(index, felled, x, y, z)
    local best, bestD2
    local cx, cy = cell(x), cell(y)
    for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
            for _, i in ipairs((index.grid[gx] or {})[gy] or {}) do
                local t = index.trees[i]
                local dx, dy = t[2] - x, t[3] - y
                local d2 = dx * dx + dy * dy
                local reach = M.reach(index.species[t[1]])
                if
                    not felled[i]
                    and d2 <= reach * reach
                    and math.abs(t[4] - z) <= M.MAX_DZ
                    and (not bestD2 or d2 < bestD2)
                then
                    best, bestD2 = i, d2
                end
            end
        end
    end
    return best
end

-- Health taken by `ms` of cutting when each point of chop damage takes `perPointMs` (the skill shortens it).
function M.damage(species, ms, perPointMs)
    return species[3] * ms / perPointMs
end

-- Milliseconds the rest of the tree takes.
function M.remainingMs(species, health, perPointMs)
    return math.ceil(health / species[3] * perPointMs)
end

-- MTA rotation (degrees) that turns a ped at (x, y) towards (tx, ty).
function M.facing(x, y, tx, ty)
    return (-math.deg(math.atan2(tx - x, ty - y))) % 360
end

-- Where the logs of a felled tree land: `pieces` points of { x, y, rz } around (x, y), each within LOG_SPREAD.
function M.drops(pieces, x, y, random)
    local out = {}
    for _ = 1, pieces do
        local angle, dist = random() * 2 * math.pi, random() * M.LOG_SPREAD
        out[#out + 1] = { x = x + dist * math.sin(angle), y = y + dist * math.cos(angle), rz = random() * 360 }
    end
    return out
end

-- How the felled tree is drawn: { ms, rx, ry, dz } as offsets from where it stands (upstream LeanTree + _UpdateTreePos:
-- a rotating tree tips over, a dropping one sinks 20 m while it leans).
function M.fall(kind, random)
    if kind == "zdrop" then
        return { ms = 5000, rx = -10 + random() * 10, ry = -35, dz = -20 }
    end
    return { ms = 3000, rx = 90, ry = 0, dz = 0 }
end

return M
