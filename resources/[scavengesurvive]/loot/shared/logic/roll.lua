local roll = {}
roll.MAX_PER_SPAWN = 6

local MILITARY_LOOT = {
    world_police = true,
    world_military = true,
    vehicle_police = true,
    vehicle_military = true,
    airdrop_low_weapons = true,
    airdrop_military_weapons = true,
}

-- Item types a rooftop loot point never rolls: a wheel on a roof is out of reach of any vehicle.
roll.ROOF_BANNED = { Wheel = true }

-- The generic "Wheel" in the loot tables stands for a wheel of any style; what lands in the world is one style, so it
-- fits only the vehicles of that style. Weights are the vehicle types' spawnChance summed per style (data/generated/
-- vehicle_types.lua, models by vehicles/shared/logic/wheels.lua), so wheels drop in step with the cars that need them.
roll.WHEEL_STYLES = {
    { "Saloon", 315 },
    { "Lighttruck", 297 },
    { "Lightvan", 170 },
    { "Classic", 160 },
    { "Truck", 135 },
    { "Alloy", 135 },
    { "Offroad", 121 },
    { "Smallcar", 104 },
    { "Sport", 25 },
    { "Rim", 10 },
}

-- "Wheel" becomes an inflated "Wheel<Style>" picked by those weights; every other uname passes through.
function roll.styleWheel(uname, rng)
    if uname ~= "Wheel" then
        return uname
    end
    local total = 0
    for _, e in ipairs(roll.WHEEL_STYLES) do
        total = total + e[2]
    end
    local r = rng() * total
    for _, e in ipairs(roll.WHEEL_STYLES) do
        r = r - e[2]
        if r < 0 then
            return "Wheel" .. e[1]
        end
    end
    return "Wheel" .. roll.WHEEL_STYLES[1][1]
end

-- The entries that pass their weight roll; `exclude` (a set of unames, optional) leaves types out.
function roll.sampleList(entries, rng, exclude)
    local out = {}
    for _, e in ipairs(entries) do
        if not (exclude and exclude[e.uname]) and rng() * 100 < e.weight then
            out[#out + 1] = e
        end
    end
    return out
end

-- Index of one entry of `sample`: uniform (upstream) without `factor`, otherwise weighted by factor(uname) (> 0).
function roll.choose(sample, rng, factor)
    if not factor then
        return math.floor(rng() * #sample) + 1
    end
    local ws, total = {}, 0
    for i, e in ipairs(sample) do
        ws[i] = math.max(tonumber(factor(e.uname)) or 1, 0.001)
        total = total + ws[i]
    end
    local r = rng() * total
    for i = 1, #sample do
        r = r - ws[i]
        if r < 0 then
            return i
        end
    end
    return #sample
end

-- Variety: a type that spawned a lot lately is picked less. `recent` is its decayed spawn count, `k` how many recent
-- spawns halve its chance (1 / (1 + recent / k)).
function roll.repeatFactor(recent, k)
    k = tonumber(k) or 0
    if k <= 0 then
        return 1
    end
    return 1 / (1 + math.max(tonumber(recent) or 0, 0) / k)
end

-- A count that halves every `halfLife` seconds: decayed from `n` at time `t` to time `now`.
function roll.decay(n, t, now, halfLife)
    if not halfLife or halfLife <= 0 then
        return 0
    end
    return n * 0.5 ^ (math.max(now - t, 0) / halfLife)
end

-- Variety: a point of one of these tables now and then rolls another table instead (percent chances), so the rare
-- medical, police and military loot also turns up away from its 250 or so points.
roll.CROSS_TABLES = {
    world_civilian = {
        { "world_survivor", 3 },
        { "world_medical", 2.5 },
        { "world_industrial", 2.5 },
        { "world_police", 1.5 },
        { "world_military", 0.5 },
    },
    world_industrial = {
        { "world_civilian", 4 },
        { "world_survivor", 3 },
        { "world_military", 1.5 },
        { "world_medical", 1 },
    },
    world_survivor = {
        { "world_military", 4 },
        { "world_medical", 4 },
        { "world_police", 3 },
    },
}

-- The table a point of `name` rolls this time: `name`, or now and then one of its CROSS_TABLES (chances x `mult`).
function roll.crossTable(name, rng, mult)
    local list = roll.CROSS_TABLES[name]
    if not list then
        return name
    end
    mult = tonumber(mult) or 1
    local r = rng() * 100
    for _, e in ipairs(list) do
        r = r - e[2] * mult
        if r < 0 then
            return e[1]
        end
    end
    return name
end

-- Where the refill goes: how many times likelier than a street or factory point a due point of these tables is to be
-- drawn (ADR 0001, correction of 2026-11-20). The 250 or so medical, police and military points are where a player
-- goes for that loot, so they roll soon after they fall due instead of waiting their turn among 11,000 others;
-- survivor points (most of them on rooftops) are worth the climb twice as often.
roll.DRAW_WEIGHTS = {
    world_military = 20,
    world_police = 20,
    world_medical = 20,
    world_survivor = 2,
}

-- SQL for a point's draw weight, given the expression of its table name (names sorted, so the text is stable).
function roll.drawWeightSql(column)
    local names = {}
    for name in pairs(roll.DRAW_WEIGHTS) do
        names[#names + 1] = name
    end
    table.sort(names)
    local parts = { "CASE " .. column }
    for _, name in ipairs(names) do
        parts[#parts + 1] = string.format("WHEN '%s' THEN %d", name, roll.DRAW_WEIGHTS[name])
    end
    parts[#parts + 1] = "ELSE 1 END"
    return table.concat(parts, " ")
end

-- `factor` (optional): uname -> weight for the pick among the entries that passed their roll (roll.repeatFactor).
function roll.pick(tbl, size, spawnWeight, mult, rng, exclude, factor)
    if size == -1 then
        size = 3 + math.floor(rng() * 3)
    end
    size = math.min(size, roll.MAX_PER_SPAWN)
    local sample = roll.sampleList(tbl.entries, rng, exclude)
    local out = {}
    for _ = 1, size do
        if #sample == 0 then
            break
        end
        if rng() * 100 <= spawnWeight * mult then -- upstream: skip when frandom(100) > weight * mult
            local idx = roll.choose(sample, rng, factor)
            out[#out + 1] = roll.styleWheel(sample[idx].uname, rng)
            table.remove(sample, idx)
        end
    end
    return out
end

-- Upstream FillContainerWithLoot: `count` picks, each a uniform choice among the entries that pass their weight
-- roll (with replacement across picks, so a crate can hold two of a kind).
function roll.fill(tbl, count, rng)
    local out = {}
    for _ = 1, count do
        local sample = roll.sampleList(tbl.entries, rng)
        if #sample > 0 then
            out[#out + 1] = roll.styleWheel(sample[math.floor(rng() * #sample) + 1].uname, rng)
        end
    end
    return out
end

-- Computes the initial JSON string for loot-spawned ammo tins and calibre weapons (core/weapon/{loot,ammunition}.pwn)
-- and liquid containers (itemtype/liquid-container.pwn OnItemCreateInWorld, #122).
-- Looted items whose data character's medical rules roll (exports.character:medicalLootData, #94).
roll.MEDICAL_DATA = { DoctorBag = true, Pills = true, AutoInjec = true }

-- A lying Gas Bottle holds 0.5 to 11 kg of propane: the shape and capacity of items/shared/logic/gas.lua.
roll.GAS_BOTTLE = "GasBottle"
roll.GAS_BOTTLE_CAPACITY = 11.0
roll.GAS_BOTTLE_MIN = 0.5

function roll.gasBottleData(rng)
    local gas = roll.GAS_BOTTLE_MIN + rng() * (roll.GAS_BOTTLE_CAPACITY - roll.GAS_BOTTLE_MIN)
    return string.format('{"gas":%.1f}', gas)
end

function roll.initialItemData(def, tableName, ammoTypes, rand)
    if type(def) == "table" and def.uname == roll.GAS_BOTTLE then
        return roll.gasBottleData(rand or math.random)
    end
    if type(def) ~= "table" or type(def.categoryData) ~= "table" then
        return nil
    end
    local rng = rand or math.random
    if def.category == "liquid" then
        return roll.liquidData(def, rng)
    end
    if def.category == "ammo" and def.categoryData.calibre then
        local cap = math.max(1, math.floor(tonumber(def.categoryData.rounds) or 1))
        local rounds = cap <= 1 and 1 or rng(1, cap - 1)
        return string.format('{"rounds":%d}', rounds)
    end
    if def.category == "weapon" and def.categoryData.calibre and not def.categoryData.liquid then
        local magSize = math.max(0, math.floor(tonumber(def.categoryData.magSize) or 0))
        local mag
        if MILITARY_LOOT[tableName] then
            local r = rng(0, 99)
            if r < 30 then
                mag = 0
            elseif r < 50 then
                mag = magSize > 1 and rng(0, magSize - 1) or 0
            else
                mag = magSize
            end
        else
            mag = magSize > 1 and rng(0, magSize - 1) or 0
        end
        if mag > 0 and type(ammoTypes) == "table" and #ammoTypes > 0 then
            local ammoItem = ammoTypes[rng(1, #ammoTypes)]
            return string.format('{"mag":%d,"reserve":0,"ammoItem":%q}', mag, ammoItem)
        end
        return '{"mag":0,"reserve":0}'
    end
    return nil
end

-- Every listed liquid whose chance beats a 0-99 roll is a candidate; one of them fills the container to a random
-- level (upstream frandom(capacity)). nil when none qualifies: the container spawns empty. rng(a, b) is an integer
-- in [a, b], rng() a float in [0, 1). items/shared/logic/liquids.lua reads the { amount, liquid } this writes.
function roll.liquidData(def, rng)
    rng = rng or math.random
    local list = def.categoryData and def.categoryData.liquids
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    local candidates = {}
    for _, entry in ipairs(list) do
        if rng(0, 99) <= (tonumber(entry[2]) or 0) then
            candidates[#candidates + 1] = entry[1]
        end
    end
    if #candidates == 0 then
        return nil
    end
    local capacity = tonumber(def.categoryData.capacity) or 0
    return string.format('{"amount":%.3f,"liquid":%q}', rng() * capacity, candidates[rng(1, #candidates)])
end

-- Laying loot items (tools/spawn_ground.py writes the data). ground.s[n] are the slots of a roll of n items (item i
-- at angle i * 360 / n, 0.6 m out), ground.s[MAX_PER_SPAWN + 1] an outer ring with room for crowded rolls (false where
-- it leaves the point's surface). A slot is { dx, dy, z, nx, ny, small, medium, long, large }: its offset from the
-- point, the ground's height and normal there, and per item size class a bitmask of the 16 headings k * 22.5 in which
-- an item of that class fits without touching a wall, step or pole. An item type's rest data
-- (loot/shared/item_rest.lua) is { base, cx, cy, class, longX, sx, sy, sz }: how far its origin sits above its lowest
-- point, its footprint's centre and size in its own frame, its size class (0: bigger than the checks), whether its
-- long side is its own x axis, and its height.
roll.HEADINGS = 16
roll.GAP = 0.03 -- metres kept between two items' footprints
roll.LEVEL = 1.0 -- items further apart than this vertically are on different floors and never conflict
roll.LEAN_MAX = 35 -- degrees: an item that would rest steeper than this slides off and lies level on top instead
local DEFAULT_REST = { 0, 0, 0, 0, 0, 0.4, 0.4, 0.3 }

-- Headings (degrees) an item may take on a slot: the free ones of its class, each also turned around; nil when its
-- class has none or it has no class (any heading is as good).
function roll.freeHeadings(slot, rest)
    local class, longX = rest[4] or 0, rest[5] or 0
    local mask = class > 0 and tonumber(slot[5 + class]) or 0
    local out = {}
    for k = 0, roll.HEADINGS - 1 do
        if math.floor(mask / 2 ^ k) % 2 == 1 then
            -- the box was tested with its length along the heading; an item long on its own x axis turns 90 more
            local h = k * 360 / roll.HEADINGS + (longX == 1 and 90 or 0)
            out[#out + 1] = h % 360
            out[#out + 1] = (h + 180) % 360
        end
    end
    return #out > 0 and out or nil
end

-- The item's origin when it lies on `slot` at heading rz: footprint centred on the slot (when its class was checked),
-- its origin `base` out along the normal so the item tilted to the ground (items/client/world.lua turns it by
-- ground_nx/ny about its origin) touches it; the client adds modelz back. Returns x, y, z, nx, ny (nil on flat ground).
function roll.layAt(px, py, slot, rest, modelz, rz, centred)
    local dx, dy, gz, nx, ny = slot[1], slot[2], slot[3], slot[4], slot[5]
    local base, cx, cy = rest[1], centred and rest[2] or 0, centred and rest[3] or 0
    local r = math.rad(rz)
    local c, s = math.cos(r), math.sin(r)
    -- right = (cos rz, sin rz), forward = (-sin rz, cos rz)
    local ox, oy = cx * c - cy * s, cx * s + cy * c
    local nz = math.sqrt(math.max(0, 1 - nx * nx - ny * ny))
    local x, y, z = px + dx - ox + nx * base, py + dy - oy + ny * base, gz + nz * base - modelz
    if nx * nx + ny * ny < 0.0025 then
        return x, y, z, nil, nil
    end
    return x, y, z, nx, ny
end

-- An item's footprint on the ground plan: its rectangle around origin (x, y) at heading rz, with z (the ground it lies
-- on) for the floor test and `top`, the height of its highest point (z plus its height unless given).
function roll.footprint(x, y, z, rz, rest, top)
    rest = rest or DEFAULT_REST
    local r = math.rad(rz or 0)
    local c, s = math.cos(r), math.sin(r)
    local cx, cy = rest[2] or 0, rest[3] or 0
    return {
        x = x + cx * c - cy * s,
        y = y + cx * s + cy * c,
        z = z or 0,
        top = top or ((z or 0) + (rest[8] or 0.3)),
        hx = (rest[6] or 0.4) / 2,
        hy = (rest[7] or 0.4) / 2,
        c = c,
        s = s,
    }
end

-- Do two footprints come within `gap` of each other (separating axis test on their four edge directions)?
function roll.overlaps(a, b, gap)
    if math.abs(a.z - b.z) > roll.LEVEL then
        return false
    end
    local dx, dy = b.x - a.x, b.y - a.y
    for _, ax in ipairs({ { a.c, a.s }, { -a.s, a.c }, { b.c, b.s }, { -b.s, b.c } }) do
        local function radius(f)
            return f.hx * math.abs(f.c * ax[1] + f.s * ax[2]) + f.hy * math.abs(-f.s * ax[1] + f.c * ax[2])
        end
        if math.abs(dx * ax[1] + dy * ax[2]) > radius(a) + radius(b) + gap then
            return false
        end
    end
    return true
end

-- the four corners of a footprint, in order around it
local function corners(fp)
    local ax, ay, bx, by = fp.c * fp.hx, fp.s * fp.hx, -fp.s * fp.hy, fp.c * fp.hy
    return {
        { fp.x - ax - bx, fp.y - ay - by },
        { fp.x + ax - bx, fp.y + ay - by },
        { fp.x + ax + bx, fp.y + ay + by },
        { fp.x - ax + bx, fp.y - ay + by },
    }
end

-- the height of a footprint's top at (x, y): its top plane when it has one (a lying item, tilted or not), else `top`
local function topAt(fp, x, y)
    if fp.h then
        return fp.h + fp.gx * (x - fp.x) + fp.gy * (y - fp.y)
    end
    return fp.top
end

-- A lying item's footprint with its top face as a plane, from its row: origin (x, y, z) with the type's modelz
-- already added back, heading rz, tilted by its ground normal (nx, ny; 0 when it lies level). Its underside passes
-- `base` under the origin along the normal and its top is `height` over that, so a leaning item's top is low at its
-- low end and high at its raised one, not its highest point everywhere.
function roll.lyingFootprint(x, y, z, rz, rest, nx, ny)
    rest = rest or DEFAULT_REST
    nx, ny = tonumber(nx) or 0, tonumber(ny) or 0
    local nz = math.sqrt(math.max(0.01, 1 - nx * nx - ny * ny))
    local base, height = rest[1] or 0, rest[8] or 0.3
    local ux, uy, uz = x - nx * base, y - ny * base, z - nz * base
    local fp = roll.footprint(x, y, uz, rz, rest)
    fp.gx, fp.gy = -nx / nz, -ny / nz
    fp.z = uz + fp.gx * (fp.x - ux) + fp.gy * (fp.y - uy) -- its underside under the footprint's centre
    fp.h = fp.z + height / nz
    local top = -math.huge
    for _, p in ipairs(corners(fp)) do
        top = math.max(top, topAt(fp, p[1], p[2]))
    end
    fp.top = top
    return fp
end

-- polygon (list of {x, y}) clipped to footprint fp's rectangle (Sutherland-Hodgman over its four edges)
local function clipTo(poly, fp)
    local planes = {
        { fp.c, fp.s, fp.hx },
        { -fp.c, -fp.s, fp.hx },
        { -fp.s, fp.c, fp.hy },
        { fp.s, -fp.c, fp.hy },
    }
    for _, pl in ipairs(planes) do
        local out = {}
        local n = #poly
        for i = 1, n do
            local a, b = poly[i], poly[i % n + 1]
            local da = pl[3] - ((a[1] - fp.x) * pl[1] + (a[2] - fp.y) * pl[2])
            local db = pl[3] - ((b[1] - fp.x) * pl[1] + (b[2] - fp.y) * pl[2])
            if da >= 0 then
                out[#out + 1] = a
            end
            if (da >= 0) ~= (db >= 0) then
                local t = da / (da - db)
                out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
            end
        end
        poly = out
        if #poly == 0 then
            break
        end
    end
    return poly
end

-- The plane h0 + gx * dx + gy * dy (dx, dy from the footprint's centre) that lies on or over every support point
-- { dx, dy, h } and is lowest at the centre: where a rigid flat item comes to rest on them, its centre of mass as low
-- as it can go. A small linear programme in (h0, gx, gy); its optimum stands on three of the points whose triangle holds
-- the centre (the weight between its supports), so every such triple is tried and the lowest one over all points kept.
-- Returns h0, gx, gy, or nil when no triple holds it (never with the footprint's own corners among the points).
local function restingPlane(pts)
    local n, EPS = #pts, 1e-4
    local best
    for i = 1, n - 2 do
        local a = pts[i]
        for j = i + 1, n - 1 do
            local b = pts[j]
            local abx, aby = b[1] - a[1], b[2] - a[2]
            for k = j + 1, n do
                local c = pts[k]
                local acx, acy = c[1] - a[1], c[2] - a[2]
                local det = abx * acy - aby * acx
                if math.abs(det) > 1e-6 then
                    -- the centre (0, 0) in barycentric terms: inside (or on) the triangle when all three are >= 0
                    local u = (-a[1] * acy - -a[2] * acx) / det
                    local v = (abx * -a[2] - aby * -a[1]) / det
                    if u >= -EPS and v >= -EPS and u + v <= 1 + EPS then
                        local h0 = a[3] + u * (b[3] - a[3]) + v * (c[3] - a[3])
                        if not best or h0 < best[1] - EPS then
                            local dh1, dh2 = b[3] - a[3], c[3] - a[3]
                            local gx = (dh1 * acy - dh2 * aby) / det
                            local gy = (abx * dh2 - acx * dh1) / det
                            local ok = true
                            for m = 1, n do
                                local p = pts[m]
                                if h0 + gx * p[1] + gy * p[2] < p[3] - EPS then
                                    ok = false
                                    break
                                end
                            end
                            if ok then
                                best = { h0, gx, gy }
                            end
                        end
                    end
                end
            end
        end
    end
    if best then
        return best[1], best[2], best[3]
    end
    return nil
end

-- Lay an item on `slot` at heading rz where it comes to rest on the ground and on what of `placed` its footprint
-- overlaps, as a rigid flat body would: the support points are its footprint's corners on the ground and the corners of
-- each overlapped item's top face that fall inside it (with where their edges cross its own), at the height that face
-- has there, tilted as that item lies; it settles on the plane over all of them lowest at its centre (restingPlane).
-- Dropped on a pile of gates it leans on the edge that really holds it, or lies across their tops when they hold it
-- level; never through them. Steeper than LEAN_MAX (a small item against a tall one) it would slide off, so it lies
-- level on the highest point under it. Returns x, y, z, rz, nx, ny and its footprint, carrying its top face as a plane
-- so what lands next rests on it as it lies.
function roll.settle(px, py, slot, rest, modelz, rz, centred, placed)
    local x, y, z, nx, ny = roll.layAt(px, py, slot, rest, modelz, rz, centred)
    local gz = slot[3]
    local fp = roll.footprint(x, y, gz, rz, rest)
    local supports = {}
    for _, o in ipairs(placed) do
        if roll.overlaps(fp, o, 0) and o.top > gz + 0.02 then
            supports[#supports + 1] = o
        end
    end
    if #supports == 0 then
        return x, y, z, rz, nx, ny, fp
    end
    local base, height = rest[1] or 0, rest[8] or 0.3
    local snx, sny = slot[4] or 0, slot[5] or 0
    local snz = math.sqrt(math.max(0.01, 1 - snx * snx - sny * sny))
    local ggx, ggy = -snx / snz, -sny / snz
    local pts = {}
    for _, p in ipairs(corners(fp)) do
        local dx, dy = p[1] - fp.x, p[2] - fp.y
        pts[#pts + 1] = { dx, dy, gz + ggx * dx + ggy * dy }
    end
    local highest = gz
    for _, o in ipairs(supports) do
        for _, p in ipairs(clipTo(corners(o), fp)) do
            local h = topAt(o, p[1], p[2])
            pts[#pts + 1] = { p[1] - fp.x, p[2] - fp.y, h }
            highest = math.max(highest, h)
        end
    end
    -- its origin without the ground's lean (layAt set it `base` out along the ground's normal)
    local ox, oy = x - snx * base, y - sny * base
    local h0, gx, gy = restingPlane(pts)
    if not h0 or math.atan(math.sqrt(gx * gx + gy * gy)) > math.rad(roll.LEAN_MAX) then
        -- it would slide off: level on the highest point under it
        fp.z, fp.h, fp.gx, fp.gy, fp.top = highest, highest + height, 0, 0, highest + height
        return ox, oy, highest + base - modelz, rz, nil, nil, fp
    end
    local len = math.sqrt(1 + gx * gx + gy * gy)
    local tnx, tny, tnz = -gx / len, -gy / len, 1 / len
    local under = h0 + gx * (ox - fp.x) + gy * (oy - fp.y)
    fp.z, fp.gx, fp.gy, fp.h = h0, gx, gy, h0 + height * len
    local top = -math.huge
    for _, p in ipairs(corners(fp)) do
        top = math.max(top, topAt(fp, p[1], p[2]))
    end
    fp.top = top
    if tnx * tnx + tny * tny < 0.0025 then
        return ox, oy, under + base - modelz, rz, nil, nil, fp
    end
    return ox + tnx * base, oy + tny * base, under + tnz * base - modelz, rz, tnx, tny, fp
end

local function worldCandidates(ground, own)
    local cands, seen = {}, { [("%g,%g"):format(own[1], own[2])] = true }
    for _, ring in ipairs(ground.s) do
        for _, slot in ipairs(ring) do
            if type(slot) == "table" and #slot >= 5 then
                local key = ("%g,%g"):format(slot[1], slot[2])
                if not seen[key] then
                    seen[key] = true
                    local d = (slot[1] - own[1]) ^ 2 + (slot[2] - own[2]) ^ 2
                    cands[#cands + 1] = { slot = slot, d = d }
                end
            end
        end
    end
    return cands
end

local function nearestFirst(a, b)
    return a.d < b.d
end

-- Prefer the authored slot and rolled heading. Search other slots and widen the search across the same surface
-- when the pose is obstructed. Keep the nearest world-clear pose in reserve if other loot crowds every fit.
roll.WORLD_SEARCH_RADIUS = 4.5
local SEARCH_RADII = { 0.5, 1, 1.5, 2.25, 3.25, roll.WORLD_SEARCH_RADIUS }
local SEARCH_STEP = 0.35
local SEARCH_HEADINGS = { 0, 22.5, -22.5, 45, -45, 67.5, -67.5, 90 }

function roll.placeWorldItem(px, py, ground, n, i, rest, modelz, rz, placed, world, boxClear)
    local own = ground.s[n] and ground.s[n][i]
    if type(own) ~= "table" or #own < 5 then
        local angle = math.rad(i * 360 / n)
        own = { math.cos(angle) * 0.6, math.sin(angle) * 0.6, ground.z }
    end
    local reserve
    local function trySlot(dx, dy)
        local hz, nx, ny, nz = world.below(px + dx, py + dy, own[3], SEARCH_STEP, SEARCH_STEP)
        if not hz or math.abs(hz - own[3]) > SEARCH_STEP or nz < 0.65 then
            return nil
        end
        local slot = { dx, dy, hz, nx, ny }
        for _, offset in ipairs(SEARCH_HEADINGS) do
            local heading = (rz + offset) % 360
            local x, y, z, sx, sy = roll.layAt(px, py, slot, rest, modelz, heading, true)
            local fp = roll.lyingFootprint(x, y, z + modelz, heading, rest, sx, sy)
            local overlaps = false
            for _, other in ipairs(placed) do
                if roll.overlaps(fp, other, roll.GAP) then
                    overlaps = true
                    break
                end
            end
            if
                (not overlaps or not reserve)
                and boxClear(rest, x, y, z + modelz, heading, sx or 0, sy or 0, world.clear)
            then
                local candidate = { x = x, y = y, z = z, rz = heading, nx = sx, ny = sy, fp = fp }
                if not overlaps then
                    return candidate
                end
                reserve = candidate
            end
        end
        return nil
    end

    local fit = trySlot(own[1], own[2])
    if not fit then
        local cands = worldCandidates(ground, own)
        for _, radius in ipairs(SEARCH_RADII) do
            for k = 0, 11 do
                local angle = k * math.pi / 6
                cands[#cands + 1] = {
                    slot = { own[1] + radius * math.cos(angle), own[2] + radius * math.sin(angle) },
                    d = radius * radius,
                }
            end
        end
        table.sort(cands, nearestFirst)
        for _, cand in ipairs(cands) do
            fit = trySlot(cand.slot[1], cand.slot[2])
            if fit then
                break
            end
        end
    end
    fit = fit or reserve
    if fit then
        placed[#placed + 1] = fit.fp
        return fit.x, fit.y, fit.z, fit.rz, fit.nx, fit.ny
    end
end

-- The measured slots also work when live world collision is unavailable. When all slots are crowded, settle on
-- the existing items instead of losing the roll.
function roll.placeItem(px, py, ground, n, i, rest, modelz, rng, placed)
    rest = rest or DEFAULT_REST
    local own = ground.s[n] and ground.s[n][i]
    local cands = {}
    for _, ring in ipairs(ground.s) do
        for _, slot in ipairs(ring) do
            if type(slot) == "table" and #slot >= 5 then
                local d = own and ((slot[1] - own[1]) ^ 2 + (slot[2] - own[2]) ^ 2) or 0
                cands[#cands + 1] = { slot = slot, d = slot == own and -1 or d }
            end
        end
    end
    table.sort(cands, nearestFirst)
    for _, cand in ipairs(cands) do
        local slot = cand.slot
        local heads = roll.freeHeadings(slot, rest)
        local centred = heads ~= nil
        if not heads then
            heads = {}
            for k = 1, 8 do
                heads[k] = math.floor(rng() * 360)
            end
        end
        for k = #heads, 2, -1 do -- shuffle
            local j = math.floor(rng() * k) + 1
            heads[k], heads[j] = heads[j], heads[k]
        end
        for _, rz in ipairs(heads) do
            local x, y, z, nx, ny = roll.layAt(px, py, slot, rest, modelz, rz, centred)
            local fp = roll.footprint(x, y, slot[3], rz, rest)
            local clear = true
            for _, other in ipairs(placed) do
                if roll.overlaps(fp, other, roll.GAP) then
                    clear = false
                    break
                end
            end
            if clear then
                placed[#placed + 1] = fp
                return x, y, z, rz, nx, ny, false
            end
        end
    end
    local slot = (cands[1] or {}).slot or own
    if not slot then
        return nil
    end
    local heads = roll.freeHeadings(slot, rest)
    local rz = heads and heads[math.floor(rng() * #heads) + 1] or math.floor(rng() * 360)
    local x, y, z, lrz, nx, ny, fp = roll.settle(px, py, slot, rest, modelz, rz, heads ~= nil, placed)
    placed[#placed + 1] = fp
    return x, y, z, lrz, nx, ny, true
end

return roll
