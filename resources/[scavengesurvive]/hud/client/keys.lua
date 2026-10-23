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
    local VEHICLE_TOOLS = {
        Wrench = true,
        Screwdriver = true,
        Hammer = true,
        GasCan = true,
        Key = true,
        LocksmithKit = true,
        WheelLock = true,
        Crowbar = true,
        LockBreaker = true,
    }

    local function getNearbyVehicle()
        local px, py, pz = getElementPosition(localPlayer)
        local nearVeh, nearDist = nil, 6.0
        for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
            local vx, vy, vz = getElementPosition(veh)
            local dist = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
            if dist < nearDist then
                nearVeh, nearDist = veh, dist
            end
        end
        return nearVeh, nearDist
    end

    -- ladders and ziplines (world) take the key before anything else
    local function worldInteract()
        return exports.world:tryInteract() == true
    end

    addCommandHandler("interact", function()
        if not guard() or listIsOpen() then
            return
        end
        if getPedOccupiedVehicle(localPlayer) then
            return
        end
        if worldInteract() then
            return
        end
        local nearVeh, nearDist = getNearbyVehicle()
        local held = ctx.getHeld()
        local uname = held and held.uname
        if nearVeh and nearDist <= 5.5 then
            local px, py = getElementPosition(localPlayer)
            local vx, vy = getElementPosition(nearVeh)
            local _, _, vrz = getElementRotation(nearVeh)
            local rad = math.rad(vrz or 0)
            local dx, dy = px - vx, py - vy
            local localX = dx * math.cos(rad) + dy * math.sin(rad)
            local localY = -dx * math.sin(rad) + dy * math.cos(rad)
            local angle = (math.deg(math.atan2(localX, localY)) + 360) % 360
            local isRear = angle > 155 and angle < 205
            if (uname and VEHICLE_TOOLS[uname]) or isRear then
                return triggerServerEvent("vehicleInteractRequested", localPlayer, nearVeh)
            end
        end
        if held and held.category == "food" then
            return triggerServerEvent("itemUseRequested", localPlayer, held.id)
        end
        triggerServerEvent("itemPickupRequested", localPlayer)
    end)

    addCommandHandler("dropitem", function()
        if not guard() or listIsOpen() then
            return
        end
        if getPedOccupiedVehicle(localPlayer) then
            return triggerServerEvent("lightsToggleRequested", localPlayer)
        end
        if isTimer(holdTimer) then
            return
        end
        local held = ctx.getHeld()
        local isCalibreWep = held and held.category == "weapon" and held.calibre ~= nil and not held.liquid
        local key = string.lower(getKeyBoundToCommand("dropitem") or "n")
        if not isCalibreWep or not getKeyState(key) then
            return triggerServerEvent("itemDropRequested", localPlayer)
        end
        local startTick = getTickCount()
        holdTimer = setTimer(function()
            if not getKeyState(key) then
                killTimer(holdTimer)
                holdTimer = nil
                triggerServerEvent("itemDropRequested", localPlayer)
            elseif getTickCount() - startTick >= 300 then
                killTimer(holdTimer)
                holdTimer = nil
                triggerServerEvent("itemUnloadRequested", localPlayer)
            end
        end, 50, 0)
    end)

    addCommandHandler("putaway", function()
        if not guard() or listIsOpen() then
            return
        end
        if getPedOccupiedVehicle(localPlayer) then
            return triggerServerEvent("engineToggleRequested", localPlayer)
        end
        triggerServerEvent("itemPutAwayRequested", localPlayer)
    end)
    addCommandHandler("reloadweapon", request("itemReloadRequested"))
    addCommandHandler("unloadweapon", request("itemUnloadRequested"))
    addCommandHandler("inventory", function()
        if not guard() then
            return
        end
        if listIsOpen() then
            return exports.ui:listClose()
        end
        triggerServerEvent("inventoryOpenRequested", localPlayer)
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
