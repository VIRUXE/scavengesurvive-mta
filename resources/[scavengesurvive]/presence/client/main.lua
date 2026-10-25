-- Discord Rich Presence (MTA 1.6 client): "Scavenge & Survive", the player count and a join button. Does nothing
-- when the player has Discord closed or Rich Presence turned off in MTA's settings.
local REFRESH_MS = 15000

local cfg
local timer

local function refresh()
    if not cfg or not isDiscordRichPresenceConnected() then
        return
    end
    setDiscordRichPresenceState("Surviving")
    setDiscordRichPresencePartySize(#getElementsByType("player"), cfg.maxPlayers)
end

addEventHandler("presenceConfigured", resourceRoot, function(c)
    if type(c) ~= "table" or c.appId == "" or not setDiscordApplicationID(c.appId) then
        return
    end
    cfg = c
    setDiscordRichPresenceDetails(c.serverName)
    setDiscordRichPresenceStartTime(1) -- seconds already elapsed: the timer counts from now
    if c.joinUrl ~= "" then
        setDiscordRichPresenceButton(1, "Join server", c.joinUrl)
    end
    refresh()
    if not isTimer(timer) then
        timer = setTimer(refresh, REFRESH_MS, 0)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    resetDiscordRichPresenceData()
end)
