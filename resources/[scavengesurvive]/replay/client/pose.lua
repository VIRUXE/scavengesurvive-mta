-- luacheck: read_globals isPedInVehicle isElementInWater getPedMoveState getPedAnimation getPedTargetEnd
-- Recorder, client half: the server cannot read a player's walk/run state, animation or aim point, so each client
-- reports them (only when they change, at most 5 a second) for server/recorder.lua to write into the flight record.
-- Cosmetic metadata for the replay; the server clamps it and nothing in the game reads it back.
local TICK_MS = 200
local AIM_MIN_MOVE = 0.3 -- metres the aim point has to move to be worth a report
local STATES = {
    stand = "stand",
    walk = "walk",
    powerwalk = "walk",
    jog = "run",
    sprint = "sprint",
    crouch = "crouch",
    crawl = "crouch",
    jump = "jump",
    fall = "fall",
    climb = "climb",
}

local last = { mv = nil, an = nil, ax = nil, ay = nil, az = nil, aiming = false }

local function currentMove()
    if isPedInVehicle(localPlayer) then
        return "vehicle"
    end
    if isElementInWater(localPlayer) then
        return "swim"
    end
    return STATES[getPedMoveState(localPlayer) or "stand"] or "stand"
end

local function tick()
    if not isElement(localPlayer) or isPedDead(localPlayer) then
        return
    end
    local mv = currentMove()
    local block, name = getPedAnimation(localPlayer)
    local an = block and name and (block .. "|" .. name) or nil
    local ax, ay, az
    if getPedControlState(localPlayer, "aim_weapon") and (getPedWeapon(localPlayer) or 0) > 0 then
        ax, ay, az = getPedTargetEnd(localPlayer)
    end
    local aimMoved = false
    if ax then
        aimMoved = not last.ax
            or (ax - last.ax) ^ 2 + (ay - last.ay) ^ 2 + (az - last.az) ^ 2 >= AIM_MIN_MOVE * AIM_MIN_MOVE
    elseif last.aiming then
        aimMoved = true
    end
    if mv ~= last.mv or an ~= last.an or aimMoved then
        last.mv, last.an, last.aiming = mv, an, ax ~= nil
        if ax then
            last.ax, last.ay, last.az = ax, ay, az
        else
            last.ax, last.ay, last.az = nil, nil, nil
        end
        triggerServerEvent("replayPoseReported", localPlayer, mv, an, ax, ay, az)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(tick, TICK_MS, 0)
end)
