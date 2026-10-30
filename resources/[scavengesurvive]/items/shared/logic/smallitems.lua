-- The small item behaviours of upstream core/item/{note,sign,dice,locator,stungun,molotov}.pwn as pure rules
-- (#136): the text a Note or Sign keeps, their labels, the dice roll and the rotation each face lands at, the
-- stun gun's charge and the petrol a Molotov takes from a can. Server and client read the same file.
local M = {}

M.NOTE_MAX = 256 -- SetItemTypeMaxArrayData(Note, 256)
M.SIGN_MAX = 128 -- MAX_SIGN_TEXT
M.DICE_THROW = 0.4 -- metres the dice roll on from where they were dropped
M.STUN_KO_MS = 60000 -- KnockOutPlayer(targetid, 60000)
M.MOLOTOV_LITRES = 0.5 -- petrol poured into an empty bottle
M.MOLOTOV_FROM, M.MOLOTOV_TO = "MolotovEmpty", "Molotov"

-- A player's text as the item keeps it: no control characters, no colour codes, trimmed, at most max characters.
function M.cleanText(text, max)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("[%c]", " "):gsub("#%x%x%x%x%x%x", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, max or M.NOTE_MAX)
end

local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end

-- the message written on a Note or Sign ("" when blank)
function M.text(data)
    local t = unwrap(data).text
    return type(t) == "string" and t or ""
end

-- OnItemNameRender for the Note: "Note (Blank)", the whole message when it is short, else its first 8 letters
-- and "(...)" (upstream strins at 8, cut at 13)
function M.noteLabel(name, data)
    local text = M.text(data)
    if text == "" then
        return name .. " (Blank)"
    end
    if #text > 8 then
        return name .. " (" .. text:sub(1, 8) .. "(...))"
    end
    return name .. " (" .. text .. ")"
end

-- A sign's text as lines: upstream turned every "\" into a line break
function M.signLines(text)
    local lines = {}
    for line in (tostring(text or "") .. "\\"):gmatch("(.-)\\") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    return lines
end

-- Dice: the object rotation (rx, ry) that shows each face up, upstream's DiceRotationSets
M.DICE_ROTATIONS = { { 0, 0 }, { 0, 90 }, { 270, 0 }, { 90, 0 }, { 0, 270 }, { 180, 0 } }

function M.rollDice(randInt)
    return (randInt or math.random)(1, 6)
end

function M.diceFace(data)
    local f = tonumber(unwrap(data).face)
    return f and M.DICE_ROTATIONS[f] and f or nil
end

function M.diceRotation(face)
    local r = M.DICE_ROTATIONS[tonumber(face) or 0] or M.DICE_ROTATIONS[1]
    return r[1], r[2]
end

-- where the dice come to rest: DICE_THROW metres on along the thrower's facing
function M.diceLanding(x, y, facing)
    local rad = math.rad(facing or 0)
    return x - M.DICE_THROW * math.sin(rad), y + M.DICE_THROW * math.cos(rad)
end

-- Stun gun: charged by a Battery, spent by one hit
function M.isCharged(data)
    return tonumber(unwrap(data).charged) == 1
end

function M.stunLabel(name, data)
    return name .. (M.isCharged(data) and " (Charged)" or " (Uncharged)")
end

-- Pouring petrol from a can (its liquid data, items/shared/logic/liquids.lua) into an empty Molotov:
-- ok, the can's next data, litres moved; or false and the toast code.
function M.pourMolotov(liquids, canType, canData)
    local amount, liquid = liquids.decode(canType, canData)
    if liquid and liquid ~= "Petrol" then
        return false, "FUELNOTPETR"
    end
    if not liquid or amount <= 0 then
        return false, "PETROLEMPTY"
    end
    local moved = math.min(M.MOLOTOV_LITRES, amount)
    return true, { amount = amount - moved, liquid = liquid }, moved
end

-- Locator: the phone it is synced to, or nil
function M.locatorPhone(data)
    return tonumber(unwrap(data).phone)
end

return M
