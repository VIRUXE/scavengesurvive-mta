-- Ladders and ziplines on the client (upstream samp-ladders / samp-zipline, see shared/logic/features.lua).
-- The local player's movement is client-owned in MTA, so the climb and the ride run here: hud's interact key
-- calls tryInteract() first, and nearbyFeature() feeds the "F Climb ladder" / "F Grab zipline" lines; a button in
-- reach (client/buttons.lua) comes after them.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local F = loadFile("shared/logic/features.lua", "=world/features.lua")
local data = loadFile("data/features.lua", "=world/features_data.lua")
local ladders, ziplines = data.ladders, data.ziplines

local onLadder = nil -- { idx, since, animUp }
local onZip = nil -- { idx, mult, timer }
local CLIMB_CONTROLS =
    { "forwards", "backwards", "left", "right", "sprint", "jump", "fire", "aim_weapon", "enter_exit" }

local function setClimbControls(enabled)
    for _, ctrl in ipairs(CLIMB_CONTROLS) do
        toggleControl(ctrl, enabled)
    end
end

local exitZipline -- defined with the zipline code below; a ladder grab while riding lets go first

local function keyHeld(control)
    local keys = getBoundKeys(control)
    if keys then
        for key in pairs(keys) do
            if getKeyState(key) then
                return true
            end
        end
    end
    local dev = getResourceFromName("dev")
    return dev and getResourceState(dev) == "running" and exports.dev:isHeld(control) == true
end

local function busy()
    return isPedDead(localPlayer)
        or getPedOccupiedVehicle(localPlayer) ~= false
        or getElementData(localPlayer, "character.knockedOut") == true
        or getElementData(localPlayer, "character.cuffed") == true
end

-- Ladders -----------------------------------------------------------------------------------------------------

local function climbAnim(hang)
    if hang then
        setPedAnimation(localPlayer, "FINALE", "FIN_HANG_LOOP", -1, true, false, false, false)
    else
        setPedAnimation(localPlayer, "PED", "CLIMB_IDLE", -1, false, false, false, true)
    end
end

local function exitLadder()
    if not onLadder then
        return
    end
    local l = ladders[onLadder.idx]
    onLadder = nil
    setPedAnimation(localPlayer)
    setClimbControls(true)
    setElementRotation(localPlayer, 0, 0, l[5])
    setElementVelocity(localPlayer, F.ladderExitVelocity(l[5]))
end

local function enterLadder(idx)
    local l = ladders[idx]
    local _, _, z = getElementPosition(localPlayer)
    if onZip then
        exitZipline(false)
    end
    setPedAnimation(localPlayer)
    setElementRotation(localPlayer, 0, 0, l[5])
    setElementPosition(localPlayer, l[1], l[2], F.ladderEnterZ(l, z))
    setClimbControls(false)
    onLadder = { idx = idx, since = getTickCount(), animUp = false }
    climbAnim(false)
end

local function ladderFrame()
    local l = ladders[onLadder.idx]
    local _, _, z = getElementPosition(localPlayer)
    if F.ladderShouldExit(l, z, getTickCount() - onLadder.since) then
        return exitLadder()
    end
    local direction = keyHeld("forwards") and "up" or (keyHeld("backwards") and "down" or nil)
    if direction then
        -- upstream alternates the two climbing animations while a key is held
        if getTickCount() % 600 < 300 ~= onLadder.animUp then
            onLadder.animUp = not onLadder.animUp
            climbAnim(onLadder.animUp)
        end
    elseif onLadder.animUp then
        onLadder.animUp = false
        climbAnim(false)
    end
    setElementVelocity(localPlayer, 0, 0, F.ladderVelocity(direction))
end

-- Ziplines ----------------------------------------------------------------------------------------------------

exitZipline = function(boost)
    if not onZip then
        return
    end
    local zl = ziplines[onZip.idx]
    if isTimer(onZip.timer) then
        killTimer(onZip.timer)
    end
    local mult = onZip.mult
    onZip = nil
    setPedAnimation(localPlayer)
    setClimbControls(true)
    if boost then
        local ux, uy, uz = F.ziplineVector(zl)
        local m = mult + F.ZIP_EXIT_BOOST
        setElementVelocity(localPlayer, ux * m, uy * m, uz * m)
    end
end

local function zipTick()
    if not onZip then
        return
    end
    local zl = ziplines[onZip.idx]
    local x, y, z = getElementPosition(localPlayer)
    local leave = F.ziplineShouldExit(zl, x, y, z)
    if leave then
        return exitZipline(true)
    end
    local mult, vx, vy, vz = F.ziplineStep(zl, onZip.mult)
    onZip.mult = mult
    setElementVelocity(localPlayer, vx, vy, vz)
end

local function enterZipline(idx)
    local zl = ziplines[idx]
    local x, y, z = getElementPosition(localPlayer)
    local t = F.ziplineProject(zl, x, y, z + F.ZIP_HANG_BELOW)
    local px, py, pz, angle = F.ziplineRiderPos(zl, t)
    setPedAnimation(localPlayer)
    setElementPosition(localPlayer, px, py, pz)
    setElementRotation(localPlayer, 0, 0, angle)
    setPedAnimation(localPlayer, "PED", "CLIMB_IDLE", -1, true, false, false, true)
    setClimbControls(false)
    onZip = { idx = idx, mult = F.ZIP_SPEED_START }
    onZip.timer = setTimer(zipTick, F.ZIP_TICK_MS, 0)
end

-- Shared ------------------------------------------------------------------------------------------------------

addEventHandler("onClientRender", root, function()
    if onLadder then
        ladderFrame()
    end
end)

-- hud shows this next to F; "ladder" / "zipline" to grab, "ladder_on" / "zipline_on" to let go, or nil
function nearbyFeature()
    if onLadder then
        return "ladder_on"
    end
    if onZip then
        return "zipline_on"
    end
    if busy() then
        return nil
    end
    local x, y, z = getElementPosition(localPlayer)
    if F.ladderAt(ladders, x, y, z) then
        return "ladder"
    end
    if F.ziplineAt(ziplines, x, y, z) then
        return "zipline"
    end
    return buttonNear() -- client/buttons.lua
end

-- hud's interact key: true when the press was used by a ladder or a zipline
function tryInteract()
    if onLadder then
        exitLadder()
        return true
    end
    if onZip then
        exitZipline(true)
        return true
    end
    if busy() then
        return false
    end
    local x, y, z = getElementPosition(localPlayer)
    local li = F.ladderAt(ladders, x, y, z)
    if li then
        enterLadder(li)
        return true
    end
    local zi = F.ziplineAt(ziplines, x, y, z)
    if zi then
        enterZipline(zi)
        return true
    end
    return buttonInteract() -- client/buttons.lua
end

-- The rope: a line between the anchors, drawn when either end is within 300 m (upstream used 2.46 m objects of
-- model 19087, which is SA-MP-only and not in the model pack).
local ROPE = tocolor(40, 40, 40, 255)
addEventHandler("onClientRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    for _, zl in ipairs(ziplines) do
        if
            getDistanceBetweenPoints3D(cx, cy, cz, zl[1], zl[2], zl[3]) < 300
            or getDistanceBetweenPoints3D(cx, cy, cz, zl[4], zl[5], zl[6]) < 300
        then
            dxDrawLine3D(zl[1], zl[2], zl[3], zl[4], zl[5], zl[6], ROPE, 3)
        end
    end
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if onLadder then
        onLadder = nil
        setClimbControls(true)
    end
    if onZip then
        exitZipline(false)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if onLadder then
        exitLadder()
    end
    if onZip then
        exitZipline(false)
    end
end)
