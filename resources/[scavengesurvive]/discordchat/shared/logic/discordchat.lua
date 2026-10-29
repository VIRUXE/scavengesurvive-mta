local discordchat = {}

function discordchat.strip(s)
    local cleaned = tostring(s or ""):gsub("#%x%x%x%x%x%x", "")
    return cleaned ~= "" and cleaned or tostring(s or "")
end

function discordchat.joinPayload(name, channel)
    local player = discordchat.strip(name)
    if player == "" then
        return nil
    end
    local payload = { player = player }
    if channel then
        payload.channel = channel
    end
    return payload
end

function discordchat.quitPayload(name, quitType, reason, respName, channel)
    local player = discordchat.strip(name)
    if player == "" then
        return nil, nil
    end

    local reasonStr = type(reason) == "string" and reason ~= "" and discordchat.strip(reason) or false

    if quitType == "Kicked" then
        local payload = {
            player = player,
            responsible = respName and discordchat.strip(respName) or "Console",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.kick", payload
    elseif quitType == "Banned" then
        local payload = {
            player = player,
            responsible = respName and discordchat.strip(respName) or "Console",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.ban", payload
    else
        local payload = {
            player = player,
            type = quitType or "Quit",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.quit", payload
    end
end

function discordchat.nickChangePayload(previous, nick, channel)
    local prevClean = discordchat.strip(previous)
    local newClean = discordchat.strip(nick)
    if prevClean == "" or newClean == "" or prevClean == newClean then
        return nil
    end
    local payload = {
        player = newClean,
        previous = prevClean,
    }
    if channel then
        payload.channel = channel
    end
    return payload
end

function discordchat.itemSpawnPayload(playerName, itemUname, itemId, zone, channel)
    local player = discordchat.strip(playerName)
    local item = discordchat.strip(itemUname)
    if player == "" or item == "" then
        return nil, nil
    end
    local idStr = itemId and (" (ID: " .. tostring(itemId) .. ")") or ""
    local zoneClean = zone and discordchat.strip(zone) or nil
    local zoneStr = (zoneClean and zoneClean ~= "" and zoneClean ~= "none") and (" in " .. zoneClean) or ""
    local payload = {
        player = player,
        item = item,
        id = itemId and tostring(itemId) or nil,
        zone = (zoneClean and zoneClean ~= "" and zoneClean ~= "none") and zoneClean or nil,
        text = string.format(":package: **%s** spawned item **%s**%s%s", player, item, idStr, zoneStr),
    }
    if channel then
        payload.channel = channel
    end
    return "staff.log", payload
end

function discordchat.staffLogPayload(text, channel)
    local cleaned = discordchat.strip(text)
    if cleaned == "" then
        return nil, nil
    end
    local payload = {
        text = cleaned,
    }
    if channel then
        payload.channel = channel
    end
    return "staff.log", payload
end

return discordchat
