-- Pure logic for worn armour durability (upstream item/armour.pwn): the item carries its points in data.ap.
local M = {}

M.MIN_AP = 25
M.SPAN = 75

-- upstream OnItemCreate: 25 + random(75), so 25..99 (rnd() is a float in [0, 1))
function M.roll(rnd)
    return M.MIN_AP + math.floor(rnd() * M.SPAN)
end

-- give an armour item its points when it has none (loot and starting armour are created without data);
-- true when it rolled and the data needs saving
function M.ensure(item, rnd)
    if type(item.data) ~= "table" then
        item.data = {}
    end
    if tonumber(item.data.ap) == nil then
        item.data.ap = M.roll(rnd)
        return true
    end
    return false
end

-- upstream OnPlayerShootPlayer for a chest hit: the bleed is cut by the ammo's penetration and the armour loses
-- (ap + 10) * (bleed * 10) points. Returns the bleed that goes through and the points that are left (0 = broken).
function M.hit(ap, bleed, penetration)
    local through = bleed * penetration
    local left = ap - (ap + 10) * (through * 10)
    return through, math.max(0, math.floor(left + 0.5))
end

return M
