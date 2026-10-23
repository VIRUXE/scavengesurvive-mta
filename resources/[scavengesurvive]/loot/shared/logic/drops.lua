-- Supply drops and weapons caches, pure logic. Upstream: core/world/supply-crate.pwn (types from
-- core/server/init.pwn:1376-1380, the type cycle, the 50 % "Unknown" announcement, the 3.5 u/s descent from z 1000)
-- and core/world/weapons-cache.pwn (22 + random(11) items, three bearing/distance signals 200 s apart).
local drops = {}

-- DefineSupplyDropType(name, lootindex, interval s, random s, required players)
drops.TYPES = {
    { name = "Food and Medical", table = "airdrop_food_medical", interval = 900, random = 600, required = 3 },
    { name = "Low Grade Weapons", table = "airdrop_low_weapons", interval = 2400, random = 1200, required = 4 },
    { name = "Military Weapons", table = "airdrop_military_weapons", interval = 4200, random = 1800, required = 6 },
    { name = "Industrial Supplies", table = "airdrop_industrial", interval = 2000, random = 900, required = 5 },
    { name = "Ordnance Supplies", table = "airdrop_ordnance", interval = 10800, random = 10800, required = 8 },
}
drops.DROP_HEIGHT = 1000.0 -- crates start here (upstream creates the objects at z 1000)
drops.DROP_SPEED = 3.5 -- units per second
drops.SUPPLY_CRATE = "LargeBox" -- the landed crate is a world safebox item; loot beyond its slots lies around it
drops.CACHE_CRATE = "GunCase"
drops.CACHE_TABLE = "airdrop_military_weapons"
drops.CACHE_SIGNALS = 3
drops.CACHE_SIGNAL_INTERVAL_S = 200
drops.CACHE_REFERENCE_RADIUS = 1000.0
drops.CACHE_CLEAR_RADIUS = 500.0 -- no cache where a player is within this distance
drops.LAND_PUSH_RADIUS = 3.0

-- Per-type timer state: lastDrop (ms tick) and the randomised offset, seeded like upstream so every type is
-- due at start (lastDrop = now - interval) with a random extra wait.
function drops.newTypeState(types, nowMs, rng)
    local st = {}
    for i, t in ipairs(types) do
        st[i] = { lastDrop = nowMs - t.interval * 1000, offset = math.floor(rng() * t.random * 1000) }
    end
    return st
end

-- Upstream SupplyDropTimer type pick: walk the types in order and take the first whose player requirement is
-- met and whose interval + offset has passed. Returns the index or nil.
function drops.pickType(types, st, playerCount, nowMs)
    for i, t in ipairs(types) do
        local s = st[i]
        if playerCount >= t.required and nowMs - s.lastDrop >= t.interval * 1000 + s.offset then
            return i
        end
    end
    return nil
end

function drops.markDropped(types, st, idx, nowMs, rng)
    st[idx].lastDrop = nowMs
    st[idx].offset = math.floor(rng() * types[idx].random * 1000)
end

-- 50 % of announcements name the drop, the rest say "Unknown" (upstream: keeps players guessing).
function drops.announceName(typeName, rng)
    if rng() * 100 < 50 then
        return typeName
    end
    return "Unknown"
end

function drops.descentMs(fromZ, toZ, speed)
    local dist = math.abs((fromZ or drops.DROP_HEIGHT) - (toZ or 0))
    return math.max(1000, math.floor(dist / (speed or drops.DROP_SPEED) * 1000))
end

-- Upstream crate contents: 4 + random(16) items for a supply crate, 22 + random(11) for a weapons cache.
function drops.supplyCount(rng)
    return 4 + math.floor(rng() * 16)
end

function drops.cacheCount(rng)
    return 22 + math.floor(rng() * 11)
end

-- Splits rolled unames between the crate (first `slots` items, one slot each) and the ground around it.
function drops.splitForCrate(unames, slots)
    local inside, around = {}, {}
    for i, u in ipairs(unames) do
        if i <= slots then
            inside[#inside + 1] = u
        else
            around[#around + 1] = u
        end
    end
    return inside, around
end

-- Positions for n ground items in rings around (x, y): 8 per ring, 1.2 m apart in radius.
function drops.ringPositions(x, y, n, rng)
    local out = {}
    for i = 1, n do
        local ring = math.floor((i - 1) / 8)
        local ang = math.rad(((i - 1) % 8) * 45 + rng() * 20)
        local r = 1.5 + ring * 1.2
        out[i] = { x = x + math.cos(ang) * r, y = y + math.sin(ang) * r }
    end
    return out
end

-- Upstream GetAngleToPoint / absoluteangle: compass bearing (0 = north, clockwise) from the reference to the
-- cache, and the 2D distance. Returns bearing in degrees [0, 360) and distance.
function drops.bearing(refX, refY, toX, toY)
    local dx, dy = toX - refX, toY - refY
    local deg = math.deg(math.atan2(dx, dy))
    deg = deg % 360
    return deg, math.sqrt(dx * dx + dy * dy)
end

-- A random cache point other than the cache itself within CACHE_REFERENCE_RADIUS, used as the signal's origin.
function drops.signalReference(points, cacheX, cacheY, rng)
    local candidates = {}
    for _, p in ipairs(points) do
        local d = math.sqrt((p.x - cacheX) ^ 2 + (p.y - cacheY) ^ 2)
        if d > 0.5 and d < drops.CACHE_REFERENCE_RADIUS then
            candidates[#candidates + 1] = p
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[math.floor(rng() * #candidates) + 1]
end

function drops.signalText(ref, cacheX, cacheY)
    local bearing, dist = drops.bearing(ref.x, ref.y, cacheX, cacheY)
    return string.format(" >  [EBS]: WEAPONS CACHE SIGNAL: BEARING: %.1fDEG DISTANCE: %.1fM", bearing, dist)
end

function drops.supplyText(name, location)
    return string.format(' >  [EBS]: SUPPLY DROP: #33CCFF"%s"#FFFF00 INCOMING AT: #FFAA00"%s"', name, location)
end

-- Players standing on the landing spot get pushed LAND_PUSH_RADIUS away (upstream SupplyCrateLand).
function drops.pushOut(px, py, cx, cy, radius)
    local dx, dy = px - cx, py - cy
    local d = math.sqrt(dx * dx + dy * dy)
    if d >= radius then
        return nil
    end
    if d < 0.01 then
        dx, dy, d = 1, 0, 1
    end
    return cx + dx / d * radius, cy + dy / d * radius
end

return drops
