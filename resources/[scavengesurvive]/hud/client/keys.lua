-- Command binds for the HUD keys (players rebind them in MTA's settings). ctx.getHeld() is the held item
-- summary from client/main.lua; the interact key eats held food, R reloads, and holding N for 300 ms on a
-- calibre weapon unloads it (tapping N drops the item).
return function(ctx)
    local holdTimer = nil

    local function guard()
        return not (
            isChatBoxInputActive()
            or isConsoleActive()
            or isMainMenuActive()
            or isMTAWindowActive()
            or isPedDead(localPlayer)
        )
    end
    local function listIsOpen()
        local ui = getResourceFromName("ui")
        if not ui or getResourceState(ui) ~= "running" then
            return false
        end
        return exports.ui:listIsOpen() == true
    end
    local function request(eventName)
        return function()
            if not guard() or listIsOpen() then
                return
            end
            triggerServerEvent(eventName, localPlayer)
        end
    end
    addCommandHandler("interact", function()
        if not guard() or listIsOpen() then
            return
        end
        local held = ctx.getHeld()
        if held and held.category == "food" then
            return triggerServerEvent("onItemsRequestUse", localPlayer, held.id)
        end
        triggerServerEvent("onItemsRequestPickup", localPlayer)
    end)

    addCommandHandler("dropitem", function()
        if not guard() or listIsOpen() then
            return
        end
        if isTimer(holdTimer) then
            return
        end
        local held = ctx.getHeld()
        local isCalibreWep = held and held.category == "weapon" and held.calibre ~= nil and not held.liquid
        local key = string.lower(getKeyBoundToCommand("dropitem") or "n")
        if not isCalibreWep or not getKeyState(key) then
            return triggerServerEvent("onItemsRequestDrop", localPlayer)
        end
        local startTick = getTickCount()
        holdTimer = setTimer(function()
            if not getKeyState(key) then
                killTimer(holdTimer)
                holdTimer = nil
                triggerServerEvent("onItemsRequestDrop", localPlayer)
            elseif getTickCount() - startTick >= 300 then
                killTimer(holdTimer)
                holdTimer = nil
                triggerServerEvent("onItemsRequestUnload", localPlayer)
            end
        end, 50, 0)
    end)

    addCommandHandler("putaway", request("onItemsRequestPutAway"))
    addCommandHandler("reloadweapon", request("onItemsRequestReload"))
    addCommandHandler("unloadweapon", request("onItemsRequestUnload"))
    addCommandHandler("inventory", function()
        if not guard() then
            return
        end
        if listIsOpen() then
            return exports.ui:listClose()
        end
        triggerServerEvent("onItemsRequestOpenInventory", localPlayer)
    end)

    local DEFAULTS = { interact = "f", dropitem = "n", putaway = "y", inventory = "h", reloadweapon = "r" }
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
        if isTimer(holdTimer) then
            killTimer(holdTimer)
            holdTimer = nil
        end
        bindKey("y", "down", "chatbox", "teamsay")
    end)
end
