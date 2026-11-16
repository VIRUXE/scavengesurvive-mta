-- /fly: free flight for staff. W/S fly forwards/backwards along the ped's heading (level), A/D turn it, Space/C
-- climb/descend, Shift fast, Alt slow, mouse wheel sets the cruise speed. Walls and the ground do not stop it, GTA's
-- own controls are switched off while flying (so C does not crouch, the wheel does not swap weapons) and the keys are
-- read straight from the keyboard: the movement keys as bound, the rest as fixed keys (GTA binds Space to sprint and
-- Shift to jump, which is the wrong way round here). Falling after landing in mid-air does no harm.

local BASE_SPEED = 20 -- m/s at the default wheel step
local MIN_SPEED, MAX_SPEED = 2, 400
local WHEEL_STEP = 1.25
local FAST, SLOW = 4, 0.2
local RESPONSE = 8 -- 1/s: how fast the velocity follows the keys
local TURN_RATE = 150 -- degrees a second for A/D
local FIXED = { -- action -> keys, not taken from GTA's binds
    up = { "space" },
    down = { "c", "lctrl" },
    fast = { "lshift", "rshift" },
    slow = { "lalt" },
}
local LANDING_GRACE_MS = 15000

-- every on-foot control GTA would act on while a movement key is held
local CONTROLS = {
    "fire",
    "aim_weapon",
    "next_weapon",
    "previous_weapon",
    "forwards",
    "backwards",
    "left",
    "right",
    "zoom_in",
    "zoom_out",
    "jump",
    "sprint",
    "crouch",
    "walk",
    "action",
    "look_behind",
    "enter_exit",
    "enter_passenger",
    "conversation_yes",
    "conversation_no",
}

local flying = false
local speed = BASE_SPEED
local vx, vy, vz = 0, 0, 0
local disabled = {} -- controls this script switched off
local keys = {} -- control -> list of bound keys, read when flying starts
local landingUntil = 0
local heading = 0
local px, py, pz -- where the flight holds the ped; GTA's gravity pulls it down between frames
local TELEPORT_GAP = 5 -- metres off that point: something else moved the ped (a staff teleport), follow it

local function readBinds()
    keys = {}
    for _, control in ipairs(CONTROLS) do
        local list = {}
        for key in pairs(getBoundKeys(control) or {}) do
            list[#list + 1] = key
        end
        keys[control] = list
    end
    -- unbound controls fall back to the default keys
    local defaults = { forwards = "w", backwards = "s", left = "a", right = "d" }
    for control, key in pairs(defaults) do
        if #keys[control] == 0 then
            keys[control] = { key }
        end
    end
    for action, list in pairs(FIXED) do
        keys[action] = list
    end
end

local function held(control)
    for _, key in ipairs(keys[control]) do
        if getKeyState(key) then
            return true
        end
    end
    return false
end

local function typing()
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isCursorShowing()
end

local function onWheel(_, _, dir)
    if not flying or typing() then
        return
    end
    speed = math.max(MIN_SPEED, math.min(MAX_SPEED, dir > 0 and speed * WHEEL_STEP or speed / WHEEL_STEP))
end

local function setFlying(on, quiet)
    if on == flying then
        return
    end
    if on and (getPedOccupiedVehicle(localPlayer) or isPedDead(localPlayer)) then
        outputChatBox("[dev] fly: get out of the vehicle first", 255, 120, 120)
        triggerServerEvent("devFlyActiveChanged", localPlayer, false)
        return
    end
    flying = on
    if on then
        readBinds()
        vx, vy, vz = 0, 0, 0
        local _, _, rz = getElementRotation(localPlayer)
        heading = rz
        px, py, pz = getElementPosition(localPlayer)
        for _, control in ipairs(CONTROLS) do
            if isControlEnabled(control) then
                toggleControl(control, false)
                disabled[#disabled + 1] = control
            end
        end
        setElementCollisionsEnabled(localPlayer, false)
        bindKey("mouse_wheel_up", "down", onWheel, 1)
        bindKey("mouse_wheel_down", "down", onWheel, -1)
    else
        for _, control in ipairs(disabled) do
            toggleControl(control, true)
        end
        disabled = {}
        setElementCollisionsEnabled(localPlayer, true)
        unbindKey("mouse_wheel_up", "down", onWheel)
        unbindKey("mouse_wheel_down", "down", onWheel)
        setElementVelocity(localPlayer, vx / 50, vy / 50, math.min(0, vz / 50))
        landingUntil = getTickCount() + LANDING_GRACE_MS
    end
    if not quiet then
        outputChatBox(
            on and "[dev] fly on: W/S forwards/back, A/D turn, Space/C up/down, Shift fast, Alt slow, wheel speed"
                or "[dev] fly off",
            120,
            200,
            255
        )
        triggerServerEvent("devFlyActiveChanged", localPlayer, on)
    end
end

addEventHandler("devFlyStateChanged", root, function(enabled)
    setFlying(enabled == true)
end)

addEventHandler("onClientPreRender", root, function(slice)
    if not flying then
        -- the fall's damage lands with the first ground contact; drop the grace soon after it
        if landingUntil > 0 and isPedOnGround(localPlayer) then
            landingUntil = math.min(landingUntil, getTickCount() + 500)
        end
        return
    end
    if getPedOccupiedVehicle(localPlayer) or isPedDead(localPlayer) then
        return setFlying(false)
    end
    local dt = math.min(slice, 100) / 1000

    local tx, ty, tz = 0, 0, 0
    if not typing() then
        local turn = (held("left") and 1 or 0) - (held("right") and 1 or 0)
        heading = (heading + turn * TURN_RATE * dt) % 360
        local f = (held("forwards") and 1 or 0) - (held("backwards") and 1 or 0)
        local u = (held("up") and 1 or 0) - (held("down") and 1 or 0)
        local rad = math.rad(heading)
        tx, ty, tz = -math.sin(rad) * f, math.cos(rad) * f, u
        local m = math.sqrt(tx * tx + ty * ty + tz * tz)
        if m > 0 then
            local v = speed * (held("fast") and FAST or 1) * (held("slow") and SLOW or 1)
            tx, ty, tz = tx / m * v, ty / m * v, tz / m * v
        end
    end

    local k = 1 - math.exp(-RESPONSE * dt)
    vx, vy, vz = vx + (tx - vx) * k, vy + (ty - vy) * k, vz + (tz - vz) * k

    local x, y, z = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > TELEPORT_GAP then
        px, py, pz = x, y, z
    end
    px, py, pz = px + vx * dt, py + vy * dt, pz + vz * dt
    setElementVelocity(localPlayer, 0, 0, 0)
    setElementPosition(localPlayer, px, py, pz, false)
    setElementRotation(localPlayer, 0, 0, heading, "default", true)
end)

addEventHandler("onClientRender", root, function()
    if not flying then
        return
    end
    local sw, sh = guiGetScreenSize()
    local v = math.sqrt(vx * vx + vy * vy + vz * vz)
    local text = string.format(
        "FLY %.0f m/s (cruise %.0f)  W/S move · A/D turn · Space/C up/down · Shift/Alt fast/slow · wheel speed",
        v,
        speed
    )
    dxDrawText(text, 1, sh - 39, sw + 1, sh + 1, 0xC0000000, 1, "default-bold", "center", "top")
    dxDrawText(text, 0, sh - 40, sw, sh, 0xFFB4DCFF, 1, "default-bold", "center", "top")
end)

-- no damage while flying, nor from the fall after stopping in mid-air
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if flying then
        return cancelEvent()
    end
    if landingUntil > 0 then
        if getTickCount() < landingUntil then
            cancelEvent()
        end
        if getTickCount() >= landingUntil then
            landingUntil = 0
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setFlying(false, true)
end)
