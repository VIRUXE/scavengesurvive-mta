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

return discordchat
