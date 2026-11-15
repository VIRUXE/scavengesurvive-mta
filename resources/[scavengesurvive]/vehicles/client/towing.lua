-- Tow Bars and towing ropes on the client (server/towing.lua has the rules):
-- - the Tow Bar model (20266, prop_models) bolted on every streamed vehicle with "vehicles.towbar", its ball at the
--   model's trailer_attach dummy, so a hitched trailer's coupler meets it;
-- - every streamed rope ("vehicles.ropeTow" on a tower) drawn from the tower's hitch to the towed vehicle's front,
--   sagging while slack (shared/logic/rope.lua), and a pending tie drawn from the hitch to the player's hand;
-- - the rope's pull, run by the client that syncs the towed vehicle (the tower's driver, while it has no driver of
--   its own): past the rope's length the two anchors may not fly apart any further, an impulse at the towed vehicle's
--   front (and, when this client syncs it too, the opposite one at the tower's hitch) takes back the separating speed;
-- - the interaction list's "Remove tow bar" and "Untie rope" entries (towingActions, through interactionActions).
local vlogic, rope
do
    local f = fileOpen("shared/logic/vehicle.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    vlogic = assert(loadstring(src, "=vehicles/vehicle.lua"))()
    f = fileOpen("shared/logic/rope.lua", true)
    src = fileRead(f, fileGetSize(f))
    fileClose(f)
    rope = assert(loadstring(src, "=vehicles/rope.lua"))()
end
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local TOWBAR_MODEL = 20266
local SYNC_MS = 500
local ROPE_WIDTH = 0.035
local ROPE_COLOUR = tocolor(196, 170, 120, 255)

local bars = {} -- vehicle -> the tow bar object on it
local ropes = {} -- tower -> towed, every streamed rope
local pendingTower = nil -- the vehicle whose hitch the player's rope is tied to, before its other end
local hitchCache, frontCache, handlingCache = {}, {}, {}
local ropeTexture = dxCreateTexture("files/rope.png", "dxt1", true, "wrap")

-- the ball's place against the bounding box: this far behind its rear face, this high above its bottom (the wheels'
-- contact patch); a rope's front end sits as high, this far inside the front face
local HITCH_BACK, HITCH_UP, FRONT_IN = 0.12, 0.36, 0.1

-- A model's hitch in its own frame: the trailer_attach dummy (no car model the game ships has one: 0, 0, 0), else the
-- middle of the rear at bumper height. Kept per model once the bounding box is known.
local function hitchOffset(vehicle)
    local model = getElementModel(vehicle)
    local c = hitchCache[model]
    if not c then
        local x, y, z = getVehicleModelDummyDefaultPosition(model, "trailer_attach")
        local _, minY, minZ = getElementBoundingBox(vehicle)
        if not minY then
            return 0, -2.4, -0.3
        end
        if not x or (math.abs(x) + math.abs(y) + math.abs(z) < 0.01) then
            x, y, z = 0, minY - HITCH_BACK, minZ + HITCH_UP
        end
        c = { x, y, z }
        hitchCache[model] = c
    end
    return c[1], c[2], c[3]
end

-- The middle of a model's front bumper, where a rope's other end is tied.
local function frontOffset(vehicle)
    local model = getElementModel(vehicle)
    local c = frontCache[model]
    if not c then
        local _, _, minZ, _, maxY = getElementBoundingBox(vehicle)
        if not maxY then
            return 0, 2.3, -0.3
        end
        c = { 0, maxY - FRONT_IN, minZ + HITCH_UP }
        frontCache[model] = c
    end
    return c[1], c[2], c[3]
end

local function toWorld(vehicle, lx, ly, lz)
    local m = getElementMatrix(vehicle)
    return lx * m[1][1] + ly * m[2][1] + lz * m[3][1] + m[4][1],
        lx * m[1][2] + ly * m[2][2] + lz * m[3][2] + m[4][2],
        lx * m[1][3] + ly * m[2][3] + lz * m[3][3] + m[4][3]
end

local function massOf(vehicle)
    local model = getElementModel(vehicle)
    local h = handlingCache[model]
    if not h then
        local hd = getVehicleHandling(vehicle) or {}
        h = { math.max(100, tonumber(hd.mass) or 1500), math.max(200, tonumber(hd.turnMass) or 4000) }
        handlingCache[model] = h
    end
    return h[1], h[2]
end

-- the velocity (MTA units) of a vehicle's point (px, py, pz), and that point's offset from its centre in x and y
local function pointVelocity(vehicle, px, py, pz)
    local vx, vy, vz = getElementVelocity(vehicle)
    local wx, wy, wz = getElementAngularVelocity(vehicle)
    local cx, cy, cz = getElementPosition(vehicle)
    local rx, ry, rz = px - cx, py - cy, pz - cz
    return vx + wy * rz - wz * ry, vy + wz * rx - wx * rz, vz + wx * ry - wy * rx, rx, ry
end

-- one impulse of size j along (nx, ny, nz) at a point (rx, ry) of a vehicle, as a change of speed and of spin
local function push(vehicle, j, nx, ny, nz, rx, ry)
    local mass, inertia = massOf(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)
    setElementVelocity(vehicle, vx + nx * j / mass, vy + ny * j / mass, vz + nz * j / mass)
    local wx, wy, wz = getElementAngularVelocity(vehicle)
    setElementAngularVelocity(vehicle, wx, wy, wz + (rx * ny - ry * nx) * j / inertia)
end

local function pull(tower, towed, ax, ay, az, bx, by, bz, dt)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= rope.LENGTH or dist < 0.001 then
        return
    end
    local nx, ny, nz = dx / dist, dy / dist, dz / dist
    local avx, avy, avz, arx, ary = pointVelocity(tower, ax, ay, az)
    local bvx, bvy, bvz, brx, bry = pointVelocity(towed, bx, by, bz)
    local vrel = (bvx - avx) * nx + (bvy - avy) * ny + (bvz - avz) * nz
    local want = rope.correction(dist, vrel, dt)
    if want <= 0 then
        return
    end
    local m2, i2 = massOf(towed)
    local inv = rope.inverseMass(m2, i2, brx, bry, nx, ny)
    local both = isElementSyncer(tower) and not isElementFrozen(tower)
    if both then
        local m1, i1 = massOf(tower)
        inv = inv + rope.inverseMass(m1, i1, arx, ary, nx, ny)
    end
    local j = want / inv
    push(towed, -j, nx, ny, nz, brx, bry)
    if both then
        push(tower, j, nx, ny, nz, arx, ary)
    end
end

local function drawRope(ax, ay, az, bx, by, bz)
    local mx, my, mz = (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2
    local ground = getGroundPosition(mx, my, mz + 0.5)
    local pts = rope.points(ax, ay, az, bx, by, bz, ground ~= 0 and ground or nil)
    for i = 1, #pts - 1 do
        local p, q = pts[i], pts[i + 1]
        if ropeTexture then
            dxDrawMaterialLine3D(p[1], p[2], p[3], q[1], q[2], q[3], ropeTexture, ROPE_WIDTH, ROPE_COLOUR)
        else
            dxDrawLine3D(p[1], p[2], p[3], q[1], q[2], q[3], ROPE_COLOUR, 2)
        end
    end
end

addEventHandler("onClientPreRender", root, function(msSinceLastFrame)
    local dt = math.min(msSinceLastFrame, 100) / 1000
    for tower, towed in pairs(ropes) do
        if isElement(tower) and isElement(towed) and isElementStreamedIn(tower) and isElementStreamedIn(towed) then
            local ax, ay, az = toWorld(tower, hitchOffset(tower))
            local bx, by, bz = toWorld(towed, frontOffset(towed))
            if isElementSyncer(towed) and not isElementFrozen(towed) then
                pull(tower, towed, ax, ay, az, bx, by, bz, dt)
            end
            drawRope(ax, ay, az, bx, by, bz)
        end
    end
    if pendingTower and isElement(pendingTower) and isElementStreamedIn(pendingTower) then
        local ax, ay, az = toWorld(pendingTower, hitchOffset(pendingTower))
        local hx, hy, hz = getPedBonePosition(localPlayer, 25)
        if hx then
            drawRope(ax, ay, az, hx, hy, hz)
        end
    end
end)

local function removeBar(vehicle)
    local obj = bars[vehicle]
    bars[vehicle] = nil
    if obj and isElement(obj) then
        destroyElement(obj)
    end
end

local function placeBar(vehicle)
    local model = models.resolve(TOWBAR_MODEL)
    if not model then
        return
    end
    local obj = bars[vehicle]
    if obj and isElement(obj) and getElementModel(obj) == model then
        return
    end
    removeBar(vehicle)
    local x, y, z = getElementPosition(vehicle)
    obj = createObject(model, x, y, z)
    if not obj then
        return
    end
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    local hx, hy, hz = hitchOffset(vehicle)
    attachElements(obj, vehicle, hx, hy, hz)
    bars[vehicle] = obj
end

-- what is streamed in: the bars to show and the ropes to pull and draw
local function sync()
    local seen, nextRopes = {}, {}
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(v, "vehicles.towbar") == true then
            seen[v] = true
            placeBar(v)
        end
        local towed = getElementData(v, "vehicles.ropeTow")
        if towed and isElement(towed) then
            nextRopes[v] = towed
        end
    end
    for v in pairs(bars) do
        if not seen[v] then
            removeBar(v)
        end
    end
    ropes = nextRopes
end
setTimer(sync, SYNC_MS, 0)
addEventHandler("onClientElementDataChange", root, function(key)
    if (key == "vehicles.towbar" or key == "vehicles.ropeTow") and getElementType(source) == "vehicle" then
        sync()
    end
end)
addEventHandler("sampModelsChanged", root, function()
    for v in pairs(bars) do
        removeBar(v)
    end
    sync()
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    for v in pairs(bars) do
        removeBar(v)
    end
end)

addEventHandler("vehicleRopeTieStarted", localPlayer, function(tower)
    pendingTower = isElement(tower) and tower or nil
end)

local function towerOf(vehicle)
    for tower, towed in pairs(ropes) do
        if towed == vehicle then
            return tower
        end
    end
end

-- The HUD's F line with a Tow Bar or Rope in hand (hud keyactions M.TOW), the same checks the server makes on F:
-- "fit" at the rear of a car without a bar that takes one, "hitch" at a free hitch (a stock one or a bar), "front" at
-- another vehicle's front once the rope is tied to a hitch; false anywhere else.
function towHint(heldUname)
    if getPedOccupiedVehicle(localPlayer) then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestDist = nil, 5.5
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy, vz = getElementPosition(v)
        local d = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
        if d < bestDist and getPedContactElement(localPlayer) ~= v then
            best, bestDist = v, d
        end
    end
    if not best then
        return false
    end
    local vx, vy = getElementPosition(best)
    local _, _, rz = getElementRotation(best)
    local angle = vlogic.angleToVehicle(px, py, vx, vy, rz)
    local vt = exports.data:vehicleType(getElementData(best, "vehicles.type"))
    local towbar = getElementData(best, "vehicles.towbar") == true
    if heldUname == "TowBar" then
        return vlogic.isRear(angle) and not towbar and vlogic.canFitTowbar(vt) and "fit" or false
    end
    if heldUname ~= "Rope" then
        return false
    end
    if pendingTower and isElement(pendingTower) and best ~= pendingTower then
        return vlogic.isFront(angle) and not towerOf(best) and "front" or false
    end
    local free = not ropes[best] and not getVehicleTowedByVehicle(best)
    return vlogic.isRear(angle) and free and vlogic.hitchOf(vt, towbar) and "hitch" or false
end

-- The interaction list's tow entries for the vehicles around an on-foot player with empty hands: "Remove tow bar" at
-- the rear of one with a bar and nothing on it, "Untie rope" at the tower's rear or the towed vehicle's front. With
-- either at a rear the trunk joins the list, as the interact key alone would have opened it.
function towingActions(heldUname)
    if heldUname or getPedOccupiedVehicle(localPlayer) then
        return {}
    end
    local actions = {}
    local px, py, pz = getElementPosition(localPlayer)
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy, vz = getElementPosition(vehicle)
        if
            getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= 5.5
            and getElementDimension(vehicle) == getElementDimension(localPlayer)
            and getPedContactElement(localPlayer) ~= vehicle
        then
            local _, _, rz = getElementRotation(vehicle)
            local angle = vlogic.angleToVehicle(px, py, vx, vy, rz)
            local rear, front = vlogic.isRear(angle), vlogic.isFront(angle)
            local vehicleType = exports.data:vehicleType(getElementData(vehicle, "vehicles.type"))
            local name = vehicleType and lang.text(vehicleType.name) or getVehicleName(vehicle)
            local id = "vehicle:" .. tostring(getElementData(vehicle, "vehicles.id")) .. ":"
            local added = false
            local function add(key, label, event, action)
                actions[#actions + 1] = {
                    id = id .. key,
                    label = label .. " · " .. name,
                    event = event,
                    target = vehicle,
                    action = action,
                }
                added = true
            end
            local roped = ropes[vehicle] ~= nil
            if rear and roped then
                add("untie_rope", lang.text("Untie rope"), "vehicleTowActionRequested", "untie_rope")
            elseif
                rear
                and getElementData(vehicle, "vehicles.towbar") == true
                and not getVehicleTowedByVehicle(vehicle)
            then
                add("remove_towbar", lang.text("Remove tow bar"), "vehicleTowActionRequested", "remove_towbar")
            end
            if front and towerOf(vehicle) then
                add("untie_rope", lang.text("Untie rope"), "vehicleTowActionRequested", "untie_rope")
            end
            if added and rear and getElementData(vehicle, "vehicles.containerId") then
                add("trunk", lang.text("Open trunk"), "vehicleInteractRequested")
            end
        end
    end
    return actions
end
