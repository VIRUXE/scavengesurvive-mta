-- Recipe matching for upstream's craft sets (data/generated/recipes.lua, from init.pwn): combined in an inventory
-- screen ("combine"), built from items on the ground with a tool ("construct", craft-construct.pwn) or built from a
-- workbench's contents with a tool ("workbench", workbench.pwn). Upstream's craft library matches a selection only
-- when it holds exactly a set's ingredients, as a multiset (_craft_FindCraftset: same count, same sorted types).
-- Pure: no MTA calls; the server passes the recipe list in.
local M = {}

M.WORKBENCH_MS_PER_ITEM = 3600 -- workbench.pwn: the hold is itemcount * 3600 ms, the set's build time is not used

local function key(unames)
    local sorted = {}
    for i, u in ipairs(unames) do
        sorted[i] = u
    end
    table.sort(sorted)
    return table.concat(sorted, "+")
end

local function ingredientUnames(r)
    local out = {}
    for i, ing in ipairs(r.ingredients) do
        out[i] = ing.uname
    end
    return out
end

-- book = { list, byKey, byResult, constructTools }; upstream's first set wins a key, the last set defined for a
-- result type is the one a removal tool takes apart (craft_ItemTypeResultFor is overwritten on each define)
function M.book(recipes)
    local book = { list = recipes, byKey = {}, byResult = {}, constructTools = {} }
    for _, r in ipairs(recipes) do
        local k = key(ingredientUnames(r))
        book.byKey[k] = book.byKey[k] or r
        book.byResult[r.result] = r
        if r.kind == "construct" then
            book.constructTools[r.tool] = true
        end
    end
    return book
end

-- the set whose ingredients are exactly these unames (any order), or nil
function M.find(book, unames)
    if #unames < 2 then
        return nil
    end
    return book.byKey[key(unames)]
end

-- items: { { id, uname, ... } } matching the recipe; returns consumed, kept (lists of those items). Within one item
-- type the kept ingredients take the first items given, so the caller orders items it would rather keep first
-- (the cut key of a key copy).
function M.split(recipe, items)
    local wants = {}
    for _, ing in ipairs(recipe.ingredients) do
        local w = wants[ing.uname] or { keep = 0 }
        wants[ing.uname] = w
        if ing.keep then
            w.keep = w.keep + 1
        end
    end
    local consumed, kept = {}, {}
    for _, it in ipairs(items) do
        local w = wants[it.uname]
        if w and w.keep > 0 then
            w.keep = w.keep - 1
            kept[#kept + 1] = it
        else
            consumed[#consumed + 1] = it
        end
    end
    return consumed, kept
end

-- craft.inc _craft_CraftSelected: the units the result needs beyond what the consumed ingredients free
function M.extraUnits(recipe, sizeOf)
    local units = sizeOf(recipe.result)
    for _, ing in ipairs(recipe.ingredients) do
        if not ing.keep then
            units = units - sizeOf(ing.uname)
        end
    end
    return units
end

-- craft-construct.pwn: taking a built item apart gives back the ingredients that were used up (kept ones never left
-- the builder)
function M.returned(recipe)
    local out = {}
    for _, ing in ipairs(recipe.ingredients) do
        if not ing.keep then
            out[#out + 1] = ing.uname
        end
    end
    return out
end

-- the construct set a removal tool takes this item type apart with, or nil
function M.removal(book, uname, tool)
    local r = book.byResult[uname]
    if r and r.kind == "construct" and r.removalTool and (not tool or r.removalTool == tool) then
        return r
    end
    return nil
end

-- every item type some removal tool takes apart (for the nearest-item query)
function M.removable(book, tool)
    local out, seen = {}, {}
    for _, r in ipairs(book.list) do
        local cur = M.removal(book, r.result, tool)
        if cur == r and not seen[r.result] then
            seen[r.result] = true
            out[#out + 1] = r.result
        end
    end
    table.sort(out)
    return out
end

function M.workbenchTime(itemCount)
    return itemCount * M.WORKBENCH_MS_PER_ITEM
end

-- craft-construct.pwn: the result stands at the average position of the ingredients (those at 0,0,0 are skipped
-- from the sum but still count, as upstream divides by the ingredient count)
function M.averagePos(items)
    local x, y, z = 0, 0, 0
    for _, it in ipairs(items) do
        if it.x * it.y * it.z ~= 0 then
            x, y, z = x + it.x, y + it.y, z + it.z
        end
    end
    local n = math.max(1, #items)
    return x / n, y / n, z / n
end

local function liquid(data)
    local d = type(data) == "table" and (type(data[1]) == "table" and data[1] or data) or {}
    local amount = tonumber(d.amount) or 0
    return amount, amount > 0.001 and d.liquid or nil
end

-- Bottle + Bottle: the second bottle's liquid into the first, as far as it fits; one liquid per bottle. Returns
-- the two bottles' new data, or nil and the reason.
function M.pour(intoData, fromData, capacity)
    local intoAmount, intoLiquid = liquid(intoData)
    local fromAmount, fromLiquid = liquid(fromData)
    if not fromLiquid then
        return nil, nil, "LIQUID_EMPTY"
    end
    if intoLiquid and intoLiquid ~= fromLiquid then
        return nil, nil, "LIQUID_MIX"
    end
    local moved = math.min(fromAmount, (tonumber(capacity) or 0) - intoAmount)
    if moved <= 0.001 then
        return nil, nil, "LIQUID_FULL"
    end
    local left = fromAmount - moved
    return { amount = intoAmount + moved, liquid = fromLiquid }, {
        amount = left,
        liquid = left > 0.001 and fromLiquid or nil,
    }
end

function M.byKind(book, kind)
    local out = {}
    for i, r in ipairs(book.list) do
        if r.kind == kind then
            out[#out + 1] = { id = i, recipe = r }
        end
    end
    return out
end

return M
