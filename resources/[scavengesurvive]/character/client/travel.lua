-- The jump boost and the jump count (upstream char/travel-stats.pwn JumpBoost, #138): a jump started while running
-- or sprinting is pushed on by 1 + 1.3 x Endurance (the skill rows the server sends), and every jump on foot is
-- reported so the server counts it towards the skill.
-- read and closed again: a handle left open locks the client's cached copy, so a changed file fails to download
local travel
do
    local f = fileOpen("shared/logic/travel.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    travel = assert(loadstring(src, "=character/travel.lua"))()
end
local endurance = 0
local lastReport = 0
local REPORT_GAP_MS = 400 -- the server rate-limits at 3 a second

addEventHandler("characterSkillsSynced", localPlayer, function(rows)
    endurance = 0
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.name == "Endurance" then
            endurance = tonumber(r.amount) or 0
        end
    end
end)

local function onJump()
    if getPedOccupiedVehicle(localPlayer) or isPedDead(localPlayer) then
        return
    end
    if getElementData(localPlayer, "character.knockedOut") or getElementData(localPlayer, "character.cuffed") then
        return
    end
    local now = getTickCount()
    if now - lastReport >= REPORT_GAP_MS then
        lastReport = now
        triggerServerEvent("playerJumped", localPlayer)
    end
    local moving = getPedMoveState(localPlayer)
    if moving ~= "powerwalk" and moving ~= "sprint" then
        return
    end
    local boost = travel.boost(endurance)
    if boost <= 1 then
        return
    end
    -- upstream deferred the push to the next tick, when the jump has its own velocity
    setTimer(function()
        if isElement(localPlayer) and not getPedOccupiedVehicle(localPlayer) then
            local vx, vy, vz = getElementVelocity(localPlayer)
            setElementVelocity(localPlayer, vx * boost, vy * boost, vz * boost)
        end
    end, 50, 1)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("jump", "down", onJump)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("jump", "down", onJump)
end)
