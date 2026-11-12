-- Lug nuts, in the world. Holding the tyre wrench beside a wheel moves the camera to the hub, where each
-- modelled nut carries an outline. Pick one (click it, or A/D, the arrows or the mouse wheel) and hold the
-- mouse button or Space to run it along its stud: out to take the wheel off, in to fit one.
local lang

local function strings()
    if not lang then
        lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    end
    return lang
end

local models

local lug
do
    local f = fileOpen("shared/logic/lugnuts.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    lug = assert(loadstring(src, "=vehicles/lugnuts.lua"))()
end

local WHEELS = { "wheel_lf_dummy", "wheel_lb_dummy", "wheel_rf_dummy", "wheel_rb_dummy" }
local CONTROLS =
    { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "fire", "aim_weapon", "enter_exit" }
local PREVIOUS = { a = true, arrow_l = true, mouse_wheel_down = true }
local FOLLOWING = { d = true, arrow_r = true, mouse_wheel_up = true }
local NUT_SCALE = 1.7
local NUT_CORNER = 0.019 / math.sqrt(3) * NUT_SCALE -- hub axis to a corner of the hexagon
local NUT_HALF = 0.0169 / 2 * NUT_SCALE -- half the nut's height along the stud
local BOLT_RING = 0.19 -- radius of the ring of nuts, as a share of the wheel's radius
local HUB_OFFSET = 0.16
local THREAD = 0.05 -- how far a nut travels along its stud
-- camera, relative to the hub face: out along the axle, a little above and to one side so the
-- nuts are seen moving along their studs rather than end on
local CAM_OUT, CAM_UP, CAM_SIDE = 0.6, 0.14, 0.2
local CAM_FOV = 60
local CAM_EASE = 450
local CAM_CLEARANCE = 0.3 -- the camera stays this far above the ground
local WHEEL_MODEL = 20222 -- the Wheel item's model (prop_models), shown on the bare hub while fitting
local WHEEL_MODEL_RADIUS = 0.49
local WHEEL_MODEL_FACE = 0.20 -- its centre plane to the face of its hub, where the nuts seat

local session = nil
local modelId = nil
local kept = {}
local requestCancel

local function cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function shown(index)
    local progress = session.states[index] + (session.pending[index] or 0) / session.turn
    if progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end
    return progress
end

local function finished(index)
    return lug.done(shown(index), session.sign)
end

local function close()
    if not session then
        return
    end
    for _, object in ipairs(session.objects) do
        if isElement(object) then
            destroyElement(object)
        end
    end
    for _, element in ipairs({ session.wheelObject, session.light }) do
        if isElement(element) then
            destroyElement(element)
        end
    end
    for _, object in ipairs(session.hidden or {}) do
        if isElement(object) then
            setElementAlpha(object, 255)
        end
    end
    setElementAlpha(localPlayer, session.alpha)
    setCameraTarget(localPlayer)
    showCursor(false)
    guiSetInputMode("allow_binds")
    for _, control in ipairs(CONTROLS) do
        toggleControl(control, true)
    end
    session = nil
end

requestCancel = function()
    if not session then
        return
    end
    triggerServerEvent("holdActionCancelRequested", localPlayer)
    close()
end

local function flush()
    if not session then
        return
    end
    for index, delta in pairs(session.pending) do
        if math.abs(delta) > 0.04 then
            local step = delta
            if step > lug.MAX_STEP then
                step = lug.MAX_STEP
            elseif step < -lug.MAX_STEP then
                step = -lug.MAX_STEP
            end
            session.pending[index] = delta - step
            session.states[index] = lug.apply(session.states[index], step, session.sign, session.turn)
            session.sentAt[index] = getTickCount()
            triggerServerEvent("lugnutTurnRequested", localPlayer, index, step)
        end
    end
end

local function spawnNuts(vehicle, wheel, count)
    local objects = {}
    if not modelId or not isElement(vehicle) then
        return objects
    end
    local wx, wy, wz = getVehicleComponentPosition(vehicle, WHEELS[wheel], "world")
    if not wx then
        return objects
    end
    local interior, dimension = getElementInterior(vehicle), getElementDimension(vehicle)
    for _ = 1, count do
        local object = createObject(modelId, wx, wy, wz)
        if object then
            setElementInterior(object, interior)
            setElementDimension(object, dimension)
            setElementCollisionsEnabled(object, false)
            setObjectScale(object, NUT_SCALE)
            objects[#objects + 1] = object
        end
    end
    return objects
end

-- Points an object's own X, Y and Z axes along three world directions (unit length, right-handed).
local function orient(object, x, y, z, ax, ay, az)
    setElementMatrix(object, {
        { ax[1], ax[2], ax[3], 0 },
        { ay[1], ay[2], ay[3], 0 },
        { az[1], az[2], az[3], 0 },
        { x, y, z, 1 },
    })
end

-- The hub face and its axes in the world: centre, outward axle, forward and up.
local function hubFrame()
    local vehicle = session.vehicle
    if not isElement(vehicle) then
        return nil
    end
    local wx, wy, wz = getVehicleComponentPosition(vehicle, WHEELS[session.wheel], "world")
    local matrix = getElementMatrix(vehicle)
    if not wx or not matrix then
        return nil
    end
    local right, forward, up = matrix[1], matrix[2], matrix[3]
    local outward = (session.wheel <= 2) and -1 or 1
    local axle = { right[1] * outward, right[2] * outward, right[3] * outward }
    -- The dummy is where the wheel hangs at rest, not where it is drawn: a tyre never sinks into the
    -- ground, and a vehicle with a wheel missing rests on that hub. Either way the wheel being worked
    -- on sits with its tyre on the ground.
    local ground = getGroundPosition(wx, wy, wz + 1)
    local lift = ground and math.max(0, ground + session.radius - wz) or 0
    local offset = session.sign > 0 and WHEEL_MODEL_FACE * session.radius / WHEEL_MODEL_RADIUS or HUB_OFFSET
    return {
        x = wx + axle[1] * offset,
        y = wy + axle[2] * offset,
        z = wz + axle[3] * offset + lift,
        wx = wx,
        wy = wy,
        wz = wz + lift,
        axle = axle,
        forward = forward,
        up = up,
        outward = outward,
    }
end

local function placeCamera(frame)
    local a, f, u = frame.axle, frame.forward, frame.up
    -- lean towards the vehicle's nose on the left side and its tail on the right, so the view is mirrored
    local side = CAM_SIDE * -frame.outward
    local cx = frame.x + a[1] * CAM_OUT + u[1] * CAM_UP + f[1] * side
    local cy = frame.y + a[2] * CAM_OUT + u[2] * CAM_UP + f[2] * side
    local cz = frame.z + a[3] * CAM_OUT + u[3] * CAM_UP + f[3] * side
    local lx, ly, lz, fov = frame.x, frame.y, frame.z, CAM_FOV
    local from = session.cameraFrom
    local t = (getTickCount() - session.startedAt) / CAM_EASE
    if from and t < 1 then
        t = getEasingValue(t, "InOutQuad")
        cx, cy, cz = from[1] + (cx - from[1]) * t, from[2] + (cy - from[2]) * t, from[3] + (cz - from[3]) * t
        lx, ly, lz = from[4] + (lx - from[4]) * t, from[5] + (ly - from[5]) * t, from[6] + (lz - from[6]) * t
        fov = from[7] + (fov - from[7]) * t
    end
    local ground = getGroundPosition(cx, cy, cz + 1)
    if ground and cz < ground + CAM_CLEARANCE then
        cz = ground + CAM_CLEARANCE
    end
    setCameraMatrix(cx, cy, cz, lx, ly, lz, 0, fov)
    if isElement(session.light) then
        setElementPosition(session.light, cx, cy, cz)
    end
end

-- Moves every nut to its place on its stud and records where it is for the outlines and the cursor.
local function placeNuts(frame)
    local a, f, u = frame.axle, frame.forward, frame.up
    local layout = lug.layout(#session.states, BOLT_RING * session.radius)
    -- the ring runs clockwise as the player sees it, whichever side of the vehicle the wheel is on
    local across = frame.outward
    if isElement(session.wheelObject) then
        -- the model's axle is its own X axis
        local fx, fy, fz = cross(u[1], u[2], u[3], a[1], a[2], a[3])
        orient(session.wheelObject, frame.wx, frame.wy, frame.wz, a, { fx, fy, fz }, u)
    end
    for index = 1, #session.states do
        local progress = shown(index)
        local spot = layout[index]
        local reach = (1 - progress) * THREAD + NUT_HALF
        local sx, sy = spot.x * across, -spot.y
        local x = frame.x + a[1] * reach + f[1] * sx + u[1] * sy
        local y = frame.y + a[2] * reach + f[2] * sx + u[2] * sy
        local z = frame.z + a[3] * reach + f[3] * sx + u[3] * sy
        local spin = -progress * session.turn * frame.outward
        local cosine, sine = math.cos(spin), math.sin(spin)
        local xx = f[1] * cosine + u[1] * sine
        local xy = f[2] * cosine + u[2] * sine
        local xz = f[3] * cosine + u[3] * sine
        local yx, yy, yz = cross(a[1], a[2], a[3], xx, xy, xz)
        local gone = session.sign < 0 and lug.done(progress, session.sign)
        session.nuts[index] = { x = x, y = y, z = z, xx = xx, xy = xy, xz = xz, yx = yx, yy = yy, yz = yz, gone = gone }
        local object = session.objects[index]
        if isElement(object) then
            orient(object, x, y, z, { xx, xy, xz }, { yx, yy, yz }, a)
            setElementAlpha(object, gone and 0 or 255)
        end
    end
end

-- A hexagonal cage just outside the nut, turning with it. Line widths are world units, not pixels,
-- and a 3D line drawn after the GUI does not show at all.
local function outline(frame, nut, colour, width)
    local a = frame.axle
    local radius = NUT_CORNER * 1.22
    local half = NUT_HALF * 1.25
    local front, back = {}, {}
    for corner = 1, 6 do
        local angle = (corner - 1) * math.pi / 3
        local cosine, sine = math.cos(angle) * radius, math.sin(angle) * radius
        local px = nut.x + nut.xx * cosine + nut.yx * sine
        local py = nut.y + nut.xy * cosine + nut.yy * sine
        local pz = nut.z + nut.xz * cosine + nut.yz * sine
        front[corner] = { px + a[1] * half, py + a[2] * half, pz + a[3] * half }
        back[corner] = { px - a[1] * half, py - a[2] * half, pz - a[3] * half }
    end
    for corner = 1, 6 do
        local following = corner % 6 + 1
        local p, q = front[corner], front[following]
        dxDrawLine3D(p[1], p[2], p[3], q[1], q[2], q[3], colour, width)
        local r, s = back[corner], back[following]
        dxDrawLine3D(r[1], r[2], r[3], s[1], s[2], s[3], colour, width)
        dxDrawLine3D(p[1], p[2], p[3], r[1], r[2], r[3], colour, width)
    end
end

-- The nut under the cursor, if any.
local function hovered(frame)
    local cursorX, cursorY = getCursorPosition()
    if not cursorX then
        return nil
    end
    local sw, sh = guiGetScreenSize()
    cursorX, cursorY = cursorX * sw, cursorY * sh
    local u = frame.up
    local best, bestDistance = nil, nil
    for index, nut in ipairs(session.nuts) do
        if not nut.gone then
            local x, y = getScreenFromWorldPosition(nut.x, nut.y, nut.z, 0, false)
            local ex, ey = getScreenFromWorldPosition(
                nut.x + u[1] * NUT_CORNER * 1.8,
                nut.y + u[2] * NUT_CORNER * 1.8,
                nut.z + u[3] * NUT_CORNER * 1.8,
                0,
                false
            )
            if x and ex then
                local reach = (ex - x) ^ 2 + (ey - y) ^ 2
                local distance = (cursorX - x) ^ 2 + (cursorY - y) ^ 2
                if distance <= reach and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = index, distance
                end
            end
        end
    end
    return best
end

local function pick(index)
    if index and index ~= session.selected then
        session.selected = index
        session.driving = nil
        playSoundFrontEnd(3)
    end
end

local function cycle(direction)
    local following = lug.nextOpen(session.states, session.sign, session.selected or 1, direction)
    pick(following)
end

-- Starts the wrench on the selected nut; it runs for as long as `button` stays down.
local function drive(button)
    local index = session.selected
    if not index or finished(index) then
        return
    end
    session.driving = index
    session.drivingWith = button
end

local function turnWrench(elapsed)
    local index = session.driving
    if not index then
        return
    end
    if not session.down[session.drivingWith] then
        session.driving = nil
        return
    end
    if finished(index) then
        session.driving = nil
        playSoundFrontEnd(1)
        local following = lug.nextOpen(session.states, session.sign, index, 1)
        if following then
            session.selected = following
        end
        return
    end
    local travel = session.sign * lug.SPEED * elapsed / 1000
    session.pending[index] = (session.pending[index] or 0) + travel
end

-- The server's progress wins once nothing of ours is still on its way, so a dropped report cannot
-- leave a nut looking finished; while reports are in flight its older figure would jerk the nut back.
local function reconcile()
    local now = getTickCount()
    for index, progress in pairs(session.server) do
        if session.driving ~= index and now - (session.sentAt[index] or 0) > 600 then
            session.states[index] = progress
            session.server[index] = nil
        end
    end
end

local function drawHud()
    local sw, sh = guiGetScreenSize()
    local done = 0
    for index = 1, #session.states do
        if finished(index) then
            done = done + 1
        end
    end
    local white, shade = tocolor(255, 255, 255, 235), tocolor(0, 0, 0, 200)
    local function label(text, top, scale, font, colour)
        dxDrawText(text, 1, top + 1, sw + 1, top + 31, shade, scale, font, "center", "top", false, true)
        dxDrawText(text, 0, top, sw, top + 30, colour, scale, font, "center", "top", false, true)
    end
    label(session.title, sh * 0.08, 1.3, "default-bold", white)
    label(("%d / %d"):format(done, #session.states), sh * 0.08 + 26, 1.3, "default-bold", white)
    lang = strings()
    local hint = session.sign < 0
            and lang.text("Click a nut, or pick one with [A] and [D]. Hold the mouse button or [Space] to undo it.")
        or lang.text("Click a nut, or pick one with [A] and [D]. Hold the mouse button or [Space] to thread it on.")
    label(hint, sh * 0.86, 1, "default-bold", tocolor(225, 225, 225, 235))
    label(lang.text("Escape: stop"), sh * 0.86 + 24, 1, "default", tocolor(190, 190, 190, 220))
end

addEventHandler("onClientPreRender", root, function(elapsed)
    if not session then
        return
    end
    local frame = hubFrame()
    if not frame then
        return requestCancel()
    end
    turnWrench(elapsed)
    if getTickCount() >= session.nextSend then
        session.nextSend = getTickCount() + 70
        flush()
    end
    reconcile()
    placeCamera(frame)
    placeNuts(frame)
    session.frame = frame
end)

addEventHandler("onClientRender", root, function()
    if not session or not session.frame then
        return
    end
    local frame = session.frame
    session.hover = hovered(frame)
    for index, nut in ipairs(session.nuts) do
        if not nut.gone then
            local colour, width = tocolor(255, 255, 255, 170), 0.2
            if index == session.selected then
                colour, width = tocolor(255, 196, 40, 255), 0.35
            elseif finished(index) then
                colour = tocolor(110, 230, 120, 230)
            elseif index == session.hover then
                colour, width = tocolor(255, 255, 255, 255), 0.3
            end
            outline(frame, nut, colour, width)
        end
    end
    drawHud()
    if isPedDead(localPlayer) then
        return requestCancel()
    end
    local x, y, z = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, session.x, session.y, session.z) > 0.8 then
        requestCancel()
    end
end)

addEventHandler("onClientKey", root, function(button, press)
    if not session then
        return
    end
    if button == "escape" or button == "backspace" then
        if press and not isChatBoxInputActive() and not isConsoleActive() then
            cancelEvent()
            requestCancel()
        end
        return
    end
    if not press then
        session.down[button] = nil
        return
    end
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then
        return
    end
    if PREVIOUS[button] then
        cycle(-1)
    elseif FOLLOWING[button] then
        cycle(1)
    elseif button == "space" or button == "enter" then
        session.down[button] = true
        drive(button)
    elseif button == "mouse1" then
        session.down[button] = true
        local index = session.hover
        if index and not finished(index) then
            pick(index)
            drive(button)
        end
    end
end)

addEventHandler("onClientMinimize", root, function()
    if session then
        session.down = {}
        session.driving = nil
    end
end)

addEventHandler("lugnutsStarted", root, function(count, sign, turn, wheel, title, states)
    if source ~= nil and getElementType(source) ~= "vehicle" then
        return
    end
    close()
    count = tonumber(count) or 0
    if count < 1 or type(states) ~= "table" then
        return
    end
    local vehicle = (source and getElementType(source) == "vehicle") and source or nil
    if not vehicle then
        return
    end
    wheel = tonumber(wheel) or 1
    local x, y, z = getElementPosition(localPlayer)
    local cx, cy, cz, lx, ly, lz, _, fov = getCameraMatrix()
    session = {
        count = count,
        sign = tonumber(sign) or -1,
        turn = tonumber(turn) or lug.TURN,
        wheel = wheel,
        title = tostring(title or ""),
        states = states,
        pending = {},
        server = {},
        sentAt = {},
        nuts = {},
        down = {},
        selected = 1,
        objects = spawnNuts(vehicle, wheel, count),
        vehicle = vehicle,
        x = x,
        y = y,
        z = z,
        nextSend = getTickCount(),
        startedAt = getTickCount(),
        cameraFrom = { cx, cy, cz, lx, ly, lz, fov or 70 },
        alpha = getElementAlpha(localPlayer),
    }
    local axleName = (wheel == 2 or wheel == 4) and "rear_axle" or "front_axle"
    session.radius = (getVehicleModelWheelSize(getElementModel(vehicle), axleName) or 0.7) / 2
    -- fitting: the hub is bare until the server fits the wheel, so show one for the nuts to go onto
    if session.sign > 0 then
        if not models then
            models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
        end
        local id = models.resolve(WHEEL_MODEL)
        local object = id and createObject(id, x, y, z)
        if object then
            setElementInterior(object, getElementInterior(vehicle))
            setElementDimension(object, getElementDimension(vehicle))
            setElementCollisionsEnabled(object, false)
            setObjectScale(object, session.radius / WHEEL_MODEL_RADIUS)
            session.wheelObject = object
        end
    end
    -- a work light at the camera, or the nuts are lost at night
    session.light = createLight(0, cx, cy, cz, 4, 255, 244, 225)
    -- loose wheels lying beside the vehicle (the one about to go on, or one just taken off) are
    -- right where the camera goes, as is the player
    session.hidden = {}
    for _, object in pairs(exports.items:worldObjectsOfType("Wheel") or {}) do
        if isElement(object) and getElementAlpha(object) > 0 then
            local ox, oy, oz = getElementPosition(object)
            if getDistanceBetweenPoints3D(x, y, z, ox, oy, oz) < 3 then
                setElementAlpha(object, 0)
                session.hidden[#session.hidden + 1] = object
            end
        end
    end
    setElementAlpha(localPlayer, 0)
    showCursor(true)
    guiSetInputMode("no_binds")
    for _, control in ipairs(CONTROLS) do
        toggleControl(control, false)
    end
end)

addEventHandler("lugnutTurned", localPlayer, function(index, progress)
    if not session then
        return
    end
    index = tonumber(index)
    progress = tonumber(progress)
    if not index or not progress or type(session.states[index]) ~= "number" then
        return
    end
    session.server[index] = progress
end)

addEventHandler("vehicleHoldStopped", localPlayer, function()
    close()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local id = engineRequestModel("object")
    local txd = engineLoadTXD("files/lugnut.txd")
    local dff = engineLoadDFF("files/lugnut.dff")
    local col = engineLoadCOL("files/lugnut.col")
    if not id or not txd or not dff or not col then
        if id then
            engineFreeModel(id)
        end
        return
    end
    engineImportTXD(txd, id)
    engineReplaceModel(dff, id)
    engineReplaceCOL(col, id)
    engineSetModelLODDistance(id, 40)
    modelId = id
    kept = { txd, dff, col }
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    close()
    if modelId then
        engineFreeModel(modelId)
        modelId = nil
    end
    kept = {}
end)
