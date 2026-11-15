-- The keys behind the poses and the aim shout (#140, shared/logic/poses.lua): crouch held while standing still
-- asks to sit (a short tap stays a crouch), crouch, sprint or jump while sitting asks to stand, sprint with
-- crouch asks for hands up, crouch alone while they are up asks to lower them, and aim with look-behind (on
-- foot) or look-behind with the horn (driving) shouts the /aimshout line. The server decides and plays the animation.
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

-- The hands-up controls must never outlive the animation: something else (a crouch, a weapon swap) can end it and
-- leave the player standing normally but unable to walk. While the hands are up, an animation that is no longer
-- the hands-up one asks the server to lower them. A grace period lets the server's animation reach this client.
local HANDS_GRACE_MS = 1500
local HANDS_CHECK_MS = 500
local handsTimer = nil
local handsSince = 0
local handsLowerAsked = false

local function stopHandsWatch()
    if isTimer(handsTimer) then
        killTimer(handsTimer)
    end
    handsTimer = nil
end

local function handsAnimPlaying()
    local block, anim = getPedAnimation(localPlayer)
    local want = poses.ANIMS.handsUp
    return block and anim and block:lower() == want[1]:lower() and anim:lower() == want[2]:lower()
end

local function startHandsWatch()
    stopHandsWatch()
    handsSince = getTickCount()
    handsLowerAsked = false
    handsTimer = setTimer(function()
        if pose ~= "handsUp" then
            return stopHandsWatch()
        end
        if handsLowerAsked or getTickCount() - handsSince < HANDS_GRACE_MS or handsAnimPlaying() then
            return
        end
        handsLowerAsked = true
        triggerServerEvent("handsUpRequested", localPlayer)
    end, HANDS_CHECK_MS, 0)
end

addEventHandler("poseChanged", localPlayer, function(p)
    pose = p or false
    if pose == "handsUp" then
        startHandsWatch()
    else
        stopHandsWatch()
    end
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
        -- crouch alone lowers raised hands (walking is off while they are up, crouch is the way out)
        if pose == "handsUp" or getPedControlState("sprint") then
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
    stopHandsWatch()
    unbindKey("crouch", "both", onCrouch)
    unbindKey("sprint", "down", onSprint)
    unbindKey("jump", "down", onJump)
    unbindKey("aim_weapon", "down", onShoutKey)
    unbindKey("look_behind", "down", onShoutKey)
    unbindKey("vehicle_look_behind", "down", onShoutKey)
    unbindKey("horn", "down", onShoutKey)
end)
