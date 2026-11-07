-- The driver's dashboard, bottom centre (rules in hud/shared/logic/dashboard.lua): a translucent black strip in the
-- HUD's style, the warning lamps in Bank Gothic as the vehicle panel's rows, a segmented tachometer and a voltmeter.
-- It sits under the skill notice (y 430) and the overheat bar (380..400), clear of the action text and tips.
-- ctx = { canvas, c, logic }.
return function(ctx)
    local canvas, c, logic = ctx.canvas, ctx.c, ctx.logic
    local M = {}

    -- canvas units, anchored on the screen's centre
    local X, Y, W, H = 236, 445, 168, 30
    local PAD = 4
    local LAMP_Y, LAMP_H = Y + 4, 11
    local GAUGE_Y, GAUGE_H = Y + 19, 7
    local TACHO_X, TACHO_W, SEGMENTS = X + 26, 88, 22

    -- the ignition switch: a square cell of its own to the left of the strip, the key turning through four positions
    local IGN_X = X - H - 4
    local IGN_R, IGN_TICK_R = 8, 12

    local BACK = tocolor(0, 0, 0, 170)
    local FRAME = tocolor(70, 70, 70, 200)
    local UNLIT_BOX = tocolor(28, 28, 28, 220)
    local UNLIT_TEXT = tocolor(75, 75, 75, 255)
    local UNLIT_SEGMENT = tocolor(50, 50, 50, 220)
    local AMBER = { 0xFF, 0xA8, 0x00 }

    local performance = nil -- { kind = "crank" | "stall", code, vehicle, start }
    local preview = nil -- dashboardPreview overrides of the vehicle's state
    local needle, lastTick, lastVehicle, handling = 0, nil, nil, nil
    local keyAngle, keyVehicle = 0, nil -- the key's shown angle and the vehicle it was set for

    local function px(x)
        return canvas.x(c, x, "center")
    end

    local function label(text, x, y, w, h, colour, ly, align)
        local scaleY = canvas.textScale(c, ly, 2)
        local scaleX = scaleY * canvas.xScale(2, ly * 0.2, ly)
        local top, bottom = canvas.y(c, y), canvas.y(c, y + h)
        dxDrawText(text, px(x), top, px(x + w), bottom, colour, scaleX, scaleY, "bankgothic", align, "center")
    end

    local function rgba(rgb, a)
        return tocolor(rgb[1], rgb[2], rgb[3], math.floor(math.max(0, math.min(255, a)) + 0.5))
    end

    local SOUND_VOLUME = 0.8
    local performanceSound = nil -- the sound of the performance playing, cut short when a new one starts

    local function cutSound()
        if isElement(performanceSound) then
            stopSound(performanceSound)
        end
        performanceSound = nil
    end

    local function perform(kind, vehicle, code)
        if not isElement(vehicle) or vehicle ~= getPedOccupiedVehicle(localPlayer) then
            return
        end
        performance = { kind = kind, code = code or nil, vehicle = vehicle, start = getTickCount() }
        cutSound()
        local name = logic.soundFor(performance)
        if name then
            performanceSound = playSound("sounds/" .. name .. ".wav", false)
            if performanceSound then
                setSoundVolume(performanceSound, SOUND_VOLUME)
            end
        end
    end

    -- getting out cuts the key's sound off with the dashboard
    addEventHandler("onClientPlayerVehicleExit", localPlayer, cutSound)

    -- vehicles: the driver turned the key (code false: it started) or the engine died under them
    addEventHandler("engineCranked", root, function(code)
        perform("crank", source, code)
    end)
    addEventHandler("engineStalled", root, function(code)
        perform("stall", source, code)
    end)

    local function stateOf(vehicle, vt)
        local s = {
            bay = getElementData(vehicle, "vehicles.bay") == true,
            battery = tonumber(getElementData(vehicle, "vehicles.battery")),
            engine = getVehicleEngineState(vehicle),
            acc = getElementData(vehicle, "vehicles.acc") == true,
            lights = getVehicleOverrideLights(vehicle) == 2,
            health = getElementHealth(vehicle),
            fuel = tonumber(getElementData(vehicle, "vehicles.fuel")) or 0,
            maxFuel = vt and vt.maxFuel or 0,
        }
        for k, v in pairs(preview or {}) do
            s[k] = v
        end
        return s
    end

    local function targetRpm(vehicle, s)
        if not s.engine then
            return 0
        end
        if vehicle ~= lastVehicle then
            lastVehicle, handling, needle = vehicle, getVehicleHandling(vehicle), 0
        end
        local vx, vy, vz = getElementVelocity(vehicle)
        local kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
        local throttle = getPedControlState(localPlayer, "accelerate")
        local gear = getVehicleCurrentGear(vehicle)
        return logic.rpm(kmh, gear, handling and handling.maxVelocity, handling and handling.numberOfGears, throttle)
    end

    local function drawLamps(s, shot, powered, glow, now)
        local lamps = logic.lamps(s)
        local cell = (W - 2 * PAD) / #logic.LAMPS
        for i, lamp in ipairs(logic.LAMPS) do
            local st = lamps[lamp.key]
            local on = logic.lit(st.mode, now)
            local rgb = st.colour or lamp.colour
            if shot then
                if shot.bulb or (shot.solid and shot.solid[lamp.key]) then
                    on = true
                end
                if shot.flash == lamp.key then
                    on, rgb = logic.lit("fast", now), logic.RED
                end
            end
            on = on and powered and glow > 0
            local x = X + PAD + (i - 1) * cell + 1
            local w = cell - 2
            if on then
                dxDrawRectangle(
                    px(x),
                    canvas.y(c, LAMP_Y),
                    canvas.len(c, w),
                    canvas.len(c, LAMP_H),
                    rgba(rgb, 70 * glow)
                )
                label(lamp.label, x, LAMP_Y, w, LAMP_H, rgba(rgb, 255 * glow), 0.95, "center")
            else
                dxDrawRectangle(px(x), canvas.y(c, LAMP_Y), canvas.len(c, w), canvas.len(c, LAMP_H), UNLIT_BOX)
                label(lamp.label, x, LAMP_Y, w, LAMP_H, UNLIT_TEXT, 0.95, "center")
            end
        end
    end

    local function drawTacho(powered, glow)
        label("RPM", X + PAD, GAUGE_Y, 22, GAUGE_H, powered and rgba({ 200, 200, 200 }, 255 * glow) or UNLIT_TEXT, 0.8)
        local frac = math.max(0, math.min(1, needle / logic.MAX_RPM))
        local lit = powered and math.floor(frac * SEGMENTS + 0.5) or 0
        local step = TACHO_W / SEGMENTS
        for i = 1, SEGMENTS do
            local share = i / SEGMENTS
            local h = 2.5 + (GAUGE_H - 2.5) * share
            local colour = UNLIT_SEGMENT
            if i <= lit then
                local rgb = share > logic.REDLINE and logic.RED or share > 0.65 and AMBER or { 235, 235, 235 }
                colour = rgba(rgb, 255 * glow)
            end
            local x = TACHO_X + (i - 1) * step
            dxDrawRectangle(
                px(x),
                canvas.y(c, GAUGE_Y + GAUGE_H - h),
                canvas.len(c, step - 1),
                canvas.len(c, h),
                colour
            )
        end
    end

    local function drawVolts(volts, powered, glow)
        local x = TACHO_X + TACHO_W + 2
        local w = X + W - PAD - x
        if not powered then
            return label("--.-V", x, GAUGE_Y, w, GAUGE_H, UNLIT_TEXT, 1.0, "right")
        end
        local rgb = volts < 11.0 and logic.RED or volts < 11.9 and AMBER or { 255, 255, 255 }
        label(string.format("%.1fV", volts), x, GAUGE_Y, w, GAUGE_H, rgba(rgb, 255 * glow), 1.0, "right")
    end

    local TICK = {
        off = { 170, 170, 170 },
        acc = AMBER,
        on = { 0x33, 0xFF, 0x33 },
        start = { 0xFF, 0x22, 0x22 },
    }
    local METAL, METAL_INNER = tocolor(95, 95, 95, 230), tocolor(30, 30, 30, 240)
    local KEY, KEY_TAIL = tocolor(228, 205, 130, 255), tocolor(150, 135, 85, 255)

    -- a little circle at canvas (x, y) with radius r canvas units
    local function disc(x, y, r, colour)
        dxDrawCircle(px(x), canvas.y(c, y), canvas.len(c, r), 0, 360, colour, colour, 24)
    end

    -- the ignition cylinder: the four positions as ticks (the one the key is in lit), the key pointing at the angle
    local function drawIgnition(pos, angle)
        local cx, cy = IGN_X + H / 2, Y + H / 2
        local x0, y0 = px(IGN_X), canvas.y(c, Y)
        local w, h = canvas.len(c, H), canvas.len(c, H)
        dxDrawRectangle(x0, y0, w, h, BACK)
        dxDrawLine(x0, y0, x0 + w, y0, FRAME)
        dxDrawLine(x0, y0 + h, x0 + w, y0 + h, FRAME)
        dxDrawLine(x0, y0, x0, y0 + h, FRAME)
        dxDrawLine(x0 + w, y0, x0 + w, y0 + h, FRAME)
        for _, name in ipairs(logic.KEY_ORDER) do
            local a = math.rad(logic.KEY_ANGLES[name])
            local lit = name == pos
            disc(
                cx + math.sin(a) * IGN_TICK_R,
                cy - math.cos(a) * IGN_TICK_R,
                lit and 1.7 or 1.2,
                lit and rgba(TICK[name], 255) or UNLIT_SEGMENT
            )
        end
        disc(cx, cy, IGN_R, METAL)
        disc(cx, cy, IGN_R - 1.3, METAL_INNER)
        local a = math.rad(angle)
        local dx, dy = math.sin(a), -math.cos(a)
        local width = math.max(1, canvas.len(c, 2.2))
        dxDrawLine(px(cx), canvas.y(c, cy), px(cx - dx * 3), canvas.y(c, cy - dy * 3), KEY_TAIL, width)
        dxDrawLine(
            px(cx),
            canvas.y(c, cy),
            px(cx + dx * (IGN_R - 1.8)),
            canvas.y(c, cy + dy * (IGN_R - 1.8)),
            KEY,
            width
        )
        disc(cx, cy, 1.3, METAL)
    end

    -- the dashboard of `vehicle` (vt: its data vehicle type) for its driver; every frame
    function M.draw(vehicle, vt)
        local now = getTickCount()
        local dt = lastTick and math.max(0, math.min(100, now - lastTick)) or 0
        lastTick = now
        local s = stateOf(vehicle, vt)
        local powered = logic.powered(s)
        local shot = nil
        if performance and performance.vehicle == vehicle then
            shot = logic.sample(performance, now - performance.start, math.random)
        end
        if not shot then
            performance = nil
        end
        local glow = powered and (s.engine and 1 or 0.6) or 0
        if shot and (shot.bulb or shot.rpm) then
            glow = powered and 1 or 0 -- the key is turned: full backlight while the starter runs
        end
        if shot and shot.glow then
            glow = powered and shot.glow or 0
        end
        local target = targetRpm(vehicle, s)
        if shot and shot.rpm then
            needle = shot.rpm
        else
            needle = logic.needle(needle, target, dt)
        end
        local volts = shot and shot.volts or logic.volts(s)

        local x0, y0 = px(X), canvas.y(c, Y)
        local w, h = canvas.len(c, W), canvas.len(c, H)
        dxDrawRectangle(x0, y0, w, h, BACK)
        dxDrawLine(x0, y0, x0 + w, y0, FRAME)
        dxDrawLine(x0, y0 + h, x0 + w, y0 + h, FRAME)
        dxDrawLine(x0, y0, x0, y0 + h, FRAME)
        dxDrawLine(x0 + w, y0, x0 + w, y0 + h, FRAME)
        drawLamps(s, shot, powered, glow, now)
        drawTacho(powered, glow)
        drawVolts(volts, powered, glow)

        local pos = logic.keyPosition(s, shot)
        local keyTarget = logic.KEY_ANGLES[pos]
        if vehicle ~= keyVehicle then
            keyVehicle, keyAngle = vehicle, keyTarget -- the key is already where it is on getting in
        end
        keyAngle = logic.keyStep(keyAngle, keyTarget, dt)
        drawIgnition(pos, keyAngle)
    end

    -- dev preview: overrides (a table of state fields: battery, bay, engine, acc, lights, health, fuel, maxFuel)
    -- replace the vehicle's own until cleared with false (nil keeps them); kind "crank" | "stall" with a code plays
    -- that performance on the vehicle driven, as if vehicles had sent it
    function M.preview(overrides, kind, code)
        if overrides == false then
            preview = nil
        elseif type(overrides) == "table" then
            preview = overrides
        end
        if kind == "crank" or kind == "stall" then
            perform(kind, getPedOccupiedVehicle(localPlayer), code)
        end
        return true
    end

    return M
end
