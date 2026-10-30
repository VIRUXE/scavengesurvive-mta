-- Gardening (upstream core/item/plantpot.pwn and seedbag.pwn, #142): what a bag of Seeds holds, how a Plant Pot
-- takes seeds, water and the knife, how the plant grows step by step and what the pot shows meanwhile.
-- Pure rules; the server applies them to the item rows, the client draws the plant.
local M = {}

-- upstream DefineSeedType in init.pwn's order (the bag's kind is 1-based here): the crop item, the growth steps,
-- the grown plant's model and how far above the pot it stands. "Unknown" kinds grow a bush and no crop.
M.SEEDS = {
    { name = "Tomato", crop = "Tomato", grows = 4, model = 631, offset = 0.90649 },
    { name = "Apple", crop = "RedApple", grows = 5, model = 802, offset = 0.72044 },
    { name = "Apple", crop = "GrnApple", grows = 5, model = 802, offset = 0.72044 },
    { name = "Banana", crop = "Banana", grows = 6, model = 804, offset = 1.31168 },
    { name = "Lemon", crop = "Lemon", grows = 5, model = 810, offset = 0.72044 },
    { name = "Orange", crop = "Orange", grows = 5, model = 810, offset = 0.72044 },
    { name = "Unknown", grows = 0, model = 692, offset = 0.31308 },
    { name = "Unknown", grows = 0, model = 728, offset = 0.34546 },
    { name = "Unknown", grows = 0, model = 801, offset = 0.2129 },
    { name = "Unknown", grows = 0, model = 857, offset = 0.50507 },
    { name = "Unknown", grows = 0, model = 861, offset = -0.12961 },
    { name = "Unknown", grows = 0, model = 863, offset = 0.33455 },
    { name = "Unknown", grows = 0, model = 2194, offset = 0.25344 },
    { name = "Unknown", grows = 0, model = 2238, offset = 0.58121 },
}
M.SPROUT_MODEL, M.SPROUT_RISE = 2194, 0.1966 -- the sprout climbs this far over the growth
M.MAX_SEEDS = 4 -- a looted bag holds random(5) = 0..4 seeds
M.POUR_LITRES = 0.1 -- one pour from a bottle; 1 water per 0.1 L
M.GROW_MS = 600000 -- one growth step (upstream: one per server start)
M.POT, M.BAG = "PlantPot", "SeedBag"

local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end

-- the same small generator the clothes use: a bag's seeds follow from its id until they are written
function M.seeded(seed)
    local s = (math.floor(tonumber(seed) or 0) % 2147483646) + 1
    local function rand()
        s = (16807 * s) % 2147483647
        return (s - 1) / 2147483646
    end
    local function randInt(n)
        return math.min(n, math.floor(rand() * n) + 1)
    end
    return rand, randInt
end

-- { amount, kind } of a Seeds bag: its stored data.seeds, else rolled from its id (0..4 seeds of any kind)
function M.seedsFor(itemId, data)
    local stored = unwrap(data).seeds
    if type(stored) == "table" then
        return { amount = tonumber(stored.amount) or 0, kind = tonumber(stored.kind) or 1 }
    end
    local _, randInt = M.seeded(itemId)
    return { amount = randInt(M.MAX_SEEDS + 1) - 1, kind = randInt(#M.SEEDS) }
end

-- OnItemNameRender: "Seeds (3, Tomato)" or "Seeds (Empty)"
function M.seedLabel(name, seeds)
    local kind = seeds and M.SEEDS[seeds.kind]
    if seeds and seeds.amount > 0 and kind then
        return string.format("%s (%d, %s)", name, seeds.amount, kind.name)
    end
    return name .. " (Empty)"
end

-- a pot's state from its data: { active, kind, water, growth }
function M.pot(data)
    local d = unwrap(data).pot
    d = type(d) == "table" and d or {}
    return {
        active = tonumber(d.active) == 1,
        kind = tonumber(d.kind) or 0,
        water = tonumber(d.water) or 0,
        growth = tonumber(d.growth) or 0,
    }
end

function M.empty()
    return { active = false, kind = 0, water = 0, growth = 0 }
end

-- the data to store for a pot state
function M.encodePot(pot)
    return { active = pot.active and 1 or 0, kind = pot.kind, water = pot.water, growth = pot.growth }
end

-- Seeds on a pot: ok, next pot, next seeds; false when the bag is empty
function M.plant(pot, seeds)
    if not seeds or seeds.amount <= 0 or not M.SEEDS[seeds.kind] then
        return false
    end
    local next_ = { active = true, kind = seeds.kind, water = pot.water, growth = 0 }
    return true, next_, { amount = seeds.amount - 1, kind = seeds.kind }
end

-- A liquid container on a pot: ok, next pot, the container's next data; or false and the toast code.
-- liquids = items/shared/logic/liquids.lua, t = the container's type, data its data.
function M.water(pot, liquids, t, data)
    local amount, liquid = liquids.decode(t, data)
    if not liquid or amount <= 0 then
        return false, "POTBOTEMPTY"
    end
    if liquid ~= "Water" then
        return false, "POTBOTNOWAT"
    end
    local pour = math.min(M.POUR_LITRES, amount)
    local next_ =
        { active = pot.active, kind = pot.kind, water = pot.water + math.floor(pour * 10 + 0.5), growth = pot.growth }
    return true, next_, { amount = amount - pour, liquid = liquid }
end

-- A knife on a pot: ok, the crop uname (nil for a bush), the emptied pot; or false and the toast code.
function M.harvest(pot)
    if not pot.active then
        return false, "POTNOACPLNT"
    end
    local kind = M.SEEDS[pot.kind]
    if not kind then
        return false, "POTINVASEED"
    end
    if pot.growth < kind.grows then
        return false, "POTNOTGROWN"
    end
    return true, kind.crop, M.empty()
end

-- One growth step: watered, the plant drinks and grows; dry, it shrinks and dies at 0.
function M.grow(pot)
    if not pot.active then
        return pot
    end
    local next_ = { active = true, kind = pot.kind, water = pot.water, growth = pot.growth }
    if next_.water > 0 then
        next_.water, next_.growth = next_.water - 1, next_.growth + 1
    else
        next_.growth = next_.growth - 1
    end
    if next_.growth <= 0 then
        return M.empty()
    end
    return next_
end

-- What stands on the pot: model and height above the pot's origin, or nil for nothing (empty, or just planted)
function M.plantObject(pot)
    local kind = pot.active and M.SEEDS[pot.kind]
    if not kind then
        return nil
    end
    if pot.growth >= kind.grows then
        return kind.model, kind.offset
    end
    if pot.growth > 0 then
        return M.SPROUT_MODEL, (M.SPROUT_RISE / kind.grows) * pot.growth
    end
    return nil
end

-- upstream's status dialog lines
function M.status(pot)
    local kind = M.SEEDS[pot.kind]
    return string.format(
        "Active: %s\nSeed type: %s\nWater: %d\nGrowth: %d/%d",
        pot.active and "yes" or "no",
        kind and kind.name or "-",
        pot.water,
        pot.growth,
        kind and kind.grows or 0
    )
end

return M
