-- Client side of carmour (shared/logic/carmour.lua, shared/logic/carmour_place.lua, server/carmour.lua).
-- - Every streamed-in vehicle with armour carries its panels as objects attached where they were placed, full size
--   (a door defence stretched over the door leaf, swinging with it: a vehicle door cannot carry an attached object,
--   so its offsets are turned about the hinge by the door's open ratio every frame). An armoured vehicle takes no
--   damage here (the server also holds it damage proof).
-- - Attach mode (hud F with a defence in hand at the trailer): a ghost of the defence lies where the camera looks,
--   placed by the same rules as the server; F attaches it there, N or walking away cancels.
-- - The Welder's torch: one rides in the holster of every Welder on the ground or carried; a player who grabbed one
--   ("vehicles.torch" element data) holds it in the right hand, its lead drawn back to the Welder's socket.
local carmour, place, geo
do
    local function load(path, name)
        local f = fileOpen(path, true)
        local src = fileRead(f, fileGetSize(f))
        fileClose(f)
        return assert(loadstring(src, name))()
    end
    carmour = load("shared/logic/carmour.lua", "=vehicles/carmour.lua")
    place = load("shared/logic/carmour_place.lua", "=vehicles/carmour_place.lua")
    geo = place.load(load("shared/data/carmour_geometry.lua", "=vehicles/carmour_geometry.lua"))
end
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()

local WALK_IN_DOOR = 2 -- the vehicle's front-left door
local FALLBACK_MODEL = 1271
local TORCH_MODEL = 20205 -- prop_models welder_torch: origin in the grip, nozzle +Y
local WELDER_SOCKET = { -0.1, 0.195, 0.08 } -- the lead's plug on the Welder (welder model space, make_props)
local TORCH_LEAD = { 0, -0.155, 0 } -- where the lead leaves the torch (torch model space)
local TORCH_STOWED = { -0.27, -0.07, 0.18, -90, 0, 0 } -- the torch in the Welder's holster
local WELDER_INLET = { 0.1, -0.13, 0.12 } -- where the gas hose goes into the Welder (its back, model space)
local TORCH_HAND = { 0.04, 0.02, -0.02, 0, 90, 180 } -- the torch in the right hand (GTA bone 24), x y z rx ry rz
local HAND_BONE = 24
local ATTACH_LEAVE = 7.0 -- attach mode ends this far from the vehicle
local PLACE_MS = 50 -- the ghost is placed again this often

local panels = {} -- vehicle -> { [panel id] = { obj, rec, a } }
local swung = {} -- vehicle -> the door ratio its door panels were last placed for

local function modelFor(uname)
    local t = exports.data:itemType(uname)
    local id = t and t.model or FALLBACK_MODEL
    if t and t.sampOnly then
        return models.resolve(id) or t.mtaModel or FALLBACK_MODEL
    end
    return models.resolve(id) or id
end

local function stateOf(vehicle)
    local data = getElementData(vehicle, "vehicles.carmour")
    if type(data) ~= "table" then
        return nil
    end
    return carmour.decode(data, geo.panels)
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

-- an attach placement turned about the door's hinge by the open ratio (door panels only)
local function swungOffsets(a, ratio)
    local door = geo.door
    local deg = door.openDeg * (door.dir or 1) * ratio
    local r = math.rad(deg)
    local dx, dy = a.x - door.hinge.x, a.y - door.hinge.y
    local x = door.hinge.x + dx * math.cos(r) - dy * math.sin(r)
    local y = door.hinge.y + dx * math.sin(r) + dy * math.cos(r)
    return x, y, a.z, a.rx, a.ry, a.rz + deg
end

local function panelObject(vehicle, rec, alpha)
    rec = place.effective(geo, rec)
    local frame = geo.panels[rec.u]
    local obj = frame and createObject(modelFor(rec.u), 0, 0, 0)
    if not obj then
        return nil
    end
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    local a = place.attachOf(rec, frame)
    if a.sx ~= 1 or a.sy ~= 1 or a.sz ~= 1 then
        -- MTA draws a non-uniform scale with any axis at exactly 1 at full size: keep those a hair under
        local function axis(v)
            return v == 1 and 0.9999 or v
        end
        setObjectScale(obj, axis(a.sx), axis(a.sy), axis(a.sz))
    end
    attachElements(obj, vehicle, a.x, a.y, a.z, a.rx, a.ry, a.rz)
    if alpha then
        setElementAlpha(obj, alpha)
    end
    return obj, a
end

-- the vehicle's panels match its element data
local function sync(vehicle)
    local st = stateOf(vehicle)
    if not st or getElementModel(vehicle) ~= geo.model then
        return clear(vehicle)
    end
    local want = {}
    for _, rec in ipairs(st.panels) do
        want[rec.id] = rec
    end
    panels[vehicle] = panels[vehicle] or {}
    for id, have in pairs(panels[vehicle]) do
        if not want[id] then
            if isElement(have.obj) then
                destroyElement(have.obj)
            end
            panels[vehicle][id] = nil
        else
            have.rec = want[id] -- welded or not: the same object
        end
    end
    for id, rec in pairs(want) do
        if not panels[vehicle][id] then
            local obj, a = panelObject(vehicle, rec)
            if obj then
                panels[vehicle][id] = { obj = obj, rec = rec, a = a }
            end
        end
    end
    swung[vehicle] = nil
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

-- the door's panel follows the door
addEventHandler("onClientPreRender", root, function()
    for vehicle, list in pairs(panels) do
        if isElement(vehicle) then
            local ratio = getVehicleDoorOpenRatio(vehicle, WALK_IN_DOOR)
            if swung[vehicle] ~= ratio then
                swung[vehicle] = ratio
                for _, p in pairs(list) do
                    if p.rec.door and isElement(p.obj) then
                        local x, y, z, rx, ry, rz = swungOffsets(p.a, ratio)
                        setElementAttachedOffsets(p.obj, x, y, z, rx, ry, rz)
                    end
                end
            end
        end
    end
end)

-- an armoured vehicle (a panel welded on) takes no damage (the server also holds it damage proof)
addEventHandler("onClientVehicleDamage", root, function()
    local st = stateOf(source)
    if st and carmour.weldedCount(st) > 0 then
        cancelEvent()
    end
end)

-- sparks at the torch while the hold lasts
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

-- sparks thrown back off the Grinder's disc while a pass lasts
addEventHandler("grindStarted", root, function(ms)
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
        local fx, fy = -math.sin(a), math.cos(a)
        fxAddSparks(x + fx * 0.6, y + fy * 0.6, z - 0.1, -fx, -fy, 0.6, 1.5, 10, 0, 0, 0, true, 2, 1)
    end, 90, math.ceil(ms / 90))
end)

-- The vehicle a Welder's torch or a held defence works on (hud F key and its hints): the nearest streamed-in one
-- that takes armour, within the server's reach of it; false when none is.
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

-- the door's hitpoints as a built defence's label (items/client/world.lua) ------------------------------------
local LABEL_RANGE = 10
local labelSeen = {} -- vehicle -> { visible, checkedAt }

local function doorLabel(vehicle)
    local st = stateOf(vehicle)
    if not st then
        return nil
    end
    local max = carmour.DOOR_BASE_HP
    for _, p in ipairs(st.panels) do
        if p.w then
            local t = exports.data:itemType(p.u)
            max = max + (t and t.maxHitpoints or p.hp)
        end
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

-- a world point in the vehicle's frame
local function localPoint(vehicle, x, y, z)
    local m = getElementMatrix(vehicle)
    local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
    return {
        dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
        dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
        dx * m[3][1] + dy * m[3][2] + dz * m[3][3],
    }
end

local function localDir(vehicle, x, y, z)
    local m = getElementMatrix(vehicle)
    return {
        x * m[1][1] + y * m[1][2] + z * m[1][3],
        x * m[2][1] + y * m[2][2] + z * m[2][3],
        x * m[3][1] + y * m[3][2] + z * m[3][3],
    }
end

local function drawLabel(text, x, y, z, d2)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0, false)
    if not sx then
        return
    end
    local _, sh = guiGetScreenSize()
    local scale = (sh / 1080) * (d2 < 9 and 1.1 or 0.9)
    local shadow, yellow = tocolor(0, 0, 0, 200), tocolor(255, 255, 0, 230)
    local sx1, sy1 = sx + 1, sy + 1
    dxDrawText(text, sx1, sy1, sx1, sy1, shadow, scale, "default-bold", "center", "center")
    dxDrawText(text, sx, sy, sx, sy, yellow, scale, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    local px, py, pz = getElementPosition(localPlayer)
    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()
    local f = geo.door.face
    for vehicle in pairs(panels) do
        local text = isElement(vehicle) and doorLabel(vehicle)
        -- only from the door's side: the line of sight ignores the vehicle, so it would show through the trailer
        if text and localPoint(vehicle, cx, cy, cz)[1] > f.x then
            text = nil
        end
        if text then
            local x, y, z = worldPoint(vehicle, f.x - 0.1, (f.y0 + f.y1) / 2, (f.z0 + f.z1) / 2)
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
                if seen.visible then
                    drawLabel(text, x, y, z, d2)
                end
            end
        end
    end
end)

-- Attach mode ------------------------------------------------------------------------------------------------

local REASONS = {
    MISS = "Aim at the trailer",
    DOOR_ONLY = "A door only goes on the trailer's door",
    NOT_DOOR = "Only a door goes on the door",
    UNSUPPORTED = "It would hang off the trailer here",
    BLOCKS_DOOR = "It would block the door",
    CLASH = "It would hit another defence",
}

local attaching = nil -- { vehicle, uname, ghost, rec, why, o, d, placedAt }

-- a defence type that goes onto a vehicle
function isAttachable(uname)
    return type(uname) == "string" and geo.panels[uname] ~= nil
end

function attachModeActive()
    return attaching ~= nil
end

-- the defence in hand is hidden while its ghost is aimed (a full-size panel carried blocks the view)
local function showHeld(visible)
    local obj = exports.items:heldObjectOf(localPlayer)
    if obj then
        setElementAlpha(obj, visible and 255 or 0)
    end
end

function cancelAttach()
    if attaching and isElement(attaching.ghost) then
        destroyElement(attaching.ghost)
    end
    if attaching then
        showHeld(true)
    end
    attaching = nil
end

local function heldUname()
    local held = getElementData(localPlayer, "items.held") -- the held item's uname (items/server/hands.lua)
    return type(held) == "string" and held or nil
end

function beginAttach(vehicle)
    local uname = heldUname()
    if not isElement(vehicle) or not isAttachable(uname) then
        return false
    end
    cancelAttach()
    attaching = { vehicle = vehicle, uname = uname, placedAt = 0 }
    showHeld(false)
    return true
end

-- F in attach mode: the server places the defence from the same ray
function confirmAttach()
    local a = attaching
    if not a then
        return false
    end
    if a.rec and a.o then
        triggerServerEvent("carmourAttachRequested", localPlayer, a.vehicle, a.o, a.d)
    end
    cancelAttach()
    return true
end

local function cameraRay(vehicle)
    local cx, cy, cz = getCameraMatrix()
    local sw, sh = guiGetScreenSize()
    local tx, ty, tz = getWorldFromScreenPosition(sw / 2, sh / 2, 10)
    if not tx then
        return nil
    end
    local d = place.vec.norm(localDir(vehicle, tx - cx, ty - cy, tz - cz))
    return localPoint(vehicle, cx, cy, cz), d
end

local function updateAttach()
    local a = attaching
    local vehicle = a.vehicle
    if not isElement(vehicle) or heldUname() ~= a.uname or getPedOccupiedVehicle(localPlayer) then
        return cancelAttach()
    end
    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > ATTACH_LEAVE then
        return cancelAttach()
    end
    local now = getTickCount()
    if now - a.placedAt >= PLACE_MS then
        a.placedAt = now
        local o, d = cameraRay(vehicle)
        local st = stateOf(vehicle) or carmour.new()
        local rec, why = nil, "MISS"
        if o and d then
            rec, why = place.place(geo, a.uname, o, d, st.panels)
        end
        a.o, a.d, a.why = o, d, why
        if isElement(a.ghost) then
            destroyElement(a.ghost)
        end
        a.ghost, a.rec = nil, rec
        if rec then
            rec.u = a.uname
            a.ghost = panelObject(vehicle, rec, 150)
        end
    end
    local sw, sh = guiGetScreenSize()
    local scale = sh / 1080
    local text = a.rec and "F: attach here    N: cancel" or ((REASONS[a.why] or REASONS.MISS) .. "    N: cancel")
    local colour = a.rec and tocolor(120, 255, 120, 230) or tocolor(255, 90, 90, 230)
    local y = sh * 0.62
    dxDrawText(text, 1, y + 1, sw + 1, y + 1, tocolor(0, 0, 0, 200), scale * 1.2, "default-bold", "center", "top")
    dxDrawText(text, 0, y, sw, y, colour, scale * 1.2, "default-bold", "center", "top")
    dxDrawText("+", 0, sh / 2 - 10 * scale, sw, sh / 2, colour, scale * 1.4, "default-bold", "center", "top")
end

addEventHandler("onClientRender", root, function()
    if attaching then
        updateAttach()
    end
end)

-- The torch --------------------------------------------------------------------------------------------------

local stowed = {} -- welder object -> torch object
local inHand = {} -- player -> torch object

local function newTorch()
    local obj = createObject(models.resolve(TORCH_MODEL) or FALLBACK_MODEL, 0, 0, 0)
    if obj then
        setElementCollisionsEnabled(obj, false)
    end
    return obj
end

-- the rows of a rotation R = Rz * Rx * Ry (degrees): an object's own x, y, z axes in its parent's frame
local function zxyRows(rx, ry, rz)
    local a, b, c = math.rad(rx), math.rad(ry), math.rad(rz)
    local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    local m = {
        { cc * cb - sc * sa * sb, -sc * ca, cc * sb + sc * sa * cb },
        { sc * cb + cc * sa * sb, cc * ca, sc * sb - cc * sa * cb },
        { -ca * sb, sa, ca * cb },
    }
    return { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] }
end

-- a child's matrix from its parent's (MTA rows: right, forward, up, position) and an offset { x, y, z, rx, ry, rz }
local function compose(m, o)
    local r1, r2, r3 = zxyRows(o[4], o[5], o[6])
    local function row(r)
        return {
            r[1] * m[1][1] + r[2] * m[2][1] + r[3] * m[3][1],
            r[1] * m[1][2] + r[2] * m[2][2] + r[3] * m[3][2],
            r[1] * m[1][3] + r[2] * m[2][3] + r[3] * m[3][3],
            0,
        }
    end
    local px = o[1] * m[1][1] + o[2] * m[2][1] + o[3] * m[3][1] + m[4][1]
    local py = o[1] * m[1][2] + o[2] * m[2][2] + o[3] * m[3][2] + m[4][2]
    local pz = o[1] * m[1][3] + o[2] * m[2][3] + o[3] * m[3][3] + m[4][3]
    return { row(r1), row(r2), row(r3), { px, py, pz, 1 } }
end

local function apply(m, p)
    return p[1] * m[1][1] + p[2] * m[2][1] + p[3] * m[3][1] + m[4][1],
        p[1] * m[1][2] + p[2] * m[2][2] + p[3] * m[3][2] + m[4][2],
        p[1] * m[1][3] + p[2] * m[2][3] + p[3] * m[3][3] + m[4][3]
end

local function torchOf(p)
    local t = isElement(p) and getElementData(p, "vehicles.torch")
    return type(t) == "table" and t or nil
end

-- the Welder ids whose torch a player holds
local function grabbedIds()
    local out = {}
    for _, p in ipairs(getElementsByType("player", root, true)) do
        local t = torchOf(p)
        if t and t.id then
            out[t.id] = p
        end
    end
    local mine = torchOf(localPlayer)
    if mine and mine.id then
        out[mine.id] = localPlayer
    end
    return out
end

-- a torch in the holster of every Welder this client shows, except one whose torch is out; one in every hand
local function refreshTorches()
    local want = {}
    local grabbed = grabbedIds()
    for id, obj in pairs(exports.items:worldObjectsOfType("Welder") or {}) do
        if not grabbed[id] then
            want[obj] = true
        end
    end
    for _, p in ipairs(getElementsByType("player", root, true)) do
        local obj, uname = exports.items:heldObjectOf(p)
        if obj and uname == "Welder" then
            want[obj] = true
        end
    end
    for welder, torch in pairs(stowed) do
        if not want[welder] or not isElement(welder) then
            if isElement(torch) then
                destroyElement(torch)
            end
            stowed[welder] = nil
        end
    end
    for welder in pairs(want) do
        if not stowed[welder] then
            local torch = newTorch()
            if torch then
                setElementDimension(torch, getElementDimension(welder))
                setElementInterior(torch, getElementInterior(welder))
                local o = TORCH_STOWED
                attachElements(torch, welder, o[1], o[2], o[3], o[4], o[5], o[6])
                stowed[welder] = torch
            end
        end
    end
    local holders = {}
    for _, p in pairs(grabbed) do
        holders[p] = true
    end
    for p, torch in pairs(inHand) do
        if not holders[p] then
            if isElement(torch) then
                destroyElement(torch)
            end
            inHand[p] = nil
        end
    end
    for p in pairs(holders) do
        if not inHand[p] then
            inHand[p] = newTorch()
        end
    end
end
setTimer(refreshTorches, 400, 0)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "vehicles.torch" then
        refreshTorches()
    end
end)

-- the lead: a sagging line from the Welder's socket to where it leaves the torch
local LEAD_COLOUR = tocolor(20, 20, 20, 255)
local function drawLead(x1, y1, z1, x2, y2, z2, colour)
    local dist = getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
    local sag = math.max(0.05, (carmour.LEAD - dist) * 0.25)
    local floor = math.min(z1, z2) - 0.05
    local lx, ly, lz = x1, y1, z1
    for i = 1, 12 do
        local t = i / 12
        local x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
        local z = math.max(floor, z1 + (z2 - z1) * t - sag * 4 * t * (1 - t))
        dxDrawLine3D(lx, ly, lz, x, y, z, colour or LEAD_COLOUR, 2)
        lx, ly, lz = x, y, z
    end
end

local function welderSocket(t)
    local welder = (exports.items:worldObjectsOfType("Welder") or {})[t.id]
    local m
    if isElement(welder) then
        m = getElementMatrix(welder)
    else
        local r = math.rad(t.rz or 0)
        m = { { math.cos(r), math.sin(r), 0 }, { -math.sin(r), math.cos(r), 0 }, { 0, 0, 1 }, { t.x, t.y, t.z } }
    end
    return apply(m, WELDER_SOCKET)
end

addEventHandler("onClientPedsProcessed", root, function()
    for p, torch in pairs(inHand) do
        if isElement(p) and isElement(torch) then
            local bm = getElementBoneMatrix(p, HAND_BONE)
            if bm then
                setElementMatrix(torch, compose(bm, TORCH_HAND))
                setElementDimension(torch, getElementDimension(p))
                setElementInterior(torch, getElementInterior(p))
            end
        end
    end
end)

addEventHandler("onClientRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    for p, torch in pairs(inHand) do
        local t = torchOf(p)
        if t and isElement(torch) then
            local x1, y1, z1 = welderSocket(t)
            if getDistanceBetweenPoints3D(cx, cy, cz, x1, y1, z1) < 60 then
                local x2, y2, z2 = apply(getElementMatrix(torch), TORCH_LEAD)
                drawLead(x1, y1, z1, x2, y2, z2)
            end
        end
    end
    for welder, torch in pairs(stowed) do
        if isElement(welder) and isElement(torch) and isElementOnScreen(welder) then
            local x1, y1, z1 = apply(getElementMatrix(welder), WELDER_SOCKET)
            if getDistanceBetweenPoints3D(cx, cy, cz, x1, y1, z1) < 30 then
                local x2, y2, z2 = apply(getElementMatrix(torch), TORCH_LEAD)
                drawLead(x1, y1, z1, x2, y2, z2)
            end
        end
    end
end)

function hasTorch()
    return torchOf(localPlayer) ~= nil
end

-- the Welder lying within reach whose torch is free (hud: a tap grabs it) and how far it is, or false
function nearbyWelder()
    local px, py, pz = getElementPosition(localPlayer)
    local grabbed = grabbedIds()
    local best, bestDist = false, 2.0 -- across the ground: a Welder lies about a metre below the player's centre
    for id, obj in pairs(exports.items:worldObjectsOfType("Welder") or {}) do
        local x, y, z = getElementPosition(obj)
        local d = getDistanceBetweenPoints2D(px, py, x, y)
        if d <= bestDist and math.abs(pz - z) < 2 and not grabbed[id] then
            best, bestDist = id, d
        end
    end
    return best, bestDist
end

-- Gas hooked up to Welders ----------------------------------------------------------------------------------------

local GAS_TYPES = { "Canister", "GasBottle" } -- the Gas Cylinder and the Gas Bottle (carmour.GAS_CAPACITY)
local HOSE_COLOUR = tocolor(120, 28, 22, 255)
local hoseSeen = { at = 0, welders = {}, gas = {} } -- the objects, looked up again twice a second

local function gasObjects()
    local out = {}
    for _, uname in ipairs(GAS_TYPES) do
        for id, obj in pairs(exports.items:worldObjectsOfType(uname) or {}) do
            out[id] = obj
        end
    end
    return out
end

local function hoses()
    local list = getElementData(resourceRoot, "vehicles.hoses")
    return type(list) == "table" and list or {}
end

-- the top of a gas container's object, where the hose leaves it
local function gasOutlet(obj)
    local x, y, z = getElementPosition(obj)
    local _, _, _, _, _, maxZ = getElementBoundingBox(obj)
    return x, y, z + (maxZ or 0.4) * 0.85
end

addEventHandler("onClientRender", root, function()
    local list = hoses()
    if #list == 0 then
        return
    end
    local now = getTickCount()
    if now - hoseSeen.at > 500 then
        hoseSeen.at = now
        hoseSeen.welders = exports.items:worldObjectsOfType("Welder") or {}
        hoseSeen.gas = gasObjects()
    end
    local cx, cy, cz = getCameraMatrix()
    for _, link in ipairs(list) do
        local welder, gas = hoseSeen.welders[link[1]], hoseSeen.gas[link[2]]
        if isElement(welder) and isElement(gas) and isElementOnScreen(welder) then
            local x1, y1, z1 = apply(getElementMatrix(welder), WELDER_INLET)
            if getDistanceBetweenPoints3D(cx, cy, cz, x1, y1, z1) < 40 then
                local x2, y2, z2 = gasOutlet(gas)
                drawLead(x1, y1, z1, x2, y2, z2, HOSE_COLOUR)
            end
        end
    end
end)

-- The Gas Cylinder or Gas Bottle lying within reach that has a Welder lying within the hose's reach of it (hud: a
-- tap hooks it up or unhooks it): its id, how far it is and whether it is hooked up; false when there is none
function nearbyGas()
    local px, py, pz = getElementPosition(localPlayer)
    local welders = exports.items:worldObjectsOfType("Welder") or {}
    local hooked = {}
    for _, link in ipairs(hoses()) do
        hooked[link[2]] = true
    end
    local best, bestDist = false, 2.0
    for id, obj in pairs(gasObjects()) do
        local x, y, z = getElementPosition(obj)
        local d = getDistanceBetweenPoints2D(px, py, x, y)
        if d <= bestDist and math.abs(pz - z) < 2 then
            for _, w in pairs(welders) do
                local wx, wy = getElementPosition(w)
                if getDistanceBetweenPoints2D(x, y, wx, wy) <= carmour.HOSE then
                    best, bestDist = id, d
                    break
                end
            end
        end
    end
    return best, bestDist, best and hooked[best] == true
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        sync(vehicle)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for vehicle in pairs(panels) do
        clear(vehicle)
    end
    cancelAttach()
    for _, torch in pairs(stowed) do
        if isElement(torch) then
            destroyElement(torch)
        end
    end
    for _, torch in pairs(inHand) do
        if isElement(torch) then
            destroyElement(torch)
        end
    end
end)
