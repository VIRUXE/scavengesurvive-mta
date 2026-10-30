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

-- A code part (world puzzle, upstream codehunt.pwn SetItemNameExtra): "Code (7)", its digit of the lockup's code
function M.codeLabel(name, data)
    local digit = tonumber(unwrap(data).digit)
    return digit and (name .. " (" .. digit .. ")") or name
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

-- Shield (item/shield.pwn): placed, it stands SHIELD_AHEAD metres in front of the player, SHIELD_DROP below their
-- feet, turned to face them (rz + 180), on its edge (the client turns the object by SHIELD_RX)
M.SHIELD_AHEAD, M.SHIELD_DROP, M.SHIELD_RX = 0.5, 0.2, 90
M.SHIELD_PLANT_MS = 400 -- the planting animation runs this long before the shield is down

function M.isPlaced(data)
    return tonumber(unwrap(data).placed) == 1
end

-- HerpDerp (item/herpderp.pwn): one of these animations at random
M.HERP_ANIMS = {
    { "TATTOOS", "TAT_ArmL_In_O" },
    { "TATTOOS", "TAT_ArmL_Out_O" },
    { "TATTOOS", "TAT_ArmR_In_O" },
    { "TATTOOS", "TAT_ArmR_Out_O" },
    { "TATTOOS", "TAT_Back_In_O" },
    { "TATTOOS", "TAT_Back_Out_O" },
    { "TATTOOS", "TAT_Bel_In_O" },
    { "TATTOOS", "TAT_Bel_Out_O" },
    { "TATTOOS", "TAT_Che_In_O" },
    { "TATTOOS", "TAT_Che_Out_O" },
    { "TATTOOS", "TAT_Drop_O" },
    { "TATTOOS", "TAT_Idle_Loop_O" },
    { "TATTOOS", "TAT_Sit_In_O" },
    { "TATTOOS", "TAT_Sit_Loop_O" },
    { "TATTOOS", "TAT_Sit_Out_O" },
    { "GHANDS", "LHGsign1" },
    { "GHANDS", "LHGsign2" },
    { "GHANDS", "LHGsign3" },
    { "GHANDS", "LHGsign4" },
    { "GHANDS", "LHGsign5" },
    { "GHANDS", "RHGsign1" },
    { "GHANDS", "RHGsign2" },
    { "GHANDS", "RHGsign3" },
    { "GHANDS", "RHGsign4" },
    { "GHANDS", "RHGsign5" },
}

function M.herpAnim(randInt)
    local a = M.HERP_ANIMS[(randInt or math.random)(1, #M.HERP_ANIMS)]
    return a[1], a[2]
end

-- The Locker (item/locker.pwn, #143): SA-MP models, closed and open while someone has it open
M.LOCKER = { uname = "Locker", closed = 11729, open = 11730 }

function M.lockerModel(open)
    return open and M.LOCKER.open or M.LOCKER.closed
end

-- Port deviation (upstream opens it from any side): the Locker opens only for a player on its door side who faces it.
-- The door is the model's local -Y side (measured: the open twin's box grows from y -0.27 to -0.64), so with the
-- item heading rz (the type's rotz is 0) its normal is (sin rz, -cos rz). A ped at rotation r faces (-sin r, cos r).
M.LOCKER_DOOR_ARC = 60 -- degrees either side of the door normal the player may stand
M.LOCKER_FACING_ARC = 60 -- degrees either side of the locker the player's heading may point

-- the angle in degrees (0..180) between two vectors
local function angleBetween(ax, ay, bx, by)
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la < 1e-6 or lb < 1e-6 then
        return 0
    end
    local c = math.max(-1, math.min(1, (ax * bx + ay * by) / (la * lb)))
    return math.deg(math.acos(c))
end

-- true when the player at (px, py) heading prz stands in front of the locker at (ix, iy) heading irz and faces it
function M.lockerFacing(ix, iy, irz, px, py, prz)
    local ir, pr = math.rad(irz or 0), math.rad(prz or 0)
    local toPlayerX, toPlayerY = px - ix, py - iy
    if angleBetween(math.sin(ir), -math.cos(ir), toPlayerX, toPlayerY) > M.LOCKER_DOOR_ARC then
        return false
    end
    return angleBetween(-math.sin(pr), math.cos(pr), -toPlayerX, -toPlayerY) <= M.LOCKER_FACING_ARC
end

-- The body (item/torso.pwn, character/shared/logic/bodies.lua writes its data): a knife takes one raw Meat from it
-- once, within a day of the death.
M.BODY_DECOMPOSE_S = 86400
M.HARVEST_MS = 3000
M.MEAT_LIFT = 0.3 -- the meat lies this far above the body's origin

-- name and reason shown when the body is investigated
function M.bodyText(data)
    local d = unwrap(data)
    return tostring(d.name or ""), tostring(d.reason or "")
end

-- true, or false and the toast code (BODYHARVEST: already taken; BODYDECOMPD: too old)
function M.bodyCanHarvest(data, now)
    local d = unwrap(data)
    if tonumber(d.harvest) ~= 1 then
        return false, "BODYHARVEST"
    end
    if (now or 0) - (tonumber(d.at) or 0) >= M.BODY_DECOMPOSE_S then
        return false, "BODYDECOMPD"
    end
    return true
end

return M
