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
-- The crate is a 32-slot container with no item behind it (upstream CreateContainer("Supply Crate", 32) and
-- CreateContainer("Weapon Cache", 32)), opened with the interact key next to its objects: two 3799 crates, the
-- top one upside down, for a supply drop (supply-crate.pwn:261-262) and object 964 for a weapons cache
-- (weapons-cache.pwn:128). Loot that does not fit is simply not created, nothing lies around the crate.
drops.CRATE_SIZE = 32
drops.SUPPLY_OBJECT = 3799
drops.SUPPLY_STACK_Z = 2.465
drops.CACHE_OBJECT = 964
drops.CACHE_Z_OFFSET = -0.044
drops.OPEN_RADIUS = 3.0 -- the button's range in the SIF button library
drops.TITLES = { supply = "Supply Crate", cache = "Weapon Cache" }
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

-- The objects that stand for a crate of `kind` ("supply" / "cache") landed at (x, y, z), in creation order; the
-- first one carries the crate's element data.
function drops.crateObjects(kind, x, y, z)
    if kind == "cache" then
        return { { model = drops.CACHE_OBJECT, x = x, y = y, z = z + drops.CACHE_Z_OFFSET, rx = 0, ry = 0, rz = 0 } }
    end
    return {
        { model = drops.SUPPLY_OBJECT, x = x, y = y, z = z, rx = 0, ry = 0, rz = 0 },
        {
            model = drops.SUPPLY_OBJECT,
            x = x + 0.01,
            y = y + 0.01,
            z = z + drops.SUPPLY_STACK_Z,
            rx = 0,
            ry = 180,
            rz = 0,
        },
    }
end

-- The crate object nearest to (px, py, pz) within OPEN_RADIUS, from { { id, x, y, z }, ... }; nil when none.
function drops.crateAt(crates, px, py, pz)
    local best, bestD = nil, drops.OPEN_RADIUS
    for _, c in ipairs(crates) do
        local dx, dy, dz = c.x - px, c.y - py, c.z - pz
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d <= bestD then
            best, bestD = c, d
        end
    end
    return best
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
