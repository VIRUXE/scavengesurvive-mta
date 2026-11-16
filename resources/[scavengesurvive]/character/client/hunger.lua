-- luacheck: read globals dxCreateScreenSource dxCreateShader dxSetShaderValue dxUpdateScreenSource
-- Hunger and thirst effects on the local player (shared/logic/hunger.lua): the screen shader (client/hunger.fx),
-- the sprint cap and the sprint/jump lock, and the cues. The thirst sway and the aim sway go through the camera drunk
-- level, which client/medical.lua owns. Nothing applies on staff duty or once dead.
-- read and closed again: a handle left open locks the client's cached copy, so a changed file fails to download
local hunger
do
    local f = fileOpen("shared/logic/hunger.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    hunger = assert(loadstring(src, "=character/hunger.lua"))()
end
hunger.tr = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")().text

local TICK_MS = 250
local SOUNDS = { hunger = "files/growl.ogg", thirst = "files/cough.ogg" }

local stats = { food = 100, thirst = 100, drugs = {} }
local pose = false
local screenSource, shader, fx = nil, nil, nil
local locked = {} -- control -> true: switched off here, so switched back on here
local sprintMs, coolUntil = 0, 0
local lastCue = 0

addEventHandler("characterStatsSynced", localPlayer, function(s)
    stats.food = tonumber(s.food) or stats.food
    stats.thirst = tonumber(s.thirst) or stats.thirst
    stats.drugs = type(s.drugs) == "table" and s.drugs or {}
end)

addEventHandler("poseChanged", localPlayer, function(p)
    pose = p or false
end)

local function freeScreen()
    if isElement(shader) then
        destroyElement(shader)
    end
    if isElement(screenSource) then
        destroyElement(screenSource)
    end
    shader, screenSource, fx = nil, nil, nil
end

local function draw()
    if not fx then
        return
    end
    local sw, sh = guiGetScreenSize()
    if shader then
        dxUpdateScreenSource(screenSource)
        dxDrawImage(0, 0, sw, sh, shader)
    else
        -- no shader (old card or out of video memory): a plain darkening instead
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, math.floor(fx.vignette * 90)))
    end
end

local function setScreen(next)
    if not hunger.active(next) then
        if fx then
            freeScreen()
        end
        return
    end
    if not fx then
        local sw, sh = guiGetScreenSize()
        screenSource = dxCreateScreenSource(sw, sh)
        shader = screenSource and dxCreateShader("client/hunger.fx") or nil
        if shader then
            dxSetShaderValue(shader, "ScreenTexture", screenSource)
            dxSetShaderValue(shader, "Aspect", sw / sh, 1)
        elseif isElement(screenSource) then
            destroyElement(screenSource)
            screenSource = nil
        end
    end
    fx = next
    if shader then
        dxSetShaderValue(shader, "Desat", fx.desat)
        dxSetShaderValue(shader, "Vignette", fx.vignette)
        dxSetShaderValue(shader, "Blur", fx.blur)
    end
end

-- Sprint and jump are also switched off by the server (knockout, cuffs, hands up) and the staff fly: a control is
-- only switched back on here when it was switched off here and none of those holds it.
local function heldElsewhere()
    return getElementData(localPlayer, "character.knockedOut")
        or getElementData(localPlayer, "character.cuffed")
        or pose == "handsUp"
end

local function lock(control, off)
    if off then
        if isControlEnabled(control) then
            toggleControl(control, false)
        end
        locked[control] = true
    elseif locked[control] then
        if not heldElsewhere() then
            toggleControl(control, true)
        end
        locked[control] = nil
    end
end

local function releaseAll()
    for control in pairs(locked) do
        lock(control, false)
    end
    sprintMs, coolUntil = 0, 0
end

local function legs(now)
    -- a knocked out, cuffed or hands-up character's controls belong to the server until it lets go
    if heldElsewhere() then
        return
    end
    local l = hunger.legs(stats.food, stats.thirst, stats.drugs)
    local sprintOff = not l.sprint or now < coolUntil
    if l.sprint and l.maxMs and not sprintOff then
        if getPedControlState(localPlayer, "sprint") and getPedMoveState(localPlayer) == "sprint" then
            sprintMs = sprintMs + TICK_MS
            if sprintMs >= l.maxMs then
                coolUntil, sprintMs, sprintOff = now + l.cooldownMs, 0, true
            end
        else
            sprintMs = math.max(0, sprintMs - TICK_MS / 2)
        end
    elseif not l.maxMs then
        sprintMs = 0
    end
    lock("sprint", sprintOff)
    lock("jump", not l.jump)
end

local function cue(now)
    local kind, text = hunger.cue(stats.food, stats.thirst, now - lastCue)
    if not kind then
        return
    end
    lastCue = now
    exports.ui:actionTextShow(text, 4000)
    local s = playSound(SOUNDS[kind])
    if s then
        setSoundVolume(s, 0.7)
    end
end

local function update()
    if isPedDead(localPlayer) or getElementData(localPlayer, "staff.duty") == true then
        setScreen({ desat = 0, vignette = 0, blur = 0 })
        releaseAll()
        return
    end
    local now = getTickCount()
    setScreen(hunger.screen(stats.food, stats.thirst, stats.drugs))
    if getPedOccupiedVehicle(localPlayer) then
        releaseAll()
    else
        legs(now)
    end
    cue(now)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- the screen effect sits under the HUD: drawn before GTA's HUD and every onClientRender overlay
    addEventHandler("onClientHUDRender", root, draw)
    setTimer(update, TICK_MS, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    releaseAll()
    freeScreen()
end)
