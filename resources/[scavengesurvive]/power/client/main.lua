-- Mains boxes on the client (shared/logic/mains.lua, data/sites.lua): every site's box and lever are this client's
-- objects (the lever turns on the box when the server's state says so), and a lit site lights its room: the world
-- resource's blackout shader lifts its cap inside the room (world:setRoomLight), the fittings' tubes glow
-- (client/tube.fx on ws_fluorescent2 inside the room only) and a point light under each fitting lights peds and
-- vehicles. The interaction chooser offers the lever at a box in reach.
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function loadFile(path, name)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, name))()
end

local mains = loadFile("shared/logic/mains.lua", "=power/mains.lua")
local sites = loadFile("data/sites.lua", "=power/sites.lua")
local byId = mains.index(sites)

local TUBE_TEXTURES = { "ws_fluorescent2" }
local LIGHT_COLOUR = { 0.86, 0.93, 1.0 } -- cool white fluorescent
local ROOM_FILL = 0.3 -- how much light the lit room adds over the building's own night colours
local PED_LIGHT_RADIUS = 9.0

local objects = {} -- site id -> { box, lever, angle, target, from, start, lights = { point lights } }
local state = {} -- site id -> { lever, lit } as the server last sent it
local tube -- the glowing tubes' shader

-- lib sounds out of GTA's collision bank (world client/buttons.lua does the same): a metal clunk for the lever
local function clunk(x, y, z)
    local s = playSFX3D("genrl", 32, 65, x, y, z, false)
    if s then
        setSoundMaxDistance(s, 30)
        setSoundVolume(s, 0.4)
        setSoundSpeed(s, 1.15)
    end
end

local function place(s)
    local o = { angle = 0, target = 0 }
    local b = s.box
    local boxModel, leverModel = models.resolve(mains.BOX_MODEL), models.resolve(mains.LEVER_MODEL)
    if boxModel then
        o.box = createObject(boxModel, b[1], b[2], b[3], 0, 0, b[4])
    end
    if o.box and leverModel then
        setElementInterior(o.box, s.interior or 0)
        setElementDimension(o.box, s.dimension or 0)
        setElementFrozen(o.box, true)
        local px, py, pz = mains.pivot(s)
        o.lever = createObject(leverModel, px, py, pz, 0, 0, b[4])
        setElementInterior(o.lever, s.interior or 0)
        setElementDimension(o.lever, s.dimension or 0)
        setElementCollisionsEnabled(o.lever, false)
        local p = mains.LEVER_PIVOT
        attachElements(o.lever, o.box, p[1], p[2], p[3], 0, 0, 0)
    end
    objects[s.id] = o
end

local function setLever(o, angle)
    o.angle = angle
    if isElement(o.lever) and isElement(o.box) then
        local p = mains.LEVER_PIVOT
        setElementAttachedOffsets(o.lever, p[1], p[2], p[3], 0, angle, 0)
    end
end

-- the lever swings to its new place over LEVER_MS
addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    for _, o in pairs(objects) do
        if o.start then
            local f = math.min(1, (now - o.start) / mains.LEVER_MS)
            setLever(o, o.from + (o.target - o.from) * f)
            if f >= 1 then
                o.start = nil
            end
        end
    end
end)

local function worldRunning()
    local res = getResourceFromName("world")
    return res and getResourceState(res) == "running"
end

local function lightOff(s, o)
    for _, l in ipairs(o.lights or {}) do
        if isElement(l) then
            destroyElement(l)
        end
    end
    o.lights = nil
    if worldRunning() then
        exports.world:removeRoomLight("mains:" .. s.id)
    end
end

local function tubeRooms()
    if not tube then
        return
    end
    local n = 0
    for _, s in ipairs(sites) do
        if state[s.id] and state[s.id].lit and n < 2 then
            local r = s.room
            dxSetShaderValue(tube, "Room" .. n .. "Min", r[1], r[2], r[3], 1)
            dxSetShaderValue(tube, "Room" .. n .. "Max", r[4], r[5], r[6], 1)
            n = n + 1
        end
    end
    for i = n, 1 do
        dxSetShaderValue(tube, "Room" .. i .. "Min", 0, 0, -10000, 0)
        dxSetShaderValue(tube, "Room" .. i .. "Max", 0, 0, -10000, 0)
    end
    -- on the tubes only while a room is lit: otherwise world's blackout shader keeps them as dark as the rest
    for _, t in ipairs(TUBE_TEXTURES) do
        if n > 0 then
            engineApplyShaderToWorldTexture(tube, t)
        else
            engineRemoveShaderFromWorldTexture(tube, t)
        end
    end
end

local function lightOn(s, o)
    lightOff(s, o)
    o.lights = {}
    for _, f in ipairs(s.fittings) do
        local l = createLight(0, f[1], f[2], f[3] - 0.6, PED_LIGHT_RADIUS, 220, 235, 255)
        if l then
            setElementInterior(l, s.interior or 0)
            setElementDimension(l, s.dimension or 0)
            o.lights[#o.lights + 1] = l
        end
    end
    if worldRunning() then
        local r, c = s.room, LIGHT_COLOUR
        exports.world:setRoomLight(
            "mains:" .. s.id,
            r[1],
            r[2],
            r[3],
            r[4],
            r[5],
            r[6],
            c[1],
            c[2],
            c[3],
            ROOM_FILL,
            s.interior or 0,
            s.dimension or 0
        )
    end
end

addEventHandler("mainsStateChanged", resourceRoot, function(states)
    for id, st in pairs(states) do
        local s, o = byId[id], objects[id]
        if s and o then
            local before = state[id]
            local target = st.lever and mains.LEVER_ON_ROTATION or 0
            if not before then
                o.target, o.start = target, nil
                setLever(o, target)
            elseif o.target ~= target then
                o.from, o.target, o.start = o.angle, target, getTickCount()
                local x, y, z = mains.pivot(s)
                clunk(x, y, z)
            end
            if st.lit and not (before and before.lit) then
                lightOn(s, o)
            elseif not st.lit and before and before.lit then
                lightOff(s, o)
            end
            state[id] = { lever = st.lever, lit = st.lit }
        end
    end
    tubeRooms()
end)

local function nearSite()
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then
        return nil
    end
    local x, y, z = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    return mains.siteAt(sites, x, y, z, int, dim, mains.REACH)
end

-- export (hud's interaction chooser): the lever of a box in reach
function interactionActions()
    local s = nearSite()
    if not s then
        return {}
    end
    local on = state[s.id] and state[s.id].lever
    return {
        {
            id = "mains:" .. s.id,
            label = on and lang.text("Switch the mains off") or lang.text("Switch the mains on"),
            event = "mainsLeverPulled",
            target = s.id,
            element = objects[s.id] and objects[s.id].box or nil,
        },
    }
end

-- export (items): the site whose inlet is within `reach` of the local player, its id and inlet x, y, z
function inletNear(reach)
    if isPedDead(localPlayer) or getPedOccupiedVehicle(localPlayer) then
        return false
    end
    local x, y, z = getElementPosition(localPlayer)
    local s = mains.siteAt(sites, x, y, z, getElementInterior(localPlayer), getElementDimension(localPlayer), reach)
    if not s then
        return false
    end
    local ix, iy, iz = mains.inlet(s)
    return s.id, ix, iy, iz
end

-- export (items): the sites lit now, site id -> true
function litSites()
    local out = {}
    for id, st in pairs(state) do
        out[id] = st.lit or nil
    end
    return out
end

-- export (items): a site's inlet, where a plugged cord's line ends, the floor points it runs through from outside,
-- the floor's height under the inlet and the room (x1, y1, z1, x2, y2, z2)
function inletOf(siteId)
    local s = byId[siteId]
    if not s then
        return false
    end
    local x, y, z = mains.inlet(s)
    return x, y, z, s.cordPath or {}, s.floor, s.room
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, s in ipairs(sites) do
        place(s)
    end
    tube = dxCreateShader("client/tube.fx", 1, 0, false, "world,object")
    if tube then
        tubeRooms()
    end
    triggerServerEvent("mainsStateRequested", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for id, o in pairs(objects) do
        if o.lights then
            lightOff(byId[id], o)
        end
    end
end)
