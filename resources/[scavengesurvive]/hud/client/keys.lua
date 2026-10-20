local function guard()
    return not (
        isChatBoxInputActive()
        or isConsoleActive()
        or isMainMenuActive()
        or isMTAWindowActive()
        or isPedDead(localPlayer)
    )
end
local function request(eventName)
    return function()
        if not guard() then
            return
        end
        if exports.ui:listIsOpen() and eventName ~= "onItemsRequestOpenInventory" then
            return
        end
        triggerServerEvent(eventName, localPlayer)
    end
end
addCommandHandler("interact", request("onItemsRequestPickup"))
addCommandHandler("dropitem", request("onItemsRequestDrop"))
addCommandHandler("putaway", request("onItemsRequestPutAway"))
addCommandHandler("inventory", function()
    if not guard() then
        return
    end
    if exports.ui:listIsOpen() then
        return exports.ui:listClose()
    end
    triggerServerEvent("onItemsRequestOpenInventory", localPlayer)
end)

local DEFAULTS = { interact = "f", dropitem = "n", putaway = "y", inventory = "h" }
addEventHandler("onClientResourceStart", resourceRoot, function()
    -- MTA binds Y to team chat by default; the gamemode has no teams, so Y is ours (restored on stop)
    unbindKey("y", "down", "chatbox")
    for cmd, key in pairs(DEFAULTS) do
        if not getKeyBoundToCommand(cmd) then
            bindKey(key, "down", cmd)
        end
    end
    setPlayerHudComponentVisible("health", false)
    setPlayerHudComponentVisible("armour", false)
    setPlayerHudComponentVisible("money", false)
    setPlayerHudComponentVisible("clock", false)
    setPlayerHudComponentVisible("weapon", false)
    setPlayerHudComponentVisible("ammo", false)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    bindKey("y", "down", "chatbox", "teamsay")
end)
