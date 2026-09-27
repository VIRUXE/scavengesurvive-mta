local roll = {}
roll.MAX_PER_SPAWN = 6

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

return roll
