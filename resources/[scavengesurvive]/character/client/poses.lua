-- The keys behind the poses and the aim shout (#140, shared/logic/poses.lua): crouch held while standing still
-- asks to sit (a short tap stays a crouch), crouch, sprint or jump while sitting asks to stand, sprint with
-- crouch asks for hands up or down, and aim with look-behind (on foot) or look-behind with the horn (driving)
-- shouts the /aimshout line. The server decides and plays the animation.
-- read and closed again: a handle left open locks the client's cached copy, so a changed file fails to download
local poses
do
    local f = fileOpen("shared/logic/poses.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    poses = assert(loadstring(src, "=character/poses.lua"))()
end
local pose = false -- what the server last confirmed: false, "sitting" or "handsUp"
local crouchDownAt = nil
local sitTimer = nil

addEventHandler("poseChanged", localPlayer, function(p)
    pose = p or false
end)

local function free()
    return not isPedDead(localPlayer)
        and not getPedOccupiedVehicle(localPlayer)
        and not getElementData(localPlayer, "character.knockedOut")
        and not getElementData(localPlayer, "character.cuffed")
        and not isChatBoxInputActive()
        and not isMTAWindowActive()
end

local function still()
    local vx, vy, vz = getElementVelocity(localPlayer)
    return math.sqrt(vx * vx + vy * vy + vz * vz) < poses.STILL_SPEED
end

local function stopSitTimer()
    if isTimer(sitTimer) then
        killTimer(sitTimer)
    end
    sitTimer = nil
end

local function onCrouch(_, press)
    if press == "down" then
        if not free() then
            return
        end
        if pose == "sitting" then
            return triggerServerEvent("standRequested", localPlayer)
        end
        if getPedControlState("sprint") then
            return triggerServerEvent("handsUpRequested", localPlayer)
        end
        if not still() then
            return
        end
        crouchDownAt = getTickCount()
        stopSitTimer()
        sitTimer = setTimer(function()
            sitTimer = nil
            if free() and still() and pose == false then
                triggerServerEvent("sitRequested", localPlayer)
            end
        end, poses.SIT_HOLD_MS, 1)
    elseif crouchDownAt then
        if not poses.crouchWasSit(getTickCount() - crouchDownAt) then
            stopSitTimer()
        end
        crouchDownAt = nil
    end
end

local function onSprint()
    if not free() then
        return
    end
    if pose == "sitting" then
        return triggerServerEvent("standRequested", localPlayer)
    end
    if getPedControlState("crouch") and still() then
        triggerServerEvent("handsUpRequested", localPlayer)
    end
end

local function onJump()
    if pose == "sitting" and free() then
        triggerServerEvent("standRequested", localPlayer)
    end
end

local function onShoutKey()
    if isPedDead(localPlayer) or isChatBoxInputActive() then
        return
    end
    local combo
    if getPedOccupiedVehicle(localPlayer) then
        combo = getPedControlState("vehicle_look_behind") and getPedControlState("horn")
    else
        combo = getPedControlState("aim_weapon") and getPedControlState("look_behind")
    end
    if combo then
        triggerServerEvent("aimShoutRequested", localPlayer)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("crouch", "both", onCrouch)
    bindKey("sprint", "down", onSprint)
    bindKey("jump", "down", onJump)
    bindKey("aim_weapon", "down", onShoutKey)
    bindKey("look_behind", "down", onShoutKey)
    bindKey("vehicle_look_behind", "down", onShoutKey)
    bindKey("horn", "down", onShoutKey)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopSitTimer()
    unbindKey("crouch", "both", onCrouch)
    unbindKey("sprint", "down", onSprint)
    unbindKey("jump", "down", onJump)
    unbindKey("aim_weapon", "down", onShoutKey)
    unbindKey("look_behind", "down", onShoutKey)
    unbindKey("vehicle_look_behind", "down", onShoutKey)
    unbindKey("horn", "down", onShoutKey)
end)
