-- How open to the outside air a spot is (no MTA calls): rays are cast from it against whatever the caller's
-- ray function tests, and the share that gets away is the place's openness, 0 (sealed) .. 1 (the open air).
-- The server runs it on its collision for the poison, each client on its own for what it draws, so both read a
-- place the same way.
--   ray(x1, y1, z1, x2, y2, z2) -> hx, hy, hz of the first thing hit, or nil when the line is clear
-- No roof overhead is the open air whatever stands around: the gas is heavy and sinks into a yard.
-- Under a roof, a first fan of rays goes out over the upper half around the spot. An opening round a corner is
-- out of its sight, so a second, smaller fan goes out from the far end of the longest few rays (the far corners
-- of the room, the end of a corridor) at half weight.
local RANGE = 25 -- metres a ray runs before it counts as away
local ROOF = 25 -- metres up to look for a roof
local BACK = 0.6 -- metres a second fan starts short of the wall its ray hit
local SECOND_FROM = 4 -- of the longest first rays get a second fan
local SECOND_WEIGHT = 0.5

-- unit directions on rings of the upper half: { elevation in degrees, rays around }
local function ring(list, elevation, n, turn)
    local e = math.rad(elevation)
    local ce, se = math.cos(e), math.sin(e)
    for i = 1, n do
        local a = (i - 1 + turn) * 2 * math.pi / n
        list[#list + 1] = { math.cos(a) * ce, math.sin(a) * ce, se }
    end
    return list
end

local FIRST = ring(ring(ring({}, 4, 12, 0), 28, 8, 0.5), 58, 4, 0)
local SECOND = ring(ring({}, 4, 8, 0.5), 35, 4, 0)

-- Casts the fan from a spot: the share of rays that got away and the rays that hit as { d = distance, hx, hy,
-- hz }. Every ray that got away is added to `away` as { x, y, z (where it started), dx, dy, dz }.
local function cast(ray, dirs, x, y, z, away)
    local hits, n = {}, 0
    for _, d in ipairs(dirs) do
        local hx, hy, hz = ray(x, y, z, x + d[1] * RANGE, y + d[2] * RANGE, z + d[3] * RANGE)
        if hx then
            local dx, dy, dz = hx - x, hy - y, hz - z
            hits[#hits + 1] = { d = math.sqrt(dx * dx + dy * dy + dz * dz), hx, hy, hz }
        else
            n = n + 1
            away[#away + 1] = { x, y, z, d[1], d[2], d[3] }
        end
    end
    return n / #dirs, hits
end

-- Openness 0..1 of the spot, and what the fans found, for drawing: { roof = bool, away = { ray, ... } }, the rays
-- that got away from either fan as cast() lists them.
local function measure(ray, x, y, z)
    if not ray(x, y, z, x, y, z + ROOF) then
        return 1, { roof = false, away = {} }
    end
    local away = {}
    local first, hits = cast(ray, FIRST, x, y, z, away)
    table.sort(hits, function(a, b)
        return a.d > b.d
    end)
    local second, n = 0, 0
    for i = 1, math.min(SECOND_FROM, #hits) do
        local h = hits[i]
        if h.d > BACK * 2 then
            local k = (h.d - BACK) / h.d
            local sx, sy, sz = x + (h[1] - x) * k, y + (h[2] - y) * k, z + (h[3] - z) * k
            second = second + cast(ray, SECOND, sx, sy, sz, away)
            n = n + 1
        end
    end
    if n > 0 then
        first = first + SECOND_WEIGHT * second / n
    end
    return math.min(1, first), { roof = true, away = away }
end

-- Where the outside air comes in: for the rays that got away (measure's away list), the spot where each leaves the
-- roofed place, found by walking out along it until no roof is overhead and halving back to the edge. Rays that
-- climb steeply (a skylight is no doorway) and rays still under a roof at their end are left out; openings closer
-- than MERGE to one already found are the same doorway. At most `limit`, each { x, y, z, ix, iy, iz } with the unit
-- direction pointing back inside.
local STEEP = 0.5 -- dz of a unit direction above which a ray is not followed
local WALK = 3 -- metres between roof tests on the way out
local MERGE = 2.5

local function openings(ray, away, limit)
    local found = {}
    local function roofed(x, y, z)
        return ray(x, y, z, x, y, z + ROOF) ~= nil
    end
    for _, a in ipairs(away) do
        if #found >= limit then
            break
        end
        if a[6] <= STEEP then
            local inside, outside = 0, nil
            for t = WALK, RANGE, WALK do
                if roofed(a[1] + a[4] * t, a[2] + a[5] * t, a[3] + a[6] * t) then
                    inside = t
                else
                    outside = t
                    break
                end
            end
            if outside then
                for _ = 1, 3 do
                    local mid = (inside + outside) / 2
                    if roofed(a[1] + a[4] * mid, a[2] + a[5] * mid, a[3] + a[6] * mid) then
                        inside = mid
                    else
                        outside = mid
                    end
                end
                local x, y, z = a[1] + a[4] * inside, a[2] + a[5] * inside, a[3] + a[6] * inside
                local fresh = true
                for _, o in ipairs(found) do
                    if (o.x - x) ^ 2 + (o.y - y) ^ 2 + (o.z - z) ^ 2 < MERGE * MERGE then
                        fresh = false
                        break
                    end
                end
                if fresh then
                    found[#found + 1] = { x = x, y = y, z = z, ix = -a[4], iy = -a[5], iz = -a[6] }
                end
            end
        end
    end
    return found
end

-- A vehicle's cabin in place of the fan. cabin = { roofless = bool, doors = { state, ... } (MTA door states of the
-- doors the model has: 0 shut, 1 ajar, 2 shut and damaged, 3 ajar and damaged, 4 missing), ratios = { 0..1 open,
-- ... }, windscreen = bool (false when it is gone) }.
-- A missing or open door, a lost windscreen or no cabin at all is the open air. A sound, shut cabin still breathes
-- a little; every bent door that no longer seals lets more in.
local CABIN_SOUND = 0.05
local CABIN_BENT_DOOR = 0.2
local DOOR_AJAR = 0.1 -- open ratio from which a door counts as open

local function cabin(c)
    if c.roofless or c.windscreen == false then
        return 1
    end
    local open = CABIN_SOUND
    for i, state in ipairs(c.doors or {}) do
        if state == 4 or state == 1 or state == 3 or (c.ratios and (c.ratios[i] or 0) > DOOR_AJAR) then
            return 1
        end
        if state == 2 then
            open = open + CABIN_BENT_DOOR
        end
    end
    return math.min(1, open)
end

-- The gas inside an enclosed place follows the gas outside through its openings: it moves towards the outside
-- strength at a rate set by the openness, so a leaky room fills over a minute or so, clears as slowly once the
-- cloud has passed, and a sealed one never fills. Returns the new inside strength after dt seconds.
local LEAK_RATE = 0.15 -- of the gap closed a second at openness 1

local function seep(inside, outside, openness, dt)
    if openness >= 1 then
        return outside
    end
    local k = 1 - math.exp(-LEAK_RATE * openness * dt)
    return inside + (outside - inside) * k
end

return {
    RANGE = RANGE,
    measure = measure,
    openings = openings,
    cabin = cabin,
    seep = seep,
}
