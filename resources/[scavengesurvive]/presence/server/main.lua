-- Sends each client what its Discord Rich Presence needs from the server (client/main.lua sets it).
local function config()
    return {
        appId = tostring(get("appId") or ""),
        joinUrl = tostring(get("joinUrl") or ""),
        maxPlayers = getMaxPlayers(),
        serverName = getServerName(),
    }
end

addEventHandler("onPlayerResourceStart", root, function(res)
    if res == getThisResource() then
        triggerClientEvent(source, "presenceConfigured", resourceRoot, config())
    end
end)
