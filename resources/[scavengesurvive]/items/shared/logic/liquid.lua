-- Liquid containers (upstream DefineLiquidContainerItem: the Petrol Can). The amount held lives in the item data
-- as data.amount, in litres; an item created without one (dev /additem, staff, crafting) counts as full, which is
-- what vehicles/server/main.lua and items/server/cooking.lua assume when they read it. Loot rolls a random
-- amount (loot/shared/logic/roll.lua, #118). Pure: busted dofiles it.
local M = {}

-- item data arrives either as an object or wrapped in MTA's toJSON array
local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end
M.unwrap = unwrap

function M.isContainer(t)
    return t ~= nil and t.category == "liquid"
end

function M.capacity(t)
    local cd = t and t.categoryData
    return cd and tonumber(cd.capacity) or 0
end

-- litres held: data.amount clamped to [0, capacity], the capacity when the item carries no amount
function M.amount(t, data)
    local cap = M.capacity(t)
    local a = tonumber(unwrap(data).amount)
    if a == nil then
        return cap
    end
    return math.max(0, math.min(cap, a))
end

-- "Petrol Can (12.3 L)", "Petrol Can (Empty)"; other types keep their name
function M.label(t, name, data)
    if not M.isContainer(t) then
        return name
    end
    local a = M.amount(t, data)
    if a <= 0 then
        return string.format("%s (Empty)", name)
    end
    return string.format("%s (%.1f L)", name, a)
end

return M
