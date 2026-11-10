-- Lug-nut minigame. Hold the tyre wrench beside a wheel and each nut has to be dragged around:
-- counter-clockwise to take the wheel off, clockwise to do one up. The socket is the modelled nut.
local lang

local function strings()
    if not lang then
        lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    end
    return lang
end

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
local NUT_SCALE = 2.2
local BOLT_RADIUS = 0.10
local HUB_OFFSET = 0.16

local session = nil
local modelId = nil
local kept = {}
local requestCancel

local function wrap(delta)
    while delta > math.pi do
        delta = delta - 2 * math.pi
    end
    while delta < -math.pi do
        delta = delta + 2 * math.pi
    end
    return delta
end

local function cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function shown(index)
    local extra = session.pending[index] or 0
    local useful = math.max(0, session.sign > 0 and extra or -extra)
    local progress = session.states[index] + session.sign * (useful / session.turn)
    if progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end
    return progress
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
    showCursor(false)
    guiSetInputMode("allow_binds")
    for _, control in ipairs(CONTROLS) do
        toggleControl(control, true)
    end
    if requestCancel then
        unbindKey("escape", "down", requestCancel)
        unbindKey("backspace", "down", requestCancel)
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
            local blocked = lug.blocked(session.states, index, session.sign)
            local progress, seized = lug.apply(session.states[index], step, session.sign, session.turn, blocked)
            local wasDone = lug.done(session.states[index], session.sign)
            session.states[index] = progress
            if seized then
                session.seizedUntil = getTickCount() + 1400
            end
            if not wasDone and lug.done(progress, session.sign) then
                playSoundFrontEnd(1)
            end
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
            objects[#objects + 1] = object
        end
    end
    return objects
end

local function placeNuts()
    local vehicle = session.vehicle
    if not isElement(vehicle) then
        return
    end
    local wx, wy, wz = getVehicleComponentPosition(vehicle, WHEELS[session.wheel], "world")
    local matrix = getElementMatrix(vehicle)
    if not wx or not matrix then
        return
    end
    local right, forward, up = matrix[1], matrix[2], matrix[3]
    local outward = (session.wheel <= 2) and -1 or 1
    local axleX, axleY, axleZ = right[1] * outward, right[2] * outward, right[3] * outward
    local layout = lug.layout(#session.states, 1)
    for index, object in ipairs(session.objects) do
        if isElement(object) then
            local progress = shown(index)
            local spot = layout[index]
            local reach = HUB_OFFSET + (1 - progress) * 0.03
            -- spot.y grows downward on the diagram; flip it so nut 1 sits at the top of the hub
            local x = wx + axleX * reach + (forward[1] * spot.x - up[1] * spot.y) * BOLT_RADIUS
            local y = wy + axleY * reach + (forward[2] * spot.x - up[2] * spot.y) * BOLT_RADIUS
            local z = wz + axleZ * reach + (forward[3] * spot.x - up[3] * spot.y) * BOLT_RADIUS
            local start = session.sign < 0 and 1 or 0
            local spin = (progress - start) * session.turn
            local cosine, sine = math.cos(spin), math.sin(spin)
            local xx = forward[1] * cosine + up[1] * sine
            local xy = forward[2] * cosine + up[2] * sine
            local xz = forward[3] * cosine + up[3] * sine
            local yx, yy, yz = cross(axleX, axleY, axleZ, xx, xy, xz)
            local scale = NUT_SCALE
            setElementMatrix(object, {
                { xx * scale, xy * scale, xz * scale },
                { yx * scale, yy * scale, yz * scale },
                { axleX * scale, axleY * scale, axleZ * scale },
                { x, y, z },
            })
            local alpha = (session.sign < 0 and lug.done(progress, session.sign)) and 0 or 255
            setElementAlpha(object, alpha)
        end
    end
end

local function draw()
    local sw, sh = guiGetScreenSize()
    local cx, cy = sw / 2, sh / 2 + sh * 0.02
    local hub = math.min(sw, sh) * 0.22
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 110))
    dxDrawCircle(cx, cy, hub, 0, 360, tocolor(28, 30, 34, 230), tocolor(18, 18, 20, 230), 64)
    dxDrawCircle(cx, cy, hub * 0.72, 0, 360, tocolor(55, 58, 64, 255), tocolor(40, 42, 46, 255), 48)
    dxDrawText(
        session.title,
        0,
        cy - hub - 58,
        sw,
        cy - hub - 28,
        tocolor(255, 255, 255, 230),
        1.2,
        "default-bold",
        "center",
        "bottom"
    )
    lang = strings()
    local hint = session.sign < 0
            and lang.text("Drag a nut counter-clockwise. It seizes if both neighbours are still tight.")
        or lang.text("Drag a nut clockwise. It seizes if both neighbours are still loose.")
    dxDrawText(
        hint,
        sw * 0.15,
        cy - hub - 28,
        sw * 0.85,
        cy - hub - 4,
        tocolor(210, 210, 210, 220),
        1,
        "default",
        "center",
        "top",
        true
    )
    local layout = lug.layout(#session.states, hub * 0.62)
    local size = hub * 0.34
    local cursorX, cursorY = getCursorPosition()
    if cursorX then
        cursorX, cursorY = cursorX * sw, cursorY * sh
    end
    local done = 0
    for index, spot in ipairs(layout) do
        local progress = shown(index)
        if lug.done(progress, session.sign) then
            done = done + 1
        end
        local x, y = cx + spot.x, cy + spot.y
        local grabbed = session.grab == index
        local colour = tocolor(255, 255, 255, 255)
        if lug.done(progress, session.sign) then
            colour = tocolor(190, 230, 190, 255)
        elseif grabbed and session.seizedUntil and getTickCount() < session.seizedUntil then
            colour = tocolor(255, 150, 140, 255)
        end
        if grabbed then
            dxDrawCircle(x, y, size * 0.62, 0, 360, tocolor(240, 200, 80, 180), tocolor(240, 200, 80, 40), 24)
        end
        local start = session.sign < 0 and 1 or 0
        local rotation = math.deg((progress - start) * session.turn)
        dxDrawImage(x - size / 2, y - size / 2, size, size, "files/lugnut.png", rotation, size / 2, size / 2, colour)
    end
    dxDrawText(
        ("%d / %d"):format(done, #session.states),
        0,
        cy + hub + 8,
        sw,
        cy + hub + 36,
        tocolor(255, 255, 255, 230),
        1.3,
        "default-bold",
        "center",
        "top"
    )
    if session.seizedUntil and getTickCount() < session.seizedUntil then
        dxDrawText(
            lang.text("Seized. Ease the neighbouring nuts first."),
            0,
            cy + hub + 36,
            sw,
            cy + hub + 64,
            tocolor(255, 120, 100, 240),
            1,
            "default-bold",
            "center",
            "top"
        )
    else
        dxDrawText(
            lang.text("Escape: stop"),
            0,
            cy + hub + 36,
            sw,
            cy + hub + 64,
            tocolor(180, 180, 180, 200),
            1,
            "default",
            "center",
            "top"
        )
    end
    if session.grab and cursorX and session.lastAngle then
        local spot = layout[session.grab]
        local angle = math.atan2((cursorY - (cy + spot.y)), (cursorX - (cx + spot.x)))
        local delta = wrap(angle - session.lastAngle)
        session.lastAngle = angle
        local useful = (session.sign > 0 and delta > 0) or (session.sign < 0 and delta < 0)
        if useful then
            session.pending[session.grab] = (session.pending[session.grab] or 0) + delta
        end
    end
    if getTickCount() >= session.nextSend then
        session.nextSend = getTickCount() + 70
        flush()
    end
    if isPedDead(localPlayer) then
        requestCancel()
        return
    end
    local x, y, z = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, session.x, session.y, session.z) > 0.8 then
        requestCancel()
    end
end

addEventHandler("onClientRender", root, function()
    if not session then
        return
    end
    placeNuts()
    draw()
end)

addEventHandler("onClientClick", root, function(button, state, _, _, _, _, _)
    if not session or button ~= "left" then
        return
    end
    if state == "up" then
        session.grab = nil
        session.lastAngle = nil
        flush()
        return
    end
    local sw, sh = guiGetScreenSize()
    local cx, cy = sw / 2, sh / 2 + sh * 0.02
    local hub = math.min(sw, sh) * 0.22
    local cursorX, cursorY = getCursorPosition()
    if not cursorX then
        return
    end
    cursorX, cursorY = cursorX * sw, cursorY * sh
    local layout = lug.layout(#session.states, hub * 0.62)
    local best, bestDistance = nil, (hub * 0.22) ^ 2
    for index, spot in ipairs(layout) do
        local dx, dy = cursorX - (cx + spot.x), cursorY - (cy + spot.y)
        local distance = dx * dx + dy * dy
        if distance <= bestDistance then
            best, bestDistance = index, distance
        end
    end
    if not best or lug.done(session.states[best], session.sign) then
        session.grab = nil
        return
    end
    local spot = layout[best]
    session.grab = best
    session.lastAngle = math.atan2(cursorY - (cy + spot.y), cursorX - (cx + spot.x))
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
    local x, y, z = getElementPosition(localPlayer)
    session = {
        count = count,
        sign = tonumber(sign) or -1,
        turn = tonumber(turn) or lug.TURN,
        wheel = tonumber(wheel) or 1,
        title = tostring(title or ""),
        states = states,
        pending = {},
        grab = nil,
        objects = spawnNuts(vehicle, tonumber(wheel) or 1, count),
        vehicle = vehicle,
        x = x,
        y = y,
        z = z,
        nextSend = getTickCount(),
        seizedUntil = 0,
    }
    showCursor(true)
    guiSetInputMode("no_binds")
    for _, control in ipairs(CONTROLS) do
        toggleControl(control, false)
    end
    bindKey("escape", "down", requestCancel)
    bindKey("backspace", "down", requestCancel)
end)

addEventHandler("lugnutTurned", localPlayer, function(index, progress, seized)
    if not session then
        return
    end
    index = tonumber(index)
    progress = tonumber(progress)
    if not index or not progress or type(session.states[index]) ~= "number" then
        return
    end
    -- The server's progress wins, so a dropped turn report cannot leave the socket looking finished.
    session.states[index] = progress
    if seized then
        session.pending[index] = 0
        session.seizedUntil = getTickCount() + 1400
        if getTickCount() > (session.soundUntil or 0) then
            session.soundUntil = getTickCount() + 500
            playSoundFrontEnd(4)
        end
    end
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
