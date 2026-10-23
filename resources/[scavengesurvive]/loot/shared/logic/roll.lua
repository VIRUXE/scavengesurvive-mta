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

-- Computes the initial JSON string for loot-spawned ammo tins and calibre weapons (core/weapon/{loot,ammunition}.pwn).
function roll.initialItemData(def, tableName, ammoTypes, rand)
    if type(def) ~= "table" or type(def.categoryData) ~= "table" then
        return nil
    end
    local rng = rand or math.random
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

return roll
