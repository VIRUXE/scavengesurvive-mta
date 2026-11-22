-- luacheck: read globals dxCreateScreenSource dxCreateShader dxSetShaderValue dxUpdateScreenSource
-- Hunger and thirst effects on the local player (shared/logic/hunger.lua): the screen shader (client/hunger.fx),
-- the sprint cap and the sprint/jump lock (wounds cap them too, the stricter wins: shared/logic/wounds.lua), and the
-- cues. The thirst sway and the aim sway go through the camera drunk
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
local wounds
do
    local f = fileOpen("shared/logic/wounds.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    wounds = assert(loadstring(src, "=character/wounds.lua"))()
end

local TICK_MS = 250
-- each cue plays one of its kind's sounds at random, never the one it played last (tools/make_thirst_sound.py)
local SOUNDS = {
    hunger = { "files/growl.ogg" },
    thirst = {
        "files/thirst_swallow1.wav",
        "files/thirst_swallow2.wav",
        "files/thirst_smack.wav",
        "files/thirst_throat.wav",
    },
}
local lastSound = {} -- kind -> index played last

local stats = { food = 100, thirst = 100, toxic = 0, drugs = {}, woundParts = {} }
local pose = false
-- fx is what the screen shows now (nil when clear), target what the needs ask for; draw() eases one to the other
local screenSource, shader, fx = nil, nil, nil
local target = { desat = 0, vignette = 0, blur = 0, tint = 0 }
local lastDraw = 0
local locked = {} -- control -> true: switched off here, so switched back on here
local sprintMs, coolUntil = 0, 0
local lastCue = 0

addEventHandler("characterStatsSynced", localPlayer, function(s)
    stats.food = tonumber(s.food) or stats.food
    stats.thirst = tonumber(s.thirst) or stats.thirst
    stats.toxic = tonumber(s.toxic) or 0
    stats.drugs = type(s.drugs) == "table" and s.drugs or {}
    stats.woundParts = type(s.woundParts) == "table" and s.woundParts or stats.woundParts
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
    local now = getTickCount()
    fx = hunger.ease(fx, target, now - lastDraw)
    lastDraw = now
    if not hunger.active(fx) then
        return freeScreen()
    end
    local sw, sh = guiGetScreenSize()
    if shader then
        dxSetShaderValue(shader, "Desat", fx.desat)
        dxSetShaderValue(shader, "Vignette", fx.vignette)
        dxSetShaderValue(shader, "Blur", fx.blur)
        dxSetShaderValue(shader, "Tint", fx.tint)
        dxUpdateScreenSource(screenSource)
        dxDrawImage(0, 0, sw, sh, shader)
    else
        -- no shader (old card or out of video memory): a plain darkening instead
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, math.floor(fx.vignette * 90)))
        dxDrawRectangle(0, 0, sw, sh, tocolor(120, 150, 30, math.floor(fx.tint * 60)))
    end
end

-- now = true: no fade (dead, on staff duty)
local function setScreen(next, now)
    target = next
    if now and not hunger.active(next) then
        if fx then
            freeScreen()
        end
        return
    end
    if not fx and hunger.active(next) then
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
        fx, lastDraw = { desat = 0, vignette = 0, blur = 0, tint = 0 }, getTickCount()
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
    local l =
        wounds.worstLegs(hunger.legs(stats.food, stats.thirst, stats.drugs), wounds.legs(stats.woundParts, stats.drugs))
    -- a mask is hard to breathe through, the better it protects the harder (items shared/logic/masks.lua)
    local items = getResourceFromName("items")
    local breath = items and getResourceState(items) == "running" and exports.items:maskLegs()
    if type(breath) == "table" then
        l = wounds.worstLegs(l, breath)
    end
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
    local list = SOUNDS[kind]
    local i = math.random(#list)
    if #list > 1 and i == lastSound[kind] then
        i = i % #list + 1
    end
    lastSound[kind] = i
    local s = playSound(list[i])
    if s then
        setSoundVolume(s, 0.7)
    end
end

local function update()
    if isPedDead(localPlayer) or getElementData(localPlayer, "staff.duty") == true then
        setScreen({ desat = 0, vignette = 0, blur = 0, tint = 0 }, true)
        releaseAll()
        return
    end
    local now = getTickCount()
    setScreen(hunger.screen(stats.food, stats.thirst, stats.drugs, stats.toxic))
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
