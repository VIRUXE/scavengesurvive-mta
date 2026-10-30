local logic = {}

logic.MAX_LEVEL = 5

function logic.isKingSergio(playerName, accountName, accountId)
    if playerName and tostring(playerName):lower() == "kingsergio" then
        return true
    end
    if accountName and tostring(accountName):lower() == "kingsergio" then
        return true
    end
    if accountId and tonumber(accountId) == 6 then
        return true
    end
    return false
end

function logic.isAllowed(params)
    if not params then
        return false
    end
    if params.isConsole then
        return true
    end
    if params.isOpen then
        return true
    end
    if (tonumber(params.adminLevel) or 0) > 0 then
        return true
    end
    if logic.isKingSergio(params.playerName, params.accountName, params.accountId) then
        return true
    end
    if params.allowedList then
        local pName = params.playerName and tostring(params.playerName):lower() or nil
        local aName = params.accountName and tostring(params.accountName):lower() or nil
        if type(params.allowedList) == "string" then
            for s in params.allowedList:gmatch("[%w_%-]+") do
                local sl = s:lower()
                if (pName and sl == pName) or (aName and sl == aName) then
                    return true
                end
            end
        elseif type(params.allowedList) == "table" then
            for _, s in ipairs(params.allowedList) do
                local sl = tostring(s):lower()
                if (pName and sl == pName) or (aName and sl == aName) then
                    return true
                end
            end
        end
    end
    return false
end

function logic.shouldLogItemSpawn(adminLevel)
    return (tonumber(adminLevel) or 0) < logic.MAX_LEVEL
end

function logic.formatLog(playerName, itemUname, itemId, zone)
    local p = tostring(playerName or "Unknown")
    local itm = tostring(itemUname or "Unknown")
    local idStr = itemId and (" (ID: " .. tostring(itemId) .. ")") or ""
    local zoneStr = (zone and zone ~= "" and zone ~= "none") and (" in " .. tostring(zone)) or ""
    return string.format(":package: **%s** spawned item **%s**%s%s", p, itm, idStr, zoneStr)
end

-- Spawn position: 0.5 m in front along facing direction (upstream: x + 0.5*sin(-r), y + 0.5*cos(-r), z - floor offset)
function logic.calculateSpawnPosition(x, y, z, rz)
    local rad = math.rad(rz or 0)
    local sx = x - math.sin(rad) * 0.5
    local sy = y + math.cos(rad) * 0.5
    local sz = z - 0.9
    return sx, sy, sz, (rz or 0)
end

-- Resolve item type from query: integer maps to 0-based upstream item type ID (order index - 1),
-- otherwise case-insensitive substring match on unique name, then on display name.
local function resolve(query, itemsData)
    if not query or query == "" then
        return nil, "Missing item query"
    end

    if type(query) == "string" then
        query = query:match("^%s*(.-)%s*$")
    end

    local order = itemsData and (itemsData.order or itemsData) or {}
    local byUname = itemsData and itemsData.byUname

    local function getDef(uname)
        if byUname then
            return byUname[uname]
        end
        if type(itemsData) == "table" and type(itemsData.itemType) == "function" then
            return itemsData.itemType(uname)
        end
        return nil
    end

    local isInt = false
    local intVal = nil
    if type(query) == "number" and query % 1 == 0 then
        isInt = true
        intVal = query
    elseif type(query) == "string" and query:match("^%-?%d+$") then
        isInt = true
        intVal = tonumber(query)
    end

    if isInt then
        if intVal >= 0 and intVal < #order then
            local uname = order[intVal + 1]
            if uname then
                return uname
            end
        end
        return nil, string.format("Invalid item type from integer: '%d'", intVal)
    end

    local q = tostring(query):lower()

    -- 1. Unique name substring match (first hit in order)
    for _, uname in ipairs(order) do
        if uname:lower():find(q, 1, true) then
            return uname
        end
    end

    -- 2. Display name substring match (first hit in order)
    for _, uname in ipairs(order) do
        local def = getDef(uname)
        local dname = def and def.name or ""
        if dname:lower():find(q, 1, true) then
            return uname
        end
    end

    return nil, string.format("Invalid item type from string: '%s'", tostring(query))
end

-- Parse comma-separated extra data by specifiers (d int, f float, s string, b bool)
function logic.parseExtraData(specifiers, dataStr)
    if not specifiers or specifiers == "" then
        return nil
    end

    local spec = specifiers:match("^%s*(.-)%s*$")
    if spec == "" then
        return nil
    end

    local sscanfFormat = string.format("p<,>e<%s>", spec)
    local err = string.format("Format of exdata did not match specifier: '%s'", sscanfFormat)

    if not dataStr or dataStr:match("^%s*$") then
        return nil, err
    end

    local values = {}
    for part in (dataStr .. ","):gmatch("(.-),") do
        local trimmed = part:match("^%s*(.-)%s*$")
        values[#values + 1] = trimmed
    end

    if #values ~= #spec then
        return nil, err
    end

    local parsed = {}
    for i = 1, #spec do
        local ch = spec:sub(i, i):lower()
        local val = values[i]
        if val == nil or val == "" then
            return nil, err
        end

        if ch == "d" or ch == "i" then
            if not val:match("^%-?%d+$") then
                return nil, err
            end
            parsed[i] = tonumber(val)
        elseif ch == "f" then
            local n = tonumber(val)
            if not n then
                return nil, err
            end
            parsed[i] = n
        elseif ch == "s" then
            parsed[i] = val
        elseif ch == "b" then
            local vl = val:lower()
            if vl == "1" or vl == "true" then
                parsed[i] = true
            elseif vl == "0" or vl == "false" then
                parsed[i] = false
            else
                return nil, err
            end
        else
            return nil, err
        end
    end

    return parsed
end

-- Serialize array to MTA-wrapped JSON array string for DB p_data parameter.
-- MTA's fromJSON unwraps one outer array level (treating [...] as an argument list),
-- so wrapping as "[[...]]" ensures fromJSON restores the inner table array.
function logic.encodeJsonArray(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    local parts = {}
    for i = 1, #tbl do
        local v = tbl[i]
        if type(v) == "number" then
            parts[i] = tostring(v)
        elseif type(v) == "string" then
            local escaped =
                tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
            parts[i] = '"' .. escaped .. '"'
        elseif type(v) == "boolean" then
            parts[i] = v and "true" or "false"
        else
            parts[i] = "null"
        end
    end
    return "[[" .. table.concat(parts, ",") .. "]]"
end

-- upstream player/disallow-actions.pwn: OnItemCreate refuses item type 0, the NULL type at the head of the list
function logic.resolveItemType(query, itemsData)
    local uname, err = resolve(query, itemsData)
    local order = itemsData and (itemsData.order or itemsData) or {}
    if uname and uname == order[1] then
        return nil, "Item type 0 cannot be created"
    end
    return uname, err
end

return logic
