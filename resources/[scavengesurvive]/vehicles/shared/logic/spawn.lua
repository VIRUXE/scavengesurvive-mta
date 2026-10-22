-- Loot vehicle rolls (upstream core/vehicle/spawn.pwn + loot-vehicle.pwn GenerateVehicleData). Pure logic:
-- rng() returns a float in [0,1); `types` is spawn.index(list of data vehicle types).
local spawn = {}
spawn.DEFAULT_CHANCE = 4.0 -- percent per spawn point (setting vehicles.spawn_chance)
spawn.CATEGORY =
    { C = "car", T = "truck", M = "motorbike", B = "pushbike", H = "helicopter", P = "plane", S = "boat", L = "train" }
spawn.SIZE = { S = "small", M = "medium", L = "large" }

function spawn.index(list)
    local byUname = {}
    for _, t in ipairs(list) do
        byUname[t.uname] = t
    end
    return { list = list, byUname = byUname }
end

local function letterSet(text, map)
    local set = {}
    for ch in tostring(text or ""):gmatch(".") do
        if map[ch] then
            set[map[ch]] = true
        end
    end
    return set
end

-- Candidates for a group spawn: the group's types whose category and size are allowed, each kept only when its own
-- spawn chance hits (upstream PickRandomVehicleTypeFromGroup).
function spawn.candidates(row, types, rng)
    local cats, sizes = letterSet(row.categories, spawn.CATEGORY), letterSet(row.sizes, spawn.SIZE)
    local out = {}
    for _, t in ipairs(types.list) do
        if t.group == row.group_name and cats[t.category] and sizes[t.size] and rng() * 100 < t.spawnChance then
            out[#out + 1] = t
        end
    end
    return out
end

-- One spawn point (a vehicle_spawns row) -> { type = t, rz = rz } or nil when nothing spawns.
-- Deviation from upstream: when no candidate passes its chance, upstream reads list[0] of a zeroed array and spawns
-- type 0 (a Bobcat) even at a military spawn; here the point stays empty.
function spawn.roll(row, types, chance, rng)
    if rng() * 100 < 100 - (chance or spawn.DEFAULT_CHANCE) then
        return nil
    end
    local rz = (row.rz + ((rng() < 0.5) and 180 or 0)) % 360
    local t
    if row.type_name and row.type_name ~= false then
        t = types.byUname[row.type_name]
        if not t or rng() * 100 >= t.spawnChance then
            return nil
        end
    else
        local list = spawn.candidates(row, types, rng)
        if #list == 0 then
            return nil
        end
        t = list[math.floor(rng() * #list) + 1]
    end
    return { type = t, rz = rz }
end

-- GenerateVehicleData: health on the SA 0..1000 scale, most vehicles battered
function spawn.health(rng)
    local c = rng() * 100
    if c < 1 then
        return 500 + rng() * 200
    elseif c < 5 then
        return 400 + rng() * 200
    end
    return 300 + rng() * 200
end

-- GenerateVehicleData: nearly every tank is almost empty
function spawn.fuel(maxFuel, rng)
    local c = rng() * 100
    if c < 1 then
        return maxFuel / 2 + rng() * (maxFuel / 2)
    elseif c < 5 then
        return maxFuel / 4 + rng() * (maxFuel / 3)
    elseif c < 10 then
        return maxFuel / 8 + rng() * (maxFuel / 4)
    end
    return rng() * 1.0
end

local function randomList(n, states, rng)
    local out = {}
    for i = 1, n do
        out[i] = math.floor(rng() * states)
    end
    return out
end

-- Visual damage for cars and trucks only (upstream: category below MOTORBIKE); nil for everything else.
-- panels 7 x 0..3, doors 4 x 0..4, lights 4 x 0..1, tires 4 x 0..1 (MTA uses the same state scales).
function spawn.damage(category, rng)
    if category ~= "car" and category ~= "truck" then
        return nil
    end
    return {
        panels = randomList(7, 4, rng),
        doors = randomList(4, 5, rng),
        lights = randomList(4, 2, rng),
        tires = randomList(4, 2, rng),
    }
end

-- Locked at spawn: only vehicles with a tank, only when some door is damaged, then a coin flip (upstream).
function spawn.locked(t, damage, rng)
    if not damage or (t.maxFuel or 0) <= 0 then
        return false
    end
    local anyDoor = false
    for _, d in ipairs(damage.doors) do
        if d > 0 then
            anyDoor = true
        end
    end
    return anyDoor and rng() < 0.5
end

return spawn
