-- Dumpsters (shared/spots.lua): GTA's solid dump1 (model 1227) is taken out of the map at every spot and a hollow body
-- with bin bags inside takes its place, with the lid as an object of its own that swings open on its hinge while
-- somebody has the dumpster's container open (server/main.lua sends the open spots). Collision is a solid block on the
-- body, the lid has none.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()
local ldr = loader.new()

local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=dumpsters/" .. path))()
end
local logic = loadFile("shared/logic/dumpsters.lua")
local spots = loadFile("shared/spots.lua")

local NATIVE_MODEL, NATIVE_HALF_HEIGHT = 1227, 0.852
local state = {} -- spot -> { body, lid, x, y, z (hinge), h, angle, target }
local animating = {}

local function hinge(spot)
    local h = math.rad(spot[4])
    local back = logic.HALF_Y
    return spot[1] - math.sin(h) * back, spot[2] + math.cos(h) * back, spot[3] + logic.HEIGHT
end

local function setAngle(d, angle)
    d.angle = angle
    setElementRotation(d.lid, angle, 0, d.h)
end

local function build(bodyModel, lidModel)
    for i, s in ipairs(spots) do
        removeWorldModel(NATIVE_MODEL, 2.0, s[1], s[2], s[3] + NATIVE_HALF_HEIGHT)
        local body = createObject(bodyModel, s[1], s[2], s[3], 0, 0, s[4])
        local hx, hy, hz = hinge(s)
        local lid = createObject(lidModel, hx, hy, hz, 0, 0, s[4])
        if body and lid then
            setElementCollisionsEnabled(lid, false)
            state[i] = { body = body, lid = lid, h = s[4], angle = 0, target = 0 }
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local bodyModel, e1 = ldr.loadModel({ dff = "dumpster_body", txd = "dumpster_body", dist = 150 })
    local lidModel, e2 = ldr.loadModel({ dff = "dumpster_lid", txd = "dumpster_lid", dist = 150 })
    if not bodyModel or not lidModel then
        return outputDebugString("dumpsters: models not loaded: " .. tostring(e1 or e2), 1)
    end
    build(bodyModel, lidModel)
    triggerServerEvent("dumpsterLidsRequested", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, s in ipairs(spots) do
        restoreWorldModel(NATIVE_MODEL, 2.0, s[1], s[2], s[3] + NATIVE_HALF_HEIGHT)
    end
    ldr.freeAll()
end)

addEventHandler("dumpsterLidsChanged", resourceRoot, function(open)
    local want = {}
    for _, i in ipairs(open) do
        want[i] = true
    end
    for i, d in pairs(state) do
        local target = want[i] and logic.LID_OPEN_PITCH or 0
        if d.target ~= target then
            d.target = target
            d.from, d.t0 = d.angle, getTickCount()
            animating[i] = true
        end
    end
end)

-- swing: ease in and out over LID_MS, a small bounce at the end of the opening
addEventHandler("onClientRender", root, function()
    if next(animating) == nil then
        return
    end
    local now = getTickCount()
    for i in pairs(animating) do
        local d = state[i]
        local k = math.min((now - d.t0) / logic.LID_MS, 1)
        local e = k * k * (3 - 2 * k)
        setAngle(d, d.from + (d.target - d.from) * e)
        if k >= 1 then
            animating[i] = nil
        end
    end
end)

-- hud: "dumpster" while one is in reach on foot, else false
function nearbyDumpster()
    if isPedInVehicle(localPlayer) then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    return logic.nearest(spots, px, py, pz, logic.OPEN_REACH) and "dumpster" or false
end

-- hud's interact key: true when a dumpster took the press
function tryOpenDumpster()
    if isPedInVehicle(localPlayer) then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    local i = logic.nearest(spots, px, py, pz, logic.OPEN_REACH)
    if not i then
        return false
    end
    triggerServerEvent("dumpsterOpenRequested", localPlayer, i)
    return true
end
