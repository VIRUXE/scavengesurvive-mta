-- Command binds for the HUD keys (players rebind them in MTA's settings). ctx.getHeld() is the held item
-- summary from client/main.lua; the interact key eats held food or starts a held treatment, R reloads, and holding
-- N for 300 ms on a calibre weapon unloads it (tapping N drops the item).
return function(ctx)
    local holdTimer = nil
    local interactHoldTimer = nil

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
        Headlight = true,
        Wheel = true,
    }

    local TREATMENTS = { Bandage = true, AntiSepBandage = true, Medkit = true, DoctorBag = true, Pills = true }
    TREATMENTS.AutoInjec = true
    local isKeyHeld

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

    -- F is both interact and GTA's enter_exit: a press that opens a trunk (or is pressed while the trunk/inventory
    -- list is open) must not also start the enter task (#113). The server's onVehicleStartEnter only sees it too late.
    local TRUNK_ENTER_BLOCK_MS = 1000
    local blockEnterUntil = 0
    addEventHandler("onClientVehicleStartEnter", root, function(player)
        if player == localPlayer and (getTickCount() < blockEnterUntil or listIsOpen()) then
            cancelEvent()
        end
    end)

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
        if exports.loot:tryOpenCrate() == true then
            return
        end
        local bagId = exports.items:nearbyBag()
        if bagId then
            if isTimer(interactHoldTimer) then
                return
            end
            local key = string.lower(getKeyBoundToCommand("interact") or "f")
            local startTick = getTickCount()
            interactHoldTimer = setTimer(function()
                if not isKeyHeld(key, "interact") then
                    killTimer(interactHoldTimer)
                    interactHoldTimer = nil
                    if getTickCount() - startTick < 500 then
                        triggerServerEvent("itemBagOpenRequested", localPlayer, bagId)
                    end
                elseif getTickCount() - startTick >= 500 then
                    killTimer(interactHoldTimer)
                    interactHoldTimer = nil
                    triggerServerEvent("itemPickupRequested", localPlayer)
                end
            end, 50, 0)
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
                blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
                return triggerServerEvent("vehicleInteractRequested", localPlayer, nearVeh)
            end
        end
        if uname == "GasCan" then
            return triggerServerEvent("fuelPumpInteractRequested", localPlayer)
        end
        -- food is eaten; a held treatment starts its hold, and letting go of the key cancels it (items, #94);
        -- held Clothes start the clothes change (#110)
        if held and (held.category == "food" or TREATMENTS[held.uname] or held.uname == "Clothes") then
            return triggerServerEvent("itemUseRequested", localPlayer, held.id)
        end
        if held and held.category == "bag" then
            return triggerServerEvent("itemBagOpenRequested", localPlayer)
        end
        triggerServerEvent("itemPickupRequested", localPlayer)
    end)

    isKeyHeld = function(key, cmd)
        if getKeyState(key) then
            return true
        end
        local dev = getResourceFromName("dev")
        return dev and getResourceState(dev) == "running" and exports.dev:isHeld(cmd or key) == true
    end

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
        if not held and getElementData(localPlayer, "items.bag") then
            return triggerServerEvent("itemUnwearRequested", localPlayer, "bag")
        end
        local isCalibreWep = held and held.category == "weapon" and held.calibre ~= nil and not held.liquid
        local key = string.lower(getKeyBoundToCommand("dropitem") or "n")
        if not isCalibreWep or not isKeyHeld(key, "dropitem") then
            return triggerServerEvent("itemDropRequested", localPlayer)
        end
        local startTick = getTickCount()
        holdTimer = setTimer(function()
            if not isKeyHeld(key, "dropitem") then
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
        if isTimer(interactHoldTimer) then
            killTimer(interactHoldTimer)
            interactHoldTimer = nil
        end
        bindKey("y", "down", "chatbox", "teamsay")
    end)
end
