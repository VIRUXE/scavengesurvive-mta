-- Green-screen photo studio, client side: while the server has us in the studio, draw a closed chroma-green box
-- around the ped, hold the camera on the requested orbit, pin noon and clear weather so every shot has the same
-- light, light the ped with a key and a fill point light that follow the camera, and hide the hud (its dx draws
-- are not post-GUI, so takePlayerScreenShot would capture them). In model mode object models stand on the set
-- instead, lined up and centred where the ped was, with the camera presets scaled to their size.
local studio
do
    local f = fileOpen("shared/logic/studio.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    studio = assert(loadstring(src, "=dev/studio_logic.lua"))()
end

local STAGE = "postfx" -- after colour correction: the green reaches the screen exactly as given
local active = false
local cam = studio.parseCam({})
local C = studio.CENTRE -- the server always stands the ped here, so the box and orbit need no position sync
local vertices = {}
for i, v in ipairs(studio.box(C.x, C.y, C.z)) do
    vertices[i] = { v[1], v[2], v[3], studio.COLOUR }
end
local saved = {} -- weather, hour, minute, minuteDuration from before the studio
local lights = {}

-- model mode: objects on the set instead of the ped (which the server parks under the floor)
local props = {} -- { object, spec } in row order
local propRadius -- radius of the laid-out row; nil until every model's box is known
local propsSince = 0
local PROP_WAIT = 3000 -- a model that has not loaded by then is laid out as a 1 m cube
local modelsLib

local function clearProps()
    for _, p in ipairs(props) do
        if isElement(p.object) then
            destroyElement(p.object)
        end
    end
    props, propRadius = {}, nil
end

local function resolveModel(id)
    if not modelsLib then
        modelsLib = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
    end
    return modelsLib.resolve(id) or id -- a stock GTA model is its own id
end

local function setProps(list, dimension)
    clearProps()
    for _, spec in ipairs(list) do
        local object = createObject(resolveModel(spec.model), C.x, C.y, C.z, spec.rx, spec.ry, spec.rz)
        if object then
            setElementDimension(object, dimension)
            setElementCollisionsEnabled(object, false)
            props[#props + 1] = { object = object, spec = spec }
        end
    end
    propsSince = getTickCount()
end

-- lines the row up once every model's bounding box is known (they load over a few frames)
local function layoutProps()
    local bounds = {}
    local late = getTickCount() - propsSince > PROP_WAIT
    for i, p in ipairs(props) do
        local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(p.object)
        if not x1 then
            if not late then
                return
            end
            x1, y1, z1, x2, y2, z2 = -0.5, -0.5, -0.5, 0.5, 0.5, 0.5
        end
        bounds[i] = studio.turnedBounds(x1, y1, z1, x2, y2, z2, getElementMatrix(p.object))
    end
    local origins, radius = studio.layoutModels(bounds)
    for i, p in ipairs(props) do
        setElementPosition(p.object, C.x + origins[i][1], C.y + origins[i][2], C.z + origins[i][3])
    end
    propRadius = radius
end

local function setHudHidden(hidden)
    local hud = getResourceFromName("hud")
    if hud and getResourceState(hud) == "running" then
        exports.hud:setHidden(hidden)
    end
end

local function preRender()
    setTime(12, 0)
    setWeather(1)
    if #props > 0 and not propRadius then
        layoutProps()
    end
    if propRadius then
        setCameraMatrix(studio.cameraMatrix(C.x, C.y, C.z, studio.fitCam(cam, propRadius)))
    else
        setCameraMatrix(studio.cameraMatrix(C.x, C.y, C.z, cam.yaw, cam.dist, cam.height, cam.lookZ))
    end
    local dim = getElementDimension(localPlayer)
    for i, l in ipairs(studio.lights(C.x, C.y, C.z, cam.yaw)) do
        if not isElement(lights[i]) then
            lights[i] = createLight(0, l[1], l[2], l[3], l[4], l[5], l[6], l[7])
        end
        if lights[i] then
            setElementPosition(lights[i], l[1], l[2], l[3])
            if getElementDimension(lights[i]) ~= dim then
                setElementDimension(lights[i], dim)
            end
        end
    end
end

local function render()
    dxDrawPrimitive3D("trianglelist", STAGE, unpack(vertices))
end

local function start()
    if active then
        return
    end
    active = true
    saved.weather = getWeather()
    saved.hour, saved.minute = getTime()
    saved.minuteDuration = getMinuteDuration()
    saved.chat = isChatVisible()
    showChat(false) -- a window capture (tools outside MTA) would show it; takePlayerScreenShot never does
    setMinuteDuration(2 ^ 31 - 1)
    setHudHidden(true)
    addEventHandler("onClientPreRender", root, preRender)
    addEventHandler("onClientRender", root, render)
end

local function stop()
    if not active then
        return
    end
    active = false
    removeEventHandler("onClientPreRender", root, preRender)
    clearProps()
    removeEventHandler("onClientRender", root, render)
    for i, l in pairs(lights) do
        if isElement(l) then
            destroyElement(l)
        end
        lights[i] = nil
    end
    -- the world resource re-syncs the clock within a minute; this only avoids a minute of studio noon
    setMinuteDuration(saved.minuteDuration)
    setTime(saved.hour, saved.minute)
    setWeather(saved.weather)
    setCameraTarget(localPlayer)
    setHudHidden(false)
    showChat(saved.chat ~= false)
end

-- rz: the heading to face; the server sends it because only this client can set its own ped's rotation
addEventHandler("devStudioStateChanged", root, function(enabled, spec, rz)
    if spec then
        cam = spec
    end
    if enabled then
        start()
    else
        stop()
    end
    if rz then
        setElementRotation(localPlayer, 0, 0, rz)
    end
end)

addEventHandler("devStudioPoseChanged", root, function(rz)
    setElementRotation(localPlayer, 0, 0, rz)
end)

addEventHandler("devStudioCamChanged", root, function(spec)
    cam = spec
end)

-- list: studio.parseModels' result, empty to put the ped back on the set
addEventHandler("devStudioModelsChanged", root, function(list, dimension)
    setProps(list, dimension)
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)
