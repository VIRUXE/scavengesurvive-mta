-- Buttons, doors, the puzzles and Area 69 on the client (shared/logic/buttons.lua, doors.lua, puzzles.lua,
-- area69.lua). Every client builds the same registry, places the doors and the puzzles' objects, and moves its own
-- copies when the server's state (buttonsStateChanged) says so. hud's interact key reaches buttonInteract() through
-- features.lua's tryInteract().
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local buttons = loadFile("shared/logic/buttons.lua", "=world/buttons.lua")
local doors = loadFile("shared/logic/doors.lua", "=world/doors.lua")
local puzzles = loadFile("shared/logic/puzzles.lua", "=world/puzzles.lua")
local area69 = loadFile("shared/logic/area69.lua", "=world/area69.lua")
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local standins = loadstring(exports.lib:getModule("standins"), "=lib/standins.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local reg = buttons.new()
doors.register(reg, buttons)
puzzles.register(reg, buttons)
area69.register(reg, buttons)
local pstate = puzzles.newState()
local shown = nil -- door id -> state the object is drawn at; nil until the server's first state arrives
local doorObjects, keypad, screen = {}, nil, nil
local viewing = false

-- a SA-MP model through samp_models (keypad, screen, spark), a stock one as it is
local function model(id)
    if id >= 18631 or (id >= 11682 and id <= 11753) then
        return models.resolve(id) or false
    end
    return id
end

local function place(m, p, world)
    local id = model(m)
    local obj = id and createObject(id, p[1], p[2], p[3], p[4], p[5], p[6])
    if obj then
        setElementDimension(obj, world and world > 0 and world or 0)
        setElementFrozen(obj, true)
    end
    return obj
end

local function drawPose(obj, p)
    if isElement(obj) then
        stopObject(obj)
        setElementPosition(obj, p[1], p[2], p[3])
        setElementRotation(obj, p[4], p[5], p[6])
    end
end

-- moveObject turns by offsets: the rotation the door turns from where it is drawn to where it goes
local function moveDoor(id, to)
    local d, obj = reg.doors[id], doorObjects[id]
    if not isElement(obj) then
        return
    end
    local from, target = buttons.pose(d, shown[id]), buttons.pose(d, to)
    drawPose(obj, from)
    local drx, dry, drz = target[4] - from[4], target[5] - from[5], target[6] - from[6]
    moveObject(obj, buttons.doorMs(d), target[1], target[2], target[3], drx, dry, drz)
end

-- the ranch PC's screen: upstream SetDynamicObjectMaterialText(RanchPcObj, ...) once the hard drive is in
local screenTarget, screenShader = nil, nil
local function drawScreen()
    if not screenTarget then
        return
    end
    dxSetRenderTarget(screenTarget, true)
    dxDrawText(
        puzzles.screenText(lang.text),
        8,
        8,
        504,
        504,
        tocolor(255, 255, 255),
        1.0,
        "default-bold",
        "left",
        "top"
    )
    dxSetRenderTarget()
end

local function showScreen()
    if screenShader or not isElement(screen) then
        return
    end
    screenTarget = dxCreateRenderTarget(512, 512, true)
    screenShader = screenTarget and dxCreateShader("client/screen.fx")
    if not screenShader then
        return
    end
    dxSetShaderValue(screenShader, "Tex", screenTarget)
    engineApplyShaderToWorldTexture(screenShader, "*", screen)
    drawScreen()
end
addEventHandler("onClientRestore", root, drawScreen)

addEventHandler("buttonsStateChanged", resourceRoot, function(states, puzzleState)
    local first = shown == nil
    shown = shown or {}
    for _, id in ipairs(reg.doorIds) do
        local to = states[id] or "closed"
        if first then
            drawPose(doorObjects[id], buttons.pose(reg.doors[id], to))
        elseif shown[id] ~= to then
            moveDoor(id, to)
        end
        shown[id] = to
        reg.states[id] = to
    end
    if first and puzzleState.shorted then
        drawPose(keypad, puzzles.KEYPAD.broken)
    end
    pstate = puzzleState
    if pstate.pcOn then
        showScreen()
    end
end)

-- mtchill.pwn: the battery shorts the keypad: a spark for 2 s, and 0.4 s in the keypad drops off its mount
addEventHandler("puzzleKeypadSparked", resourceRoot, function()
    local spark = place(puzzles.SPARK.model, puzzles.SPARK.pos, 0)
    if spark then
        setTimer(destroyElement, puzzles.SPARK_MS, 1, spark)
    end
    setTimer(function()
        if isElement(keypad) then
            local from, to = puzzles.KEYPAD.pos, puzzles.KEYPAD.broken
            local ms = math.max(100, math.floor(math.abs(from[3] - to[3]) / puzzles.KEYPAD.speed * 1000))
            moveObject(keypad, ms, to[1], to[2], to[3], to[4] - from[4], to[5] - from[5], to[6] - from[6])
        end
    end, puzzles.KEYPAD_FALL_DELAY_MS, 1)
end)

-- a hack that failed at an Area 69 keypad (upstream kp_HackFailParticle: the spark at the player's feet for 2 s)
addEventHandler("puzzleSparkShown", resourceRoot, function(x, y, z)
    local spark = place(puzzles.SPARK.model, { x, y, z, 0, 0, 0 }, getElementDimension(localPlayer))
    if spark then
        setTimer(destroyElement, puzzles.SPARK_MS, 1, spark)
    end
end)

-- the server sends puzzles.SAY's English texts (and area69's code list); they are shown in the player's language
addEventHandler("buttonMessageShown", localPlayer, function(title, body)
    local L = lang.text
    exports.ui:dialogOpen("world:button", "msgbox", L(title), L(body), L("Close"), "")
end)

-- ranch.pwn: a press on the working PC looks at its screen, the next one gives the camera back
addEventHandler("buttonViewToggled", localPlayer, function()
    viewing = not viewing
    if viewing then
        local v = puzzles.VIEW
        setCameraMatrix(v[1], v[2], v[3], v[4], v[5], v[6])
        toggleAllControls(false, true, false)
    else
        setCameraTarget(localPlayer)
        toggleAllControls(true, true, false)
    end
end)

-- a puzzle's button that is gone, and an Area 69 door button whose doors are all open (nothing left to do there)
local function hidden(b)
    if b.owner == "area69" then
        return area69.allOpen(reg, b.keypad)
    end
    return b.owner == "puzzles" and puzzles.hidden(pstate, b)
end

-- upstream items are buttons too and the nearest one wins: a world item closer than the button (the ranch's hard
-- drive by its PC) is left to the items resource's pickup
local function itemCloser(d)
    local itemD = exports.items:nearestItemDistance()
    return itemD ~= false and itemD < d
end

local function near()
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then
        return nil
    end
    local x, y, z = getElementPosition(localPlayer)
    local b, d = buttons.buttonAt(reg, x, y, z, getElementDimension(localPlayer), hidden)
    if b and itemCloser(d) then
        return nil
    end
    return b
end

-- features.lua: the interact key's first stop after ladders and ziplines
function buttonInteract()
    local b = viewing and reg.byId.ranchPc or near()
    if not b then
        return false
    end
    triggerServerEvent("buttonPressed", localPlayer, b.id)
    return true
end

-- Doors hauled on a chain (doors.lua M.HAULED): holding the engine-bay key (E) at one asks the server to haul it,
-- letting go stops it; the server moves every client's copy (doorHaulMoved). Sounds out of GTA's collision sounds
-- (genrl bank 32, its GENRL_COLLISIONS): the chain rattling at each pull (the wire-fence rattles), the door scraping
-- on its runners while it moves (the metal scrape loop) and a solid metal clunk as it comes to rest at either end.
local COLLISIONS, SCRAPE, CLUNK = 32, 2, 65
local RATTLES = { 69, 70, 71 }
local HAUL_MS = 560 -- one pull of the hand chain (CASINO slot_plyr's stroke)
local hauledById, hauledObjects, hauledSounds = {}, {}, {}
local haulingId = nil -- the door this client holds the chain of
for _, d in ipairs(doors.HAULED) do
    hauledById[d.id] = d
end

local function sfx(sound, x, y, z, volume, speed, looped)
    local s = playSFX3D("genrl", COLLISIONS, sound, x, y, z, looped or false)
    if s then
        setSoundMaxDistance(s, 50)
        setSoundVolume(s, volume)
        setSoundSpeed(s, speed)
    end
    return s
end

local function stopHauledSound(id)
    local playing = hauledSounds[id]
    hauledSounds[id] = nil
    if playing then
        if isElement(playing.scrape) then
            stopSound(playing.scrape)
        end
        if isTimer(playing.rattle) then
            killTimer(playing.rattle)
        end
    end
end

local function hauledSound(id, kind)
    local d, obj = hauledById[id], hauledObjects[id]
    stopHauledSound(id)
    local x, y, z = getElementPosition(obj)
    local fast = kind == "fall"
    local scrape = sfx(SCRAPE, x, y, z, fast and 0.16 or 0.1, fast and 1.1 or 0.6, true)
    if scrape then
        attachElements(scrape, obj)
    end
    local rattle
    if not fast then
        local c = d.chain
        local function pull()
            sfx(RATTLES[math.random(#RATTLES)], c[1], c[2], c[3], 0.2, 0.9 + math.random() * 0.2)
        end
        pull()
        rattle = setTimer(pull, HAUL_MS, 0)
    end
    hauledSounds[id] = { scrape = scrape, rattle = rattle }
end

addEventHandler("doorHaulMoved", resourceRoot, function(id, t0, t1, ms, kind)
    local d, obj = hauledById[id], hauledObjects[id]
    if not d or not isElement(obj) then
        return
    end
    local wasMoving = hauledSounds[id] ~= nil
    stopHauledSound(id)
    local from, to = doors.hauledPose(d, t0), doors.hauledPose(d, t1)
    drawPose(obj, from)
    if ms > 0 and t0 ~= t1 then
        moveObject(obj, ms, to[1], to[2], to[3], to[4] - from[4], to[5] - from[5], to[6] - from[6])
        hauledSound(id, kind)
    elseif wasMoving and (t1 <= 0.001 or t1 >= 0.999) then
        local x, y, z = getElementPosition(obj)
        sfx(CLUNK, x, y, z, t1 <= 0.001 and 0.35 or 0.28, 0.85)
    end
end)

-- the hauled door whose chain is in reach, or nil
local function hauledNear()
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) or getElementDimension(localPlayer) ~= 0 then
        return nil
    end
    local x, y, z = getElementPosition(localPlayer)
    for _, d in ipairs(doors.HAULED) do
        local r = d.reach
        if getDistanceBetweenPoints3D(x, y, z, r[1], r[2], r[3]) <= doors.HAUL_REACH then
            return d
        end
    end
    return nil
end

local function haulKey(key)
    local bound = getKeyBoundToCommand("enginebay")
    return key == string.lower(bound or "e")
end

addEventHandler("onClientKey", root, function(key, press)
    if not haulKey(key) then
        return
    end
    if press then
        local d = not haulingId and not isCursorShowing() and not isMTAWindowActive() and hauledNear()
        if d then
            haulingId = d.id
            triggerServerEvent("doorHaulStarted", localPlayer, d.id)
        end
    elseif haulingId then
        haulingId = nil
        triggerServerEvent("doorHaulStopped", localPlayer)
    end
end)

-- features.lua nearbyFeature(): "button:<label>" for hud's F line
function buttonNear()
    local b = near()
    if b then
        return "button:" .. b[5]
    end
    local d = hauledNear()
    return d and ("hold:" .. d.label) or nil
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- the puzzles' static objects are the server's (server/main.lua): swap in this client's SA-MP models
    standins.track(resourceRoot)
    for _, list in ipairs({ doors.PROPS, puzzles.PROPS }) do
        for _, p in ipairs(list) do
            place(p[1], { p[2], p[3], p[4], p[5], p[6], p[7] }, p[8])
        end
    end
    for _, r in ipairs(doors.REMOVALS) do
        removeWorldModel(r[1], r[2], r[3], r[4], r[5])
    end
    for _, id in ipairs(reg.doorIds) do
        local d = reg.doors[id]
        doorObjects[id] = place(d.model, d.closed, d.world)
    end
    for _, d in ipairs(doors.HAULED) do
        hauledObjects[d.id] = place(d.model, d.closed, d.world)
    end
    triggerServerEvent("doorHaulStateRequested", localPlayer)
    keypad = place(puzzles.KEYPAD.model, puzzles.KEYPAD.pos, 0)
    screen = place(puzzles.SCREEN.model, puzzles.SCREEN.pos, 0)
    triggerServerEvent("buttonsStateRequested", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for id in pairs(hauledById) do
        stopHauledSound(id)
    end
    for _, r in ipairs(doors.REMOVALS) do
        restoreWorldModel(r[1], r[2], r[3], r[4], r[5])
    end
    if viewing then
        setCameraTarget(localPlayer)
        toggleAllControls(true, true, false)
    end
end)

-- The shared chooser lists a reachable button alongside world items, without the legacy item priority.
function buttonInteractionActions()
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then
        return {}
    end
    local x, y, z = getElementPosition(localPlayer)
    local b = buttons.buttonAt(reg, x, y, z, getElementDimension(localPlayer), hidden)
    if not b then
        return {}
    end
    return { { id = "button:" .. b.id, label = lang.text(b[5]), event = "buttonPressed", target = b.id } }
end
