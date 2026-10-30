-- The Firework Box (upstream item/firework.pwn): a Fire Lighter used on one lying in the world plants it, and 6 s
-- later a rocket climbs 10 m and bursts in a sequence of sparks, each spark flying off and bursting again. Upstream
-- moves SA-MP objects (the rocket 345 and the particle objects 18670 camflash, 18688 fire, 18724 shootlight); the port
-- draws the same flight on every client, with GTA's effects of the same names.
local M = {}

M.COOLDOWN_MS = 3000 -- between launches, shared by every box (upstream fwk_CooldownTick)
M.FUSE_MS = 6000 -- from the lighter to the launch
M.SPEED = 20.0 -- metres a second, every projectile
M.MAX_PROJECTILES = 64 -- in flight at once; a burst past it loses the rest (upstream MAX_PROJECTILE)
M.ROCKET_MODEL = 345

-- upstream fwk_ExplosionTypes, 0-based as there: the effects a spark is drawn with (one picked at random), its
-- elevation, distance and how many sparks one burst gives
M.EXPLOSIONS = {
    [0] = { effects = { M.ROCKET_MODEL }, elevation = 60.0, distance = 20.0, spread = 4 },
    [1] = { effects = { "shootlight" }, elevation = 45.0, distance = 50.0, spread = 3 },
    [2] = { effects = { "fire" }, elevation = 45.0, distance = 6.0, spread = 4 },
    [3] = { effects = { "camflash" }, elevation = 45.0, distance = 6.0, spread = 4 },
}

-- upstream fwk_ExplosionSequences: which explosion each generation of a sequence bursts into, -1 ends it
M.SEQUENCES = {
    [0] = { 3 },
    [1] = { 3, 1, 2 },
    [2] = { 1, 0 },
}

local function rad(d)
    return d * math.pi / 180
end

-- where a projectile from (x, y, z) heading `rotation` at `elevation` ends after `distance`; upstream rolls its
-- -10..9 degree wobble on the elevation separately for each axis. randInt(n) gives 0..n-1.
function M.target(x, y, z, rotation, elevation, distance, randInt)
    local ex = rad(elevation + randInt(20) - 10)
    local ey = rad(elevation + randInt(20) - 10)
    local ez = rad(elevation + randInt(20) - 10)
    local tx = x + distance * math.sin(rad(rotation)) * math.cos(ex)
    local ty = y + distance * math.cos(rad(rotation)) * math.cos(ey)
    local tz = z + distance * math.sin(ez)
    return tx, ty, tz
end

-- aim = { rotation, elevation, distance }
local function projectile(look, x, y, z, aim, sequence, index, randInt)
    local tx, ty, tz = M.target(x, y, z, aim[1], aim[2], aim[3], randInt)
    local d = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2 + (tz - z) ^ 2)
    local p = { look = look, from = { x, y, z }, to = { tx, ty, tz }, sequence = sequence, index = index }
    p.ms = math.max(1, math.floor(d / M.SPEED * 1000 + 0.5))
    return p
end

-- upstream FireworkLaunch: the rocket from the box, straight up 10 m, sequence 1
function M.launch(x, y, z, randInt)
    return projectile(M.ROCKET_MODEL, x, y, z, { 0.0, 90.0, 10.0 }, 1, 0, randInt)
end

-- upstream OnDynamicObjectMoved: the sparks a projectile bursts into where it stopped (none at the sequence's end)
function M.burst(p, randInt)
    local seq = M.SEQUENCES[p.sequence]
    local kind = seq and seq[p.index + 1]
    local ex = kind and M.EXPLOSIONS[kind]
    if not ex then
        return {}
    end
    local step = math.floor(360 / ex.spread)
    local offset = randInt(step)
    local x, y, z = p.to[1], p.to[2], p.to[3]
    local out = {}
    for j = 0, ex.spread - 1 do
        local look = ex.effects[randInt(#ex.effects) + 1]
        local aim = { j * step + offset, ex.elevation, ex.distance }
        out[#out + 1] = projectile(look, x, y, z, aim, p.sequence, p.index + 1, randInt)
    end
    return out
end

return M
