-- rcon "key <player> <command>": runs a bound command (interact, dropitem, putaway, inventory) or dispatches a
-- client key press (arrow_u, arrow_d, enter, escape) so a live check can be driven from a script.
addEventHandler("devKeyPressed", root, function(command)
    if not executeCommandHandler(command) then
        triggerEvent("onClientKey", root, command, true)
    end
end)

-- rcon "clua <player> <code>": runs a chunk on this client and prints its return values (or the error) to chat,
-- where "rcon chat <player>" reads them. Dev-only, like the server-side lua verb.
addEventHandler("devClientLuaRequested", root, function(code)
    local chunk, err = loadstring(code, "=rcon-client")
    if not chunk then
        return outputChatBox("[clua] compile error: " .. tostring(err))
    end
    local r = { pcall(chunk) }
    if not table.remove(r, 1) then
        return outputChatBox("[clua] runtime error: " .. tostring(r[1]))
    end
    if #r == 0 then
        return outputChatBox("[clua] ok (no return values)")
    end
    for i = 1, #r do
        local v = r[i]
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(x)
            end
            table.sort(parts)
            v = "{ " .. table.concat(parts, ", ") .. " }"
        end
        outputChatBox(string.format("[clua] [%d] %s", i, tostring(v)))
    end
end)

-- Fly feature ported from upstream filterscripts/fly.pwn
local VELOCITY_MULT = 3.0
local VELOCITY_NORM = 1.0
local HEIGHT_GAIN = 0.5

local canFly = false
local isFlying = false
local flyAngle = 0

addEventHandler("devFlyStateChanged", root, function(enabled, activateNow)
    canFly = enabled == true
    if activateNow then
        isFlying = true
        local _, _, rz = getElementRotation(localPlayer)
        flyAngle = rz
        triggerServerEvent("devFlyActiveChanged", localPlayer, true)
    elseif not canFly and isFlying then
        isFlying = false
        triggerServerEvent("devFlyActiveChanged", localPlayer, false)
    end
end)

local function toggleFly()
    if not canFly then
        return
    end
    isFlying = not isFlying
    if isFlying then
        local _, _, rz = getElementRotation(localPlayer)
        flyAngle = rz
    end
    triggerServerEvent("devFlyActiveChanged", localPlayer, isFlying)
end

bindKey("jump", "down", function()
    if not canFly then
        return
    end
    if getPedControlState(localPlayer, "enter_exit") or getKeyState("f") or getKeyState("enter") then
        toggleFly()
    end
end)

bindKey("enter_exit", "down", function()
    if not canFly then
        return
    end
    if getPedControlState(localPlayer, "jump") or getKeyState("space") or getKeyState("lshift") then
        toggleFly()
    end
end)

addEventHandler("onClientPreRender", root, function(slice)
    if not isFlying or not canFly then
        return
    end
    if getPedOccupiedVehicle(localPlayer) or isPedDead(localPlayer) then
        isFlying = false
        triggerServerEvent("devFlyActiveChanged", localPlayer, false)
        return
    end

    local dt = slice / 1000
    local forwd = 0.0
    local hMult = 0.01

    local up = getPedControlState(localPlayer, "forwards")
    local down = getPedControlState(localPlayer, "backwards")
    local left = getPedControlState(localPlayer, "left")
    local right = getPedControlState(localPlayer, "right")
    local jump = getPedControlState(localPlayer, "jump")
    local sprint = getPedControlState(localPlayer, "sprint")
    local crouch = getPedControlState(localPlayer, "crouch")
    local fire = getPedControlState(localPlayer, "fire")

    if up then
        forwd = VELOCITY_NORM
    elseif down then
        forwd = -VELOCITY_NORM
    end

    if jump then
        forwd = forwd * VELOCITY_MULT
    end

    if sprint then
        hMult = HEIGHT_GAIN
        if jump then
            hMult = HEIGHT_GAIN * 2
        end
    elseif crouch then
        hMult = -HEIGHT_GAIN
    end

    if fire then
        if left then
            forwd = VELOCITY_NORM
            flyAngle = flyAngle + 90.0
        elseif right then
            forwd = VELOCITY_NORM
            flyAngle = flyAngle - 90.0
        end
    else
        if left then
            flyAngle = flyAngle + (180.0 * dt)
        elseif right then
            flyAngle = flyAngle - (180.0 * dt)
        end
        setElementRotation(localPlayer, 0, 0, flyAngle, "default", true)
    end

    local rad = math.rad(-flyAngle)
    local vx = forwd * math.sin(rad)
    local vy = forwd * math.cos(rad)
    setElementVelocity(localPlayer, vx, vy, hMult)
end)

addEventHandler("onClientPlayerDamage", localPlayer, function()
    if isFlying then
        cancelEvent()
    end
end)

-- rcon "chat <player>": every chat line this client receives is echoed to the server, which keeps the last
-- hundred per player. Screenshots never include the chat box, so a scripted live check reads replies this way.
addEventHandler("onClientChatMessage", root, function(text)
    triggerServerEvent("devChatLineReceived", localPlayer, text)
end)
