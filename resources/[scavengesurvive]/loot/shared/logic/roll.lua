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
roll.LEAN_MAX = 35 -- degrees: an item that would lean steeper than this lies flat on top of what it touches
roll.TILT_MAX = math.sin(math.rad(45)) -- the lean and the ground's slope together tilt an item at most 45 degrees
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

-- Lay an item on `slot` at heading rz against the tallest footprint of `placed` it overlaps. It leans when it can rest
-- that way: its low end on the ground, propped on the other item's near edge, which must lie past its own middle (its
-- weight between the two supports) along one of its two axes; the gentler of the two wins, and the lean is folded into
-- the slope normal the client turns the item by. Overlapping by more than that, or steeper than LEAN_MAX (a small item
-- against a tall one), it would tip over onto the other one, so it lies flat on its top: two gates dropped on the same
-- spot stack instead of one standing half up through the other. Returns x, y, z, rz, nx, ny and its footprint, whose
-- `top` is its highest point, so what lands next stacks above it.
function roll.leanOn(px, py, slot, rest, modelz, rz, centred, placed)
    local x, y, z, nx, ny = roll.layAt(px, py, slot, rest, modelz, rz, centred)
    local gz = slot[3]
    local fp = roll.footprint(x, y, gz, rz, rest)
    local under
    for _, o in ipairs(placed) do
        if roll.overlaps(fp, o, 0) and (not under or o.top > under.top) then
            under = o
        end
    end
    local h = under and under.top - gz or 0
    if h <= 0.02 then
        return x, y, z, rz, nx, ny, fp
    end
    local base, height = rest[1] or 0, rest[8] or 0.3
    -- its two axes (the footprint's x and y), each pointing towards what it leans on
    local best
    for _, axis in ipairs({ { fp.c, fp.s, fp.hx * 2 }, { -fp.s, fp.c, fp.hy * 2 } }) do
        local ux, uy, len = axis[1], axis[2], axis[3]
        local d = (under.x - fp.x) * ux + (under.y - fp.y) * uy
        if d < 0 then
            ux, uy, d = -ux, -uy, -d
        end
        -- where along the item (from its low end) the other one's near edge props it up
        local reach = under.hx * math.abs(under.c * ux + under.s * uy)
            + under.hy * math.abs(-under.s * ux + under.c * uy)
        local run = d - reach + len / 2
        if len > 0 and run >= len / 2 then
            local angle = math.atan2(h, run)
            if angle <= math.rad(roll.LEAN_MAX) and (not best or angle < best.angle) then
                best = { ux = ux, uy = uy, len = len, angle = angle }
            end
        end
    end
    if not best then
        -- on top of it, flat
        fp.z, fp.top = under.top, under.top + height
        return x, y, under.top + base - modelz, rz, nil, nil, fp
    end
    local ux, uy, len, angle = best.ux, best.uy, best.len, best.angle
    -- the lean's normal tips away from what it leans on; add the ground's own slope (both small)
    local sa = math.sin(angle)
    nx, ny = -ux * sa + (slot[4] or 0), -uy * sa + (slot[5] or 0)
    local tilt = math.sqrt(nx * nx + ny * ny)
    if tilt > roll.TILT_MAX then -- a lean on a steep slope: never past TILT_MAX in all
        nx, ny = nx * roll.TILT_MAX / tilt, ny * roll.TILT_MAX / tilt
    end
    local nz = math.sqrt(math.max(0, 1 - nx * nx - ny * ny))
    -- the origin sits on the leaning plane, `base` out along its normal
    local along = (x - fp.x) * ux + (y - fp.y) * uy + len / 2
    local plane = gz + math.tan(angle) * math.max(0, along)
    fp.top = gz + math.tan(angle) * len + height -- its raised end
    return x, y, plane + nz * base - modelz, rz, nx, ny, fp
end

-- Lay one item of a roll so it touches nothing in `placed` (footprints already on the ground: this roll, the batch,
-- and items lying nearby). Its own slot first (slot i of the roll's ring), then the point's other slots nearest first;
-- on each, its free headings in random order (eight random ones when its class is unchecked). When nothing is free it
-- leans on what it overlaps on its own slot (roll.leanOn): items may touch, they never vanish. Appends its footprint
-- to `placed` and returns x, y, z, rz, nx, ny, leaning (true when it had to lean).
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
    table.sort(cands, function(a, b)
        return a.d < b.d
    end)
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
    local x, y, z, lrz, nx, ny, fp = roll.leanOn(px, py, slot, rest, modelz, rz, heads ~= nil, placed)
    placed[#placed + 1] = fp
    return x, y, z, lrz, nx, ny, true
end

return roll
