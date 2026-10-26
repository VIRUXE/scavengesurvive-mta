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

function roll.sampleList(entries, rng)
    local out = {}
    for _, e in ipairs(entries) do
        if rng() * 100 < e.weight then
            out[#out + 1] = e
        end
    end
    return out
end

function roll.pick(tbl, size, spawnWeight, mult, rng)
    if size == -1 then
        size = 3 + math.floor(rng() * 3)
    end
    size = math.min(size, roll.MAX_PER_SPAWN)
    local sample = roll.sampleList(tbl.entries, rng)
    local out = {}
    for _ = 1, size do
        if #sample == 0 then
            break
        end
        if rng() * 100 <= spawnWeight * mult then -- upstream: skip when frandom(100) > weight * mult
            local idx = math.floor(rng() * #sample) + 1
            out[#out + 1] = sample[idx].uname
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
            out[#out + 1] = sample[math.floor(rng() * #sample) + 1].uname
        end
    end
    return out
end

-- Computes the initial JSON string for loot-spawned ammo tins and calibre weapons (core/weapon/{loot,ammunition}.pwn)
-- and liquid containers (itemtype/liquid-container.pwn OnItemCreateInWorld, #122).
-- Looted items whose data character's medical rules roll (exports.character:medicalLootData, #94).
roll.MEDICAL_DATA = { DoctorBag = true, Pills = true, AutoInjec = true }

function roll.initialItemData(def, tableName, ammoTypes, rand)
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

return roll
