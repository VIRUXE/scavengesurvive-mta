-- Clothes types (core/char/clothes.pwn, the DefineClothesType rows in core/server/init.pwn) and the Clothes item.
-- A Clothes item stores the skin it holds as data.skin. Items created without one (loot, drops, crafting, staff)
-- hold a type rolled from their own id with upstream's rule, so the client label and the server swap agree without
-- every creation path writing data; the first swap persists it. Upstream's canWearHats/canWearMasks columns are not
-- carried: every ped model wears gear through skins.lua (#72) and headgear skins have hatless twins (#75).
local M = {}

M.MALE, M.FEMALE = 0, 1
M.HOLD_MS = 3000

-- { model, name, gender, spawn chance }, upstream order
M.TYPES = {
    { 60, "Civilian", 0, 1.0 },
    { 170, "Civilian", 0, 1.0 },
    { 250, "Civilian", 0, 1.0 },
    { 188, "Civilian", 0, 1.0 },
    { 206, "Civilian", 0, 1.0 },
    { 44, "Civilian", 0, 1.0 },
    { 289, "Civilian", 0, 1.0 },
    { 50, "Mechanic", 0, 0.6 },
    { 254, "Biker", 0, 0.3 },
    { 283, "Cop", 0, 0.3 },
    { 287, "Military", 0, 0.2 },
    { 285, "S.W.A.T.", 0, 0.1 },
    { 294, "Triad", 0, 0.2 },
    { 101, "Southclaws", 0, 0.1 },
    { 156, "Morgan Freeman", 0, 0.01 },
    { 192, "Civilian", 1, 1.0 },
    { 93, "Civilian", 1, 1.0 },
    { 233, "Civilian", 1, 1.0 },
    { 193, "Civilian", 1, 1.0 },
    { 90, "Civilian", 1, 1.0 },
    { 190, "Civilian", 1, 1.0 },
    { 195, "Civilian", 1, 1.0 },
    { 41, "Civilian", 1, 1.0 },
    { 131, "Indian", 1, 0.6 },
    { 157, "Country", 1, 0.7 },
    { 201, "Country", 1, 0.7 },
    { 298, "Country", 1, 0.6 },
    { 191, "Military", 1, 0.2 },
    { 141, "Business", 1, 0.1 },
}

local byModel = {}
for _, row in ipairs(M.TYPES) do
    byModel[row[1]] = row
end

function M.isClothesSkin(model)
    return byModel[tonumber(model)] ~= nil
end

-- gender of a clothes skin, nil for a model outside the table
function M.gender(model)
    local row = byModel[tonumber(model)]
    return row and row[3] or nil
end

-- "Male Civilian"; a skin outside the table (an older character's) is plain "Male Clothes"
function M.label(model, female)
    local row = byModel[tonumber(model)]
    local isFemale = row and row[3] == M.FEMALE or (not row and female == true)
    return (isFemale and "Female " or "Male ") .. (row and row[2] or "Clothes")
end

-- Upstream OnItemCreate: every type passes its spawn chance, one of the passes is picked. gender limits the rows
-- (spawn skins); rand() returns [0, 1), randInt(n) an integer in [1, n].
function M.roll(rand, randInt, gender)
    local passed = {}
    for _, row in ipairs(M.TYPES) do
        if (gender == nil or row[3] == gender) and rand() < row[4] then
            passed[#passed + 1] = row[1]
        end
    end
    if #passed == 0 then
        return gender == M.FEMALE and 192 or 60
    end
    return passed[randInt(#passed)]
end

-- Park-Miller generator seeded by the item id: stays exact in Lua 5.1 doubles (16807 * 2^31 < 2^53)
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

-- the skin a Clothes item holds: its stored data.skin, else the type rolled from its id
function M.skinFor(itemId, data)
    local stored = type(data) == "table" and tonumber(data.skin) or nil
    if stored then
        return stored
    end
    local rand, randInt = M.seeded(itemId)
    return M.roll(rand, randInt)
end

return M
