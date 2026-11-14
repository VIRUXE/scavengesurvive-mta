-- Client-side crafting hold-action animator and key bindings.
local activeAction = nil
local lastPos = nil
local releaseTimer = nil

-- A hold that one press of the interact key started (the Crowbar taking furniture apart) goes on only while the key
-- stays down: letting go cancels it on the server too. A hold that did not come from a fresh press (a menu pick)
-- keeps its old rules. See vehicles/client/main.lua, which does the same for the vehicle holds.
local HOLD_PRESS_WINDOW_MS = 450
local lastInteractPress = -math.huge

local function interactKey()
    return string.lower(getKeyBoundToCommand("interact") or "f")
end

local function isKeyHeld(key, cmd)
    if getKeyState(key) then
        return true
    end
    local dev = getResourceFromName("dev")
    return dev and getResourceState(dev) == "running" and exports.dev:isHeld(cmd or key) == true
end

addEventHandler("onClientKey", root, function(button, press)
    if press and button == interactKey() then
        lastInteractPress = getTickCount()
    end
end)

local function stopReleaseWatch()
    if isTimer(releaseTimer) then
        killTimer(releaseTimer)
    end
    releaseTimer = nil
end

local function cancelAction(tellServer)
    stopReleaseWatch()
    if activeAction then
        activeAction = nil
        lastPos = nil
        exports.ui:progressCancel()
        if tellServer then
            triggerServerEvent("craftHoldCancelRequested", localPlayer)
        end
    end
end

addEventHandler("craftHoldStarted", root, function(actionType, durationMs)
    activeAction = actionType
    local x, y, z = getElementPosition(localPlayer)
    lastPos = { x = x, y = y, z = z }
    exports.ui:progressStart(actionType, durationMs)
    stopReleaseWatch()
    local key = interactKey()
    local held = isKeyHeld(key, "interact")
    if not held and getTickCount() - lastInteractPress > HOLD_PRESS_WINDOW_MS then
        return
    end
    if not held then
        return cancelAction(true)
    end
    releaseTimer = setTimer(function()
        if not isKeyHeld(key, "interact") then
            cancelAction(true)
        end
    end, 100, 0)
end)

addEventHandler("craftHoldStopped", root, function()
    cancelAction(false)
end)

addEventHandler("onClientRender", root, function()
    if not activeAction or not lastPos then
        return
    end
    if isPedDead(localPlayer) then
        return cancelAction(true)
    end
    local x, y, z = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(x, y, z, lastPos.x, lastPos.y, lastPos.z)
    if dist > 0.8 then
        cancelAction(true)
    end
end)
