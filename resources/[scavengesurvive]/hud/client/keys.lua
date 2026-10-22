-- Command binds for the five keys (players rebind them in MTA's settings). ctx.getHeld() is the held item
-- summary from client/main.lua; the interact key eats held food, as upstream's single-item table does.
return function(ctx)
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
            if not guard() or exports.ui:listIsOpen() then
                return
            end
            triggerServerEvent(eventName, localPlayer)
        end
    end
    addCommandHandler("interact", function()
        if not guard() or exports.ui:listIsOpen() then
            return
        end
        local held = ctx.getHeld()
        if held and held.category == "food" then
            return triggerServerEvent("onItemsRequestUse", localPlayer, held.id)
        end
        triggerServerEvent("onItemsRequestPickup", localPlayer)
    end)
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
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        bindKey("y", "down", "chatbox", "teamsay")
    end)
end
