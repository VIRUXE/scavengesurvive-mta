-- The toxic cloud as numbers (no MTA calls): a disc of gas that crosses the map in a straight line at a steady
-- speed, so its place at any moment follows from the plan and the seconds since it formed. The gas is heavy: it
-- fills the low ground and thins out above CEILING, so high ground and tall roofs stand clear of it.
-- cloud = { seed, x0, y0, vx, vy, radius, duration } (metres, metres a second, seconds)
local MAP_HALF = 3000 -- the map is 6 km square around the origin
local TARGET = 1500 -- the path passes within this of the map centre
local FALLOFF = 100 -- metres from the rim to the full-strength core
local CEILING = 110 -- metres above sea level: full strength up to here
local CEILING_FADE = 40 -- metres more over which it thins to nothing
local PUFFS = 90 -- billboards a client draws for the whole cloud
local FORM_S = 45 -- seconds a new cloud takes to thicken, and an old one to thin out

-- rng() -> 0..1. The path runs through a point near the map centre in a random direction, from off one edge to
-- off the other.
local function plan(rng, radius, speed, seed)
    local a = rng() * 2 * math.pi
    local dx, dy = math.cos(a), math.sin(a)
    local tx, ty = (rng() * 2 - 1) * TARGET, (rng() * 2 - 1) * TARGET
    local reach = MAP_HALF * 1.2 + radius
    return {
        seed = seed,
        x0 = tx - dx * reach,
        y0 = ty - dy * reach,
        vx = dx * speed,
        vy = dy * speed,
        radius = radius,
        duration = 2 * reach / speed,
    }
end

-- A cloud formed over a point (staff): it starts there and drifts off the map.
local function planAt(rng, radius, speed, seed, x, y)
    local a = rng() * 2 * math.pi
    return {
        seed = seed,
        x0 = x,
        y0 = y,
        vx = math.cos(a) * speed,
        vy = math.sin(a) * speed,
        radius = radius,
        duration = (MAP_HALF * 2.4 + radius) / speed,
    }
end

local function centre(cloud, age)
    return cloud.x0 + cloud.vx * age, cloud.y0 + cloud.vy * age
end

-- How formed the cloud is, 0..1: it thickens over its first FORM_S seconds and thins out over its last.
local function life(cloud, age)
    return math.max(0, math.min(1, math.min(age, cloud.duration - age) / FORM_S))
end

-- Gas strength 0..1 at a point, age seconds after the cloud formed; z nil = at ground level.
local function concentration(cloud, age, x, y, z)
    if not cloud or age < 0 or age > cloud.duration then
        return 0
    end
    local cx, cy = centre(cloud, age)
    local dx, dy = x - cx, y - cy
    local d = math.sqrt(dx * dx + dy * dy)
    if d >= cloud.radius then
        return 0
    end
    local c = math.min(1, (cloud.radius - d) / FALLOFF) * life(cloud, age)
    if z and z > CEILING then
        c = c * math.max(0, 1 - (z - CEILING) / CEILING_FADE)
    end
    return c
end

-- The map strips that stand for the disc: n rows, each { left, bottom, width, height } relative to the centre.
local function strips(radius, n)
    local rows, h = {}, 2 * radius / n
    for i = 1, n do
        local bottom = -radius + (i - 1) * h
        local mid = bottom + h / 2
        local half = math.sqrt(math.max(0, radius * radius - mid * mid))
        rows[i] = { -half, bottom, 2 * half, h }
    end
    return rows
end

-- The same puffs on every client: a small generator seeded by the cloud, so nothing but the seed is sent.
-- Each puff = { ox, oy (from the centre), width, height, base (z of its foot), phase (0..1), shade (0..1) }.
local function puffs(cloud)
    local state = (cloud.seed % 2147483646) + 1
    local function rnd()
        state = (state * 16807) % 2147483647
        return state / 2147483647
    end
    local list = {}
    for i = 1, PUFFS do
        -- a third of them on the rim, so the edge reads as a wall; the rest fill the disc
        local r = i % 3 == 0 and (0.82 + rnd() * 0.16) or math.sqrt(rnd()) * 0.85
        local a = rnd() * 2 * math.pi
        local width = 260 + rnd() * 220
        list[i] = {
            ox = math.cos(a) * r * cloud.radius,
            oy = math.sin(a) * r * cloud.radius,
            width = width,
            height = width * (0.45 + rnd() * 0.25),
            base = -15 + rnd() * 25,
            phase = rnd(),
            shade = rnd(),
        }
    end
    return list
end

return {
    CEILING = CEILING,
    CEILING_FADE = CEILING_FADE,
    plan = plan,
    planAt = planAt,
    centre = centre,
    life = life,
    concentration = concentration,
    strips = strips,
    puffs = puffs,
}
