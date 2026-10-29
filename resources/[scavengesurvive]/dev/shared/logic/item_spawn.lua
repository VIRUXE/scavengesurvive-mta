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

return logic
