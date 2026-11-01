-- Client side of carmour (shared/logic/carmour.lua, server/carmour.lua): each streamed-in vehicle with armour carries
-- its welded panels as objects attached at the slot's fixed placement (shared/data/carmour_slots.lua). The panel on
-- the door slot swings with the door: a vehicle door cannot carry an attached object, so its offsets are turned about
-- the hinge by the door's open ratio every frame. Sparks fly while a player welds, and an armoured vehicle takes no
-- damage here (the server also holds it damage proof).
local carmour, slotData
do
    local f = fileOpen("shared/logic/carmour.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    carmour = assert(loadstring(src, "=vehicles/carmour.lua"))()
    f = fileOpen("shared/data/carmour_slots.lua", true)
    src = fileRead(f, fileGetSize(f))
    fileClose(f)
    slotData = assert(loadstring(src, "=vehicles/carmour_slots.lua"))()
end
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()

local WALK_IN_DOOR = 2 -- the vehicle's front-left door
local FALLBACK_MODEL = 1271
local panels = {} -- vehicle -> { [slot] = { obj, u } }
local swung = {} -- vehicle -> the door ratio its door panel was last placed for

local function modelFor(uname)
    local t = exports.data:itemType(uname)
    local id = t and t.model or FALLBACK_MODEL
    if t and t.sampOnly then
        return models.resolve(id) or t.mtaModel or FALLBACK_MODEL
    end
    return id
end

local function clear(vehicle)
    for _, p in pairs(panels[vehicle] or {}) do
        if isElement(p.obj) then
            destroyElement(p.obj)
        end
    end
    panels[vehicle] = nil
    swung[vehicle] = nil
end

-- the placement turned about the door's hinge by the open ratio (the door slot only)
local function swungPlacement(pl, ratio)
    local door = slotData.DOOR
    local deg = door.openDeg * (door.dir or 1) * ratio
    local a = math.rad(deg)
    local dx, dy = pl.x - door.hinge.x, pl.y - door.hinge.y
    local x = door.hinge.x + dx * math.cos(a) - dy * math.sin(a)
    local y = door.hinge.y + dx * math.sin(a) + dy * math.cos(a)
    return x, y, pl.z, pl.rx, pl.ry, pl.rz + deg
end

local function place(vehicle, slot, def, p)
    local pl = def.byPanel[p.u]
    if not pl then
        return
    end
    local obj = createObject(modelFor(p.u), 0, 0, 0)
    if not obj then
        return
    end
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    if pl.scale and pl.scale ~= 1 then
        setObjectScale(obj, pl.scale)
    end
    attachElements(obj, vehicle, pl.x, pl.y, pl.z, pl.rx, pl.ry, pl.rz)
    panels[vehicle][slot] = { obj = obj, u = p.u, def = def }
    swung[vehicle] = nil
end

-- the vehicle's panels match its element data
local function sync(vehicle)
    local data = getElementData(vehicle, "vehicles.carmour")
    local defs = slotData.SLOTS[getElementModel(vehicle)]
    if type(data) ~= "table" or not defs then
        return clear(vehicle)
    end
    local st = carmour.decode(data)
    panels[vehicle] = panels[vehicle] or {}
    for slot, have in pairs(panels[vehicle]) do
        local want = st.slots[slot]
        if not want or want.u ~= have.u then
            if isElement(have.obj) then
                destroyElement(have.obj)
            end
            panels[vehicle][slot] = nil
        end
    end
    for slot, p in pairs(st.slots) do
        if defs[slot] and not panels[vehicle][slot] then
            place(vehicle, slot, defs[slot], p)
        end
    end
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        sync(source)
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if panels[source] then
        clear(source)
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if panels[source] then
        clear(source)
    end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "vehicles.carmour" and getElementType(source) == "vehicle" and isElementStreamedIn(source) then
        sync(source)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        sync(vehicle)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for vehicle in pairs(panels) do
        clear(vehicle)
    end
end)

-- The vehicle a Welder in hand works on (hud F key and its hint): the nearest streamed-in one that takes armour,
-- within the server's reach of it; false when none is.
local WELD_REACH = 6.5

function nearbyWeldTarget()
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestDist = false, WELD_REACH
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(veh, "vehicles.carmour") then
            local vx, vy, vz = getElementPosition(veh)
            local d = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
            if d <= bestDist then
                best, bestDist = veh, d
            end
        end
    end
    return best
end

-- the door's panel follows the door
addEventHandler("onClientPreRender", root, function()
    for vehicle, slots in pairs(panels) do
        if isElement(vehicle) then
            local ratio = getVehicleDoorOpenRatio(vehicle, WALK_IN_DOOR)
            if swung[vehicle] ~= ratio then
                swung[vehicle] = ratio
                for _, p in pairs(slots) do
                    if p.def.door and isElement(p.obj) then
                        local x, y, z, rx, ry, rz = swungPlacement(p.def.byPanel[p.u], ratio)
                        setElementAttachedOffsets(p.obj, x, y, z, rx, ry, rz)
                    end
                end
            end
        end
    end
end)

-- an armoured vehicle takes no damage (the server also holds it damage proof)
addEventHandler("onClientVehicleDamage", root, function()
    local data = getElementData(source, "vehicles.carmour")
    if type(data) == "table" and carmour.panelCount(carmour.decode(data)) > 0 then
        cancelEvent()
    end
end)

-- sparks at the welder's torch while the hold lasts
addEventHandler("weldStarted", root, function(ms)
    local who = source
    local started = getTickCount()
    setTimer(function()
        if not isElement(who) or getTickCount() - started > ms then
            return
        end
        local x, y, z = getElementPosition(who)
        local cx, cy, cz = getCameraMatrix()
        if getDistanceBetweenPoints3D(x, y, z, cx, cy, cz) > 80 then
            return
        end
        local _, _, rz = getElementRotation(who)
        local a = math.rad(rz)
        fxAddSparks(x - math.sin(a) * 0.7, y + math.cos(a) * 0.7, z - 0.2, 0, 0, 1, 2, 6, 0, 0, 0, true, 3, 1)
    end, 120, math.ceil(ms / 120))
end)

-- The door's hitpoints as a built defence's label (items/client/world.lua): its name, then hitpoints/maximum, in
-- yellow with a shadow, from LABEL_RANGE metres while nothing but the vehicle itself stands between it and the camera.
local LABEL_RANGE = 10
local labelSeen = {} -- vehicle -> { visible, checkedAt }

local function doorLabel(vehicle)
    local data = getElementData(vehicle, "vehicles.carmour")
    if type(data) ~= "table" then
        return nil
    end
    local st = carmour.decode(data)
    local max = carmour.DOOR_BASE_HP
    for _, p in pairs(st.slots) do
        local t = exports.data:itemType(p.u)
        max = max + (t and t.maxHitpoints or p.hp)
    end
    local hp = carmour.doorHp(st)
    return string.format("Door\n%d/%d", hp, math.max(max, hp))
end

-- a vehicle-local point turned into the world
local function worldPoint(vehicle, ox, oy, oz)
    local m = getElementMatrix(vehicle)
    local x = ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1]
    local y = ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2]
    local z = ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
    return x, y, z
end

addEventHandler("onClientRender", root, function()
    local px, py, pz = getElementPosition(localPlayer)
    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()
    local _, sh = guiGetScreenSize()
    for vehicle in pairs(panels) do
        local defs = isElement(vehicle) and slotData.SLOTS[getElementModel(vehicle)]
        local text = defs and doorLabel(vehicle)
        if text then
            local door = defs[1].byPanel.MetPanel
            local x, y, z = worldPoint(vehicle, door.x, door.y, door.z)
            local dx, dy, dz = x - px, y - py, z - pz
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 < LABEL_RANGE * LABEL_RANGE then
                local seen = labelSeen[vehicle]
                if not seen or now - seen.checkedAt >= 300 then
                    local los =
                        isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, false, true, false, false, vehicle)
                    seen = { visible = los, checkedAt = now }
                    labelSeen[vehicle] = seen
                end
                local sx, sy = getScreenFromWorldPosition(x, y, z, 0, false)
                if seen.visible and sx then
                    local scale = (sh / 1080) * (d2 < 9 and 1.1 or 0.9)
                    local shadow, yellow = tocolor(0, 0, 0, 200), tocolor(255, 255, 0, 230)
                    local sx1, sy1 = sx + 1, sy + 1
                    dxDrawText(text, sx1, sy1, sx1, sy1, shadow, scale, "default-bold", "center", "center")
                    dxDrawText(text, sx, sy, sx, sy, yellow, scale, "default-bold", "center", "center")
                end
            end
        end
    end
end)
