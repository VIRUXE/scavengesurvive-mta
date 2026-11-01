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
        Welder = true,
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
        Battery = true,
        Wheel = true,
    }

    local LOCK_TOOLS = { Key = true, LocksmithKit = true, WheelLock = true, Crowbar = true, LockBreaker = true }
    LOCK_TOOLS.Keypad, LOCK_TOOLS.AdvancedKeypad = true, true

    local TREATMENTS = { Bandage = true, AntiSepBandage = true, Medkit = true, DoctorBag = true, Pills = true }
    TREATMENTS.AutoInjec = true
    local isKeyHeld
    -- fishing (items, #141): the server says when the line is out; F then cancels instead of casting again
    local fishing = false
    local MAX_CAST_MS = 10000
    addEventHandler("fishingStarted", localPlayer, function()
        fishing = true
    end)
    addEventHandler("fishingStopped", localPlayer, function()
        fishing = false
    end)

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

    -- the tweak pad (building): while an item is being nudged into place the interact key does nothing, and
    -- dropping, putting away or opening the inventory finishes the tweak first (upstream item-tweak.pwn's hooks)
    local function tweaking()
        local building = getResourceFromName("building")
        return building and getResourceState(building) == "running" and exports.building:tweakIsOpen() == true
    end
    local function finishTweak()
        if tweaking() then
            exports.building:tweakFinish()
        end
    end

    -- ladders and ziplines (world) take the key before anything else
    local function worldInteract()
        return exports.world:tryInteract() == true
    end

    -- F is both interact and GTA's enter_exit: a press the interact handler consumes (a trunk, a held item's use,
    -- a bag) or one made while the trunk/inventory list is open must not also start the enter task (#113). The
    -- server's onVehicleStartEnter only sees it too late.
    local TRUNK_ENTER_BLOCK_MS = 1000
    local PICKUP_REACH = 2.0
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
        if getPedOccupiedVehicle(localPlayer) or tweaking() then
            return
        end
        -- attaching a defence to a trailer (vehicles carmour): F puts it where the ghost lies
        if exports.vehicles:attachModeActive() then
            return exports.vehicles:confirmAttach()
        end
        if worldInteract() then
            return
        end
        -- a Gas Bottle in hand goes onto a trailer's A-frame mount, empty hands take one off (vehicles tryGasMount)
        local heldNow = ctx.getHeld()
        if exports.vehicles:tryGasMount(heldNow and heldNow.uname or false) == true then
            return
        end
        if exports.loot:tryOpenCrate() == true then
            return
        end
        -- carmour (vehicles/server/carmour.lua), ahead of the Generator powering the Welder (a machine): the torch
        -- in hand welds at a vehicle that takes armour and goes back on its Welder anywhere else; a Welder in hand is
        -- told to be laid down; an Angle Grinder in hand grinds a welded panel; a defence in hand at such a vehicle
        -- starts attaching it where the camera aims
        local armourVeh = exports.vehicles:nearbyWeldTarget()
        if exports.vehicles:hasTorch() then
            if armourVeh then
                blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
                return triggerServerEvent("vehicleInteractRequested", localPlayer, armourVeh)
            end
            return triggerServerEvent("weldTorchStowRequested", localPlayer)
        end
        if armourVeh and heldNow and (heldNow.uname == "Welder" or heldNow.uname == "Grinder") then
            return triggerServerEvent("vehicleInteractRequested", localPlayer, armourVeh)
        end
        if armourVeh and heldNow and exports.vehicles:isAttachable(heldNow.uname) then
            blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
            return exports.vehicles:beginAttach(armourVeh)
        end
        -- empty hands at a Welder lying near: a tap takes its torch, a hold picks the Welder up; at a Gas Cylinder or
        -- Gas Bottle lying near a Welder (whichever of the two is nearer) a tap hooks it up to the Welder or unhooks it
        local welderId, welderDist = false, nil
        local gasId, gasDist = false, nil
        if not heldNow then
            welderId, welderDist = exports.vehicles:nearbyWelder()
            gasId, gasDist = exports.vehicles:nearbyGas()
        end
        if gasId and welderId and gasDist < welderDist then
            welderId = false
        elseif welderId then
            gasId = false
        end
        if welderId or gasId then
            if isTimer(interactHoldTimer) then
                return
            end
            local key = string.lower(getKeyBoundToCommand("interact") or "f")
            local startTick = getTickCount()
            interactHoldTimer = setTimer(function()
                local heldMs = getTickCount() - startTick
                if not isKeyHeld(key, "interact") or heldMs >= 500 then
                    killTimer(interactHoldTimer)
                    interactHoldTimer = nil
                    if heldMs >= 500 then
                        triggerServerEvent("itemPickupRequested", localPlayer, exports.items:blockedItemsNear())
                    elseif gasId then
                        triggerServerEvent("weldCylinderHookRequested", localPlayer, gasId)
                    else
                        triggerServerEvent("weldTorchGrabRequested", localPlayer, welderId)
                    end
                end
            end, 50, 0)
            return
        end
        -- a ground bag opens on a tap and is picked up on a 500 ms hold; a sign or a body lying there (empty hands)
        -- edits or investigates on a tap and is picked up on the hold (upstream "Press F to edit / investigate,
        -- Hold F to pick up", #136, #139)
        -- a machine (#145, upstream "Press F to access machine / Hold F to open menu"): the tap opens its
        -- container, the hold its menu, or a refuel that lasts as long as the key stays down
        local bagId, bagCategory = exports.items:nearbyContainerItem()
        local inspectId, inspectUname = false, false
        if not bagId and not ctx.getHeld() then
            inspectId, inspectUname = exports.items:nearbyInspectable()
        end
        -- a Crowbar in hand skips the machine: the plain pickup below deconstructs it (server/hands.lua)
        local crowbar = (ctx.getHeld() or {}).uname == "Crowbar"
        local machineId = not bagId and not inspectId and not crowbar and exports.items:nearbyMachine() or false
        if bagId or inspectId or machineId then
            blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
            if isTimer(interactHoldTimer) then
                return
            end
            local key = string.lower(getKeyBoundToCommand("interact") or "f")
            local startTick = getTickCount()
            local menuSent = false
            interactHoldTimer = setTimer(function()
                if not isKeyHeld(key, "interact") then
                    killTimer(interactHoldTimer)
                    interactHoldTimer = nil
                    if menuSent then
                        triggerServerEvent("machineHoldReleased", localPlayer)
                    elseif getTickCount() - startTick < 500 then
                        if bagId and bagCategory == "bag" then
                            triggerServerEvent("itemBagOpenRequested", localPlayer, bagId)
                        elseif bagId or machineId then
                            triggerServerEvent("itemPickupRequested", localPlayer, exports.items:blockedItemsNear())
                        elseif inspectUname == "Sign" then
                            triggerServerEvent("signEditRequested", localPlayer, inspectId)
                        elseif inspectUname == "PlantPot" then
                            triggerServerEvent("potInspectRequested", localPlayer, inspectId)
                        else
                            triggerServerEvent("bodyInspectRequested", localPlayer, inspectId)
                        end
                    end
                elseif getTickCount() - startTick >= 500 and not menuSent then
                    if machineId then
                        menuSent = true
                        triggerServerEvent("machineMenuRequested", localPlayer, machineId)
                    else
                        killTimer(interactHoldTimer)
                        interactHoldTimer = nil
                        if bagId then
                            triggerServerEvent("itemLongPickupRequested", localPlayer, bagId)
                        else
                            triggerServerEvent("itemPickupRequested", localPlayer, exports.items:blockedItemsNear())
                        end
                    end
                end
            end, 50, 0)
            return
        end
        local nearVeh, nearDist = getNearbyVehicle()
        local held = ctx.getHeld()
        local uname = held and held.uname
        -- a lock tool or key at a walk-in door (the towable Airstream's) is for that trailer, not a truck beside it
        if uname and LOCK_TOOLS[uname] then
            local doorVeh = exports.vehicles:nearbyTrailerDoor()
            if doorVeh then
                blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
                return triggerServerEvent("vehicleInteractRequested", localPlayer, doorVeh)
            end
        end
        if nearVeh and nearDist <= 5.5 then
            local px, py = getElementPosition(localPlayer)
            local vx, vy = getElementPosition(nearVeh)
            local _, _, vrz = getElementRotation(nearVeh)
            local rad = math.rad(vrz or 0)
            local dx, dy = px - vx, py - vy
            local localX = dx * math.cos(rad) + dy * math.sin(rad)
            local localY = -dx * math.sin(rad) + dy * math.cos(rad)
            local angle = (math.deg(math.atan2(localX, localY)) + 360) % 360
            local isFront = angle < 25 or angle > 335
            -- empty hands at the bonnet: a tap opens or shuts it, a hold takes the battery out (vehicles server)
            if not uname and isFront and exports.vehicles:hasBatteryBay(nearVeh) then
                blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
                if isTimer(interactHoldTimer) then
                    return
                end
                local key = string.lower(getKeyBoundToCommand("interact") or "f")
                local startTick = getTickCount()
                local bonnetVeh = nearVeh
                interactHoldTimer = setTimer(function()
                    local heldMs = getTickCount() - startTick
                    local released = not isKeyHeld(key, "interact")
                    if released or heldMs >= 500 then
                        killTimer(interactHoldTimer)
                        interactHoldTimer = nil
                        local eventName = heldMs >= 500 and "vehicleBatteryRequested" or "vehicleInteractRequested"
                        if isElement(bonnetVeh) then
                            triggerServerEvent(eventName, localPlayer, bonnetVeh)
                        end
                    end
                end, 50, 0)
                return
            end
            local isRear = angle > 155 and angle < 205
            if (uname and VEHICLE_TOOLS[uname]) or isRear then
                blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
                return triggerServerEvent("vehicleInteractRequested", localPlayer, nearVeh)
            end
        end
        -- a Petrol Can fills at a pump and pours into an Empty Molotov lying within reach (#136): the server's pickup
        -- with a can in hand only reaches for that bottle, so both requests go and the one with a target acts
        if uname == "GasCan" then
            triggerServerEvent("fuelPumpInteractRequested", localPlayer)
            return triggerServerEvent("itemPickupRequested", localPlayer)
        end
        if uname == "Chainsaw" then
            triggerServerEvent("itemUseRequested", localPlayer, held.id)
            return triggerServerEvent("itemPickupRequested", localPlayer)
        end
        -- a Fishing Rod casts as far as the key was held (a bar fills over 10 s); with the line out F reels it in
        if uname == "FishRod" then
            if fishing then
                return triggerServerEvent("fishCancelRequested", localPlayer)
            end
            if isTimer(interactHoldTimer) then
                return
            end
            local key = string.lower(getKeyBoundToCommand("interact") or "f")
            local startTick = getTickCount()
            exports.ui:progressStart("Casting", MAX_CAST_MS)
            interactHoldTimer = setTimer(function()
                local heldMs = getTickCount() - startTick
                if not isKeyHeld(key, "interact") or heldMs >= MAX_CAST_MS then
                    killTimer(interactHoldTimer)
                    interactHoldTimer = nil
                    exports.ui:progressCancel()
                    -- getWaterLevel is client-only: the water under the spot the line lands on (items fishing.lua
                    -- castPoint, heldMs / 100 m ahead) goes with the cast, false where there is none
                    local px, py, pz = getElementPosition(localPlayer)
                    local _, _, rz = getElementRotation(localPlayer)
                    local dist, rad = math.min(heldMs, MAX_CAST_MS) / 100, math.rad(rz)
                    local water = getWaterLevel(px - dist * math.sin(rad), py + dist * math.cos(rad), pz)
                    triggerServerEvent("fishCastRequested", localPlayer, heldMs, water)
                end
            end, 50, 0)
            return
        end
        -- food is eaten; a held treatment starts its hold, and letting go of the key cancels it (items, #94);
        -- held Clothes start the clothes change (#110); a liquid container is drunk from, sip per hold (#122);
        -- a Note is read or written and a Locator traces its phone (#136); a Parachute is put on
        local drinkable = held and held.category == "liquid"
        local heldType = held and held.uname and exports.data:itemType(held.uname)
        local isExplosive = heldType and heldType.explosive
        if
            held
            and (
                held.category == "food"
                or drinkable
                or TREATMENTS[held.uname]
                or held.uname == "Clothes"
                or isExplosive
                or held.uname == "MobilePhone"
                or held.uname == "Note"
                or held.uname == "Locator"
                or held.uname == "Shield"
                or held.uname == "HerpDerp"
                or held.uname == "Parachute"
                or exports.items:isHandWearable(held.uname)
            )
        then
            blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
            return triggerServerEvent("itemUseRequested", localPlayer, held.id)
        end
        if held and (held.category == "bag" or held.category == "safebox") then
            blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
            return triggerServerEvent("itemBagOpenRequested", localPlayer)
        end
        -- a walk-in vehicle door (the towable Airstream's) only takes the key nothing above wanted, and gives way to a
        -- world item lying nearer (vehicles nearbyTrailerDoor)
        if exports.vehicles:tryTrailerDoor() == true then
            return
        end
        -- a world item within reach takes the press (pickup), so it must not also board a vehicle beside it
        local itemDist = exports.items:nearestItemDistance()
        if itemDist and itemDist <= PICKUP_REACH then
            blockEnterUntil = getTickCount() + TRUNK_ENTER_BLOCK_MS
        end
        triggerServerEvent("itemPickupRequested", localPlayer, exports.items:blockedItemsNear())
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
        -- N cancels attaching a defence and puts the Welder's torch back (vehicles carmour)
        if exports.vehicles:attachModeActive() then
            return exports.vehicles:cancelAttach()
        end
        if exports.vehicles:hasTorch() then
            return triggerServerEvent("weldTorchStowRequested", localPlayer)
        end
        if isTimer(holdTimer) then
            return
        end
        finishTweak()
        local held = ctx.getHeld()
        -- empty hands take a worn parachute off first (upstream parachute.pwn: N with weapon 46 and nothing held)
        if not held and getPedWeapon(localPlayer, 11) == 46 and getPedTotalAmmo(localPlayer, 11) > 0 then
            return triggerServerEvent("itemUnwearRequested", localPlayer, "parachute")
        end
        if not held and getElementData(localPlayer, "items.bag") then
            return triggerServerEvent("itemUnwearRequested", localPlayer, "bag")
        end
        local isCalibreWep = held and held.category == "weapon" and held.calibre ~= nil and not held.liquid
        local key = string.lower(getKeyBoundToCommand("dropitem") or "n")
        local dropEvent = held and ctx.hasPlayerNearby() and "itemGiveRequested" or "itemDropRequested"
        if not isCalibreWep or not isKeyHeld(key, "dropitem") then
            return triggerServerEvent(dropEvent, localPlayer)
        end
        local startTick = getTickCount()
        holdTimer = setTimer(function()
            if not isKeyHeld(key, "dropitem") then
                killTimer(holdTimer)
                holdTimer = nil
                triggerServerEvent(dropEvent, localPlayer)
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
        finishTweak()
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
        finishTweak()
        triggerServerEvent("inventoryOpenRequested", localPlayer)
    end)

    local DEFAULTS = { interact = "f", dropitem = "n", inventory = "h", reloadweapon = "r" }
    -- MTA binds Y to team chat in the core, which unbindKey cannot remove (it only touches this resource's binds);
    -- the gamemode has no teams, so an unbound putaway answers Y itself and swallows the key before the chat sees it
    addEventHandler("onClientKey", root, function(key, press)
        if key ~= "y" or not press or getKeyBoundToCommand("putaway") then
            return
        end
        if not guard() then
            return
        end
        cancelEvent()
        executeCommandHandler("putaway")
    end)
    addEventHandler("onClientResourceStart", resourceRoot, function()
        -- the inventory was on I for a while (#126), move those binds back to upstream's H
        if string.lower(getKeyBoundToCommand("inventory") or "") == "i" then
            unbindKey("i", "down", "inventory")
            bindKey("h", "down", "inventory")
        end
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
    end)
end
