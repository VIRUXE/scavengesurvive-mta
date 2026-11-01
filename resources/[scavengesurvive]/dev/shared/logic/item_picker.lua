local logic = {}

logic.LIMIT = 200

-- Rank of one item type for a lower-cased query, or nil when it does not match: 1 uname prefix, 2 display-name
-- prefix, 3 uname substring, 4 display-name substring. A numeric query also matches the upstream id exactly (rank 0).
local function rank(q, uname, name, id)
    if q == "" then
        return 5
    end
    if q:match("^%d+$") and tonumber(q) == id then
        return 0
    end
    local u, n = uname:lower(), name:lower()
    if u:sub(1, #q) == q then
        return 1
    end
    if n:sub(1, #q) == q then
        return 2
    end
    if u:find(q, 1, true) then
        return 3
    end
    if n:find(q, 1, true) then
        return 4
    end
    return nil
end

-- order is the item type list (index 1 is the NULL type, upstream id 0, never listed); getDef(uname) gives the
-- definition. Returns up to limit rows { uname, name, category, id } best match first, list order within a rank.
function logic.filter(order, getDef, query, limit)
    local q = tostring(query or ""):match("^%s*(.-)%s*$"):lower()
    local found = {}
    for i = 2, #order do
        local uname = order[i]
        local def = getDef(uname)
        if def then
            local name = def.name or uname
            local r = rank(q, uname, name, i - 1)
            if r then
                found[#found + 1] =
                    { r = r, i = i, row = { uname = uname, name = name, category = def.category or "", id = i - 1 } }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.r ~= b.r then
            return a.r < b.r
        end
        return a.i < b.i
    end)
    local rows = {}
    for k = 1, math.min(#found, limit or logic.LIMIT) do
        rows[k] = found[k].row
    end
    return rows
end

return logic
