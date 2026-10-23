-- Green-screen photo studio, client side: while the server has us in the studio, draw a closed chroma-green box
-- around the ped, hold the camera on the requested orbit, pin noon and clear weather so every shot has the same
-- light, light the ped with a key and a fill point light that follow the camera, and hide the hud (its dx draws
-- are not post-GUI, so takePlayerScreenShot would capture them).
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

local function setHudHidden(hidden)
    local hud = getResourceFromName("hud")
    if hud and getResourceState(hud) == "running" then
        exports.hud:setHidden(hidden)
    end
end

local function preRender()
    setTime(12, 0)
    setWeather(1)
    setCameraMatrix(studio.cameraMatrix(C.x, C.y, C.z, cam.yaw, cam.dist, cam.height, cam.lookZ))
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

addEventHandler("onClientResourceStop", resourceRoot, stop)
