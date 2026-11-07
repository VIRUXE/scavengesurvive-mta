-- The driver's dashboard, bottom centre (rules in hud/shared/logic/dashboard.lua): an analog instrument cluster in a
-- dark binnacle. A speedometer dial (with a digital readout) on the left, a tachometer on the right, a fuel gauge and
-- a voltmeter between them over a row of tell-tale lamps, and the ignition barrel outside the hood's left end. The
-- markings are lit by the backlight only while the panel has power; the needles rest at their stops otherwise.
-- It spans y 404..474 on screen; the skill notice moves above it while it shows.
-- ctx = { canvas, c, logic }.
return function(ctx)
    local canvas, c, logic = ctx.canvas, ctx.c, ctx.logic
    local M = {}

    -- design units, anchored on the screen's centre: the cluster is laid out at 212 x 48 and drawn K times that,
    -- scaled about its bottom centre so that edge sits at canvas y BOTTOM, a little clear of the screen's edge
    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 214, 430, 212, 48
    local BASE = Y + H
    M.TOP = BOTTOM - H * K
    local DIAL_R, DIAL_CY = 21, Y + 25
    local SPEEDO_CX, TACHO_CX = X + 38, X + W - 38
    local DIAL_SWEEP = 120 -- degrees either side of straight up
    local SMALL_R, SMALL_CY, SMALL_SWEEP = 12, Y + 27, 55
    local FUEL_CX, VOLT_CX = 302, 338
    local TELL_Y = Y + 40
    local TELL_X = { 287, 303.5, 320, 336.5, 353 }

    -- the ignition switch: a chrome barrel on its own plate left of the hood, the key turning through its positions
    local IGN_CX, IGN_CY = X - 20, Y + H - 17.5
    local IGN_R, IGN_TICK_R = 8.5, 14.5

    local HOOD = tocolor(14, 14, 16, 250)
    local HOOD_RIM = tocolor(58, 58, 62, 250)
    local HOOD_EDGE = tocolor(90, 90, 96, 255)
    local FACE = tocolor(6, 6, 8, 255)
    local CHROME, CHROME_DARK = tocolor(150, 150, 156, 255), tocolor(48, 48, 52, 255)
    local UNLIT_LAMP = tocolor(38, 38, 40, 255)
    local UNLIT_INK = { 70, 70, 72 } -- printed markings with the backlight off
    local LIT_INK = { 236, 232, 220 } -- warm white backlight
    local NEEDLE_LIT, NEEDLE_DARK = { 255, 72, 30 }, { 120, 50, 30 }
    local LCD_BACK = tocolor(10, 16, 12, 255)
    local LCD_INK = { 120, 255, 170 }
    local AMBER = { 0xFF, 0xA8, 0x00 }

    local performance = nil -- { kind = "crank" | "stall", code, vehicle, start }
    local preview = nil -- dashboardPreview overrides of the vehicle's state
    local needle, lastTick, lastVehicle, handling = 0, nil, nil, nil
    local keyAngle, keyVehicle = 0, nil -- the key's shown angle and the vehicle it was set for
    local shown = { speed = 0, fuel = 0, volts = 0 } -- the eased needles of the speedometer and the small gauges
    local speedTop = 160

    local function px(x)
        return canvas.x(c, 320 + (x - 320) * K, "center")
    end

    local function py(y)
        return canvas.y(c, BOTTOM + (y - BASE) * K)
    end

    local function len(u)
        return canvas.len(c, u * K)
    end

    local function rgba(rgb, a)
        return tocolor(rgb[1], rgb[2], rgb[3], math.floor(math.max(0, math.min(255, a)) + 0.5))
    end

    -- the backlit ink: the unlit print blended up to the warm backlight by glow 0..1
    local function ink(glow, rgb)
        local to = rgb or LIT_INK
        local g = math.max(0, math.min(1, glow))
        return tocolor(
            UNLIT_INK[1] + (to[1] - UNLIT_INK[1]) * g,
            UNLIT_INK[2] + (to[2] - UNLIT_INK[2]) * g,
            UNLIT_INK[3] + (to[3] - UNLIT_INK[3]) * g,
            255
        )
    end

    -- text centred on canvas (x, y), letter height ly; font 1 (Tahoma Bold) for the numerals, 2 for the labels
    local function text(s, x, y, colour, ly, font)
        font = font or 1
        local scaleY = canvas.textScale(c, ly * K, font)
        local scaleX = scaleY * canvas.xScale(font, ly * 0.22, ly)
        local h = ly * 10
        dxDrawText(
            s,
            px(x - 20),
            py(y - h / 2),
            px(x + 20),
            py(y + h / 2),
            colour,
            scaleX,
            scaleY,
            canvas.font(font),
            "center",
            "center"
        )
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
            locked = (tonumber(getElementData(vehicle, "vehicles.locked")) or 0) ~= 0,
            health = getElementHealth(vehicle),
            fuel = tonumber(getElementData(vehicle, "vehicles.fuel")) or 0,
            maxFuel = vt and vt.maxFuel or 0,
        }
        for k, v in pairs(preview or {}) do
            s[k] = v
        end
        return s
    end

    -- a new vehicle under the driver: its handling (gears, top speed) and the needles back at rest
    local function track(vehicle)
        if vehicle ~= lastVehicle then
            lastVehicle, handling, needle = vehicle, getVehicleHandling(vehicle), 0
            speedTop = logic.speedScale(handling and handling.maxVelocity)
            shown.speed, shown.fuel, shown.volts = 0, 0, 0
        end
    end

    local function targetRpm(vehicle, s, kmh)
        if not s.engine then
            return 0
        end
        local throttle = getPedControlState(localPlayer, "accelerate")
        local gear = getVehicleCurrentGear(vehicle)
        return logic.rpm(kmh, gear, handling and handling.maxVelocity, handling and handling.numberOfGears, throttle)
    end

    -- canvas-unit primitives
    local function rect(x, y, w, h, colour)
        dxDrawRectangle(px(x), py(y), len(w), len(h), colour)
    end

    local function stroke(x1, y1, x2, y2, colour, width)
        dxDrawLine(px(x1), py(y1), px(x2), py(y2), colour, math.max(1, len(width)))
    end

    local function disc(x, y, r, colour)
        dxDrawCircle(px(x), py(y), len(r), 0, 360, colour, colour, 48)
    end

    local function frame(x, y, w, h, col, t)
        rect(x, y, w, t, col)
        rect(x, y + h - t, w, t, col)
        rect(x, y, t, h, col)
        rect(x + w - t, y, t, h, col)
    end

    -- a dial's geometry: the point at `frac` (0 .. 1 along a sweep of +-`sweep` degrees from straight up), `r` out
    local function polar(cx, cy, sweep, frac, r)
        local a = math.rad(-sweep + 2 * sweep * frac)
        return cx + math.sin(a) * r, cy - math.cos(a) * r
    end

    local function tick(cx, cy, sweep, frac, r1, r2, colour, width)
        local ax, ay = polar(cx, cy, sweep, frac, r1)
        local bx, by = polar(cx, cy, sweep, frac, r2)
        stroke(ax, ay, bx, by, colour, width)
    end

    -- an arc band from f1 to f2 at radius r
    local function arc(cx, cy, sweep, f1, f2, r, colour, width)
        local steps = math.max(2, math.ceil((f2 - f1) * sweep / 6))
        for i = 0, steps - 1 do
            local a, b = f1 + (f2 - f1) * i / steps, f1 + (f2 - f1) * (i + 1) / steps
            local ax, ay = polar(cx, cy, sweep, a, r)
            local bx, by = polar(cx, cy, sweep, b, r)
            stroke(ax, ay, bx, by, colour, width)
        end
    end

    local function needleAt(cx, cy, sweep, frac, reach, tail, width, powered)
        local tx, ty = polar(cx, cy, sweep, frac, reach)
        local sx, sy = polar(cx, cy, sweep, frac, -tail)
        local rgb = powered and NEEDLE_LIT or NEEDLE_DARK
        stroke(sx, sy, tx, ty, rgba(rgb, 255), width)
    end

    local function hub(cx, cy, r)
        disc(cx, cy, r, CHROME_DARK)
        disc(cx, cy, r * 0.55, CHROME)
    end

    -- a big dial's bezel and face
    local function bezel(cx, cy, r)
        disc(cx, cy, r + 1.8, CHROME_DARK)
        disc(cx, cy, r + 1.1, CHROME)
        disc(cx, cy, r + 0.4, CHROME_DARK)
        disc(cx, cy, r, FACE)
    end

    -- a car battery: the case outline, two terminal posts on top, a + and a - on its face
    local function batteryIcon(cx, cy, col)
        local x, y, w, h, t = cx - 5.5, cy - 2.2, 11, 6.6, 0.9
        frame(x, y, w, h, col, t)
        rect(x + 1.6, y - 1.5, 2.2, 1.5, col)
        rect(x + w - 3.8, y - 1.5, 2.2, 1.5, col)
        rect(x + 2, y + 3.0, 2.4, 0.8, col) -- the minus
        rect(x + w - 4.4, y + 3.0, 2.4, 0.8, col) -- the plus: bar and upright
        rect(x + w - 3.6, y + 2.2, 0.8, 2.4, col)
    end

    -- the check-engine symbol: an engine seen from the side in outline, the air cleaner on its stem over the intake,
    -- the block with two cylinders, the fan end on the left, the exhaust end on the right, the oil pan under it
    local function engineIcon(cx, cy, col)
        local t = 0.8
        rect(cx - 2.6, cy - 4.8, 3.6, t, col) -- air cleaner
        rect(cx - 0.9, cy - 4.0, t, 1.2, col) -- its stem
        frame(cx - 3.2, cy - 2.9, 5.6, 2.3, col, t) -- intake manifold
        frame(cx - 4.2, cy - 1.0, 8.4, 4.6, col, t) -- block
        rect(cx - 1.5, cy + 0.2, t, 2.4, col) -- cylinders
        rect(cx + 1.2, cy + 0.2, t, 2.4, col)
        frame(cx - 6.4, cy + 0.2, 2.2, 2.8, col, t) -- fan end
        rect(cx - 7.4, cy + 1.2, 1.0, t, col) -- its shaft
        frame(cx + 4.2, cy + 0.6, 2.0, 3.0, col, t) -- exhaust end
        frame(cx - 3.0, cy + 3.6, 6.0, 1.3, col, t) -- oil pan
    end

    -- a headlamp: the rounded lens on the right, three beams streaming left
    local function lightIcon(cx, cy, col)
        local rx, ry, steps = 3.6, 4.2, 10
        for i = 0, steps - 1 do
            local u = (i + 0.5) / steps
            local half = ry * math.sqrt(1 - u * u)
            rect(cx - 0.6 + u * rx, cy - half, rx / steps + 0.15, half * 2, col)
        end
        rect(cx - 1.3, cy - ry, 0.8, ry * 2, col) -- the flat back of the lens
        for k = -1, 1 do
            stroke(cx - 2.4, cy + k * 2.6, cx - 6.4, cy + k * 2.6 + 0.9, col, 0.8)
        end
    end

    -- a side-on car door: the roofline, the stepped A-pillar over the window, the sill, the lower panel and a handle
    local function doorIcon(cx, cy, col)
        local x, y, t = cx - 4.2, cy - 4.5, 0.8
        rect(x + 2.2, y, 6.2, t, col)
        rect(x + 7.6, y, t, 9, col)
        rect(x, y + 8.2, 8.4, t, col)
        rect(x, y + 2.8, t, 6.4, col)
        rect(x, y + 3.6, 8.4, t, col)
        rect(x + 1.7, y + 0.8, t, 1.1, col)
        rect(x + 0.9, y + 1.9, t, 1.0, col)
        rect(x + 2.0, y + 5.8, 2.8, t, col)
    end

    -- a fuel pump: the column with its window, the base, the hose hooked over the side to the nozzle
    local function fuelIcon(cx, cy, col)
        local t = 0.8
        frame(cx - 3.6, cy - 4.4, 5.2, 8.6, col, t)
        rect(cx - 2.8, cy - 3.6, 3.6, 2.4, col) -- the window
        rect(cx - 4.6, cy + 4.2, 7.2, t, col) -- the base
        rect(cx + 1.6, cy - 1.6, 1.6, t, col) -- the hose out of the column
        rect(cx + 2.8, cy - 1.6, t, 4.2, col) -- down the side
        rect(cx + 2.8, cy - 3.8, t, 1.6, col) -- the nozzle hung up top
        rect(cx + 1.8, cy - 4.4, 1.8, t, col)
    end

    local ICONS = { bat = batteryIcon, chk = engineIcon, lgt = lightIcon, dor = doorIcon, fuel = fuelIcon }
    -- the tell-tale row, left to right
    local TELLTALES = { logic.LAMPS[1], logic.LAMPS[2], logic.FUEL_LAMP, logic.LAMPS[3], logic.LAMPS[4] }

    -- whether a lamp shows lit now and in which colour, with a performance's `shot` (or nil) laid over its state
    local function lampShows(lamp, st, shot, powered, glow, now)
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
        return on and powered and glow > 0, rgb
    end

    local function drawTelltales(s, shot, powered, glow, now)
        local lamps = logic.lamps(s)
        for i, lamp in ipairs(TELLTALES) do
            local on, rgb = lampShows(lamp, lamps[lamp.key], shot, powered, glow, now)
            local x = TELL_X[i]
            if on then
                disc(x, TELL_Y, 6, rgba(rgb, 40 * glow)) -- the glow bleeding round the symbol
                ICONS[lamp.key](x, TELL_Y, rgba(rgb, 255 * math.max(0.5, glow)))
            else
                ICONS[lamp.key](x, TELL_Y, UNLIT_LAMP)
            end
        end
    end

    -- the binnacle: a stadium-shaped hood with a lighter rim and a bright lip along its top edge
    local function drawHood()
        local r = H / 2
        disc(X + r, Y + r, r + 1, HOOD_RIM)
        disc(X + W - r, Y + r, r + 1, HOOD_RIM)
        rect(X + r, Y - 1, W - 2 * r, H + 2, HOOD_RIM)
        disc(X + r, Y + r, r, HOOD)
        disc(X + W - r, Y + r, r, HOOD)
        rect(X + r, Y, W - 2 * r, H, HOOD)
        rect(X + r, Y - 1, W - 2 * r, 0.5, HOOD_EDGE)
    end

    -- the speedometer: 0 .. speedTop km/h over 240 degrees, numbered every major step, with an LCD under the pivot
    local function drawSpeedo(kmh, powered, glow)
        local cx, cy, r = SPEEDO_CX, DIAL_CY, DIAL_R
        bezel(cx, cy, r)
        local major = logic.speedStep(speedTop)
        local col = ink(glow)
        local steps = speedTop / (major / 4)
        for i = 0, steps do
            local frac = i / steps
            if i % 4 == 0 then
                tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 4, col, 0.8)
                local lx, ly = polar(cx, cy, DIAL_SWEEP, frac, r - 7.6)
                text(tostring(math.floor(frac * speedTop + 0.5)), lx, ly, col, 0.5)
            elseif i % 2 == 0 then
                tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2.8, col, 0.5)
            else
                tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2, col, 0.4)
            end
        end
        text("km/h", cx, cy - 6, col, 0.42, 2)
        -- the LCD: the speed in digits, dark with the panel off
        rect(cx - 6.5, cy + 6, 13, 5.6, LCD_BACK)
        if powered then
            text(string.format("%d", math.floor(kmh + 0.5)), cx, cy + 8.9, rgba(LCD_INK, 255 * glow), 0.55)
        end
        needleAt(cx, cy, DIAL_SWEEP, shown.speed / speedTop, r - 2, 3.5, 1.1, powered)
        hub(cx, cy, 2.4)
    end

    -- the tachometer: 0 .. MAX_RPM, a number every thousand, the red zone from the redline
    local function drawTacho(powered, glow)
        local cx, cy, r = TACHO_CX, DIAL_CY, DIAL_R
        bezel(cx, cy, r)
        local col = ink(glow)
        arc(cx, cy, DIAL_SWEEP, logic.REDLINE, 1, r - 1.6, ink(glow, logic.RED), 1.8)
        local thousands = logic.MAX_RPM / 1000
        for i = 0, thousands * 4 do
            local frac = i / (thousands * 4)
            local red = frac >= logic.REDLINE
            local tc = red and ink(glow, logic.RED) or col
            if i % 4 == 0 then
                tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 4, tc, 0.8)
                local lx, ly = polar(cx, cy, DIAL_SWEEP, frac, r - 7.6)
                text(tostring(i / 4), lx, ly, tc, 0.6)
            elseif i % 2 == 0 then
                tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2.8, tc, 0.5)
            end
        end
        text("x1000", cx, cy - 6, col, 0.42, 2)
        text("RPM", cx, cy + 8.5, col, 0.46, 2)
        local frac = math.max(0, math.min(1, needle / logic.MAX_RPM))
        needleAt(cx, cy, DIAL_SWEEP, powered and frac or 0, r - 2, 3.5, 1.1, powered)
        hub(cx, cy, 2.4)
    end

    -- a small gauge between the dials: a 110 degree scale, its low end red over `redTo`, labels at both ends
    local function drawSmall(cx, frac, lowLabel, highLabel, name, redTo, powered, glow)
        local cy, r = SMALL_CY, SMALL_R
        local col, red = ink(glow), ink(glow, logic.RED)
        arc(cx, cy, SMALL_SWEEP, 0, redTo, r, red, 0.6)
        arc(cx, cy, SMALL_SWEEP, redTo, 1, r, col, 0.6)
        for i = 0, 4 do
            local f = i / 4
            tick(cx, cy, SMALL_SWEEP, f, r, r - (i % 2 == 0 and 3 or 1.8), f < redTo and red or col, 0.6)
        end
        -- the end labels just under the arc's ends and the name under the pivot, clear of the needle's sweep
        local lx, ly = polar(cx, cy, SMALL_SWEEP, 0, r)
        text(lowLabel, lx - 0.6, ly + 4, red, 0.44, 2)
        local hx, hy = polar(cx, cy, SMALL_SWEEP, 1, r)
        text(highLabel, hx + 0.6, hy + 4, col, 0.44, 2)
        text(name, cx, cy + 4.6, col, 0.36, 2)
        needleAt(cx, cy, SMALL_SWEEP, frac, r - 1.5, 2, 0.8, powered)
        hub(cx, cy, 1.5)
    end

    -- the ignition cylinder: the three positions as ticks (the one the key is in lit, green for ACC with the engine
    -- running), the key pointing at the angle
    local TICK = {
        off = { 170, 170, 170 },
        acc = AMBER,
        start = { 0xFF, 0x22, 0x22 },
    }
    local RUNNING = { 0x33, 0xFF, 0x33 } -- the ACC tick while the engine runs
    local KEY = tocolor(235, 200, 95, 255) -- the key's brass bow
    local KEY_EDGE = tocolor(110, 85, 30, 255)
    local KEY_SHINE = tocolor(255, 240, 190, 255)
    local SLOT = tocolor(0, 0, 0, 255)

    local function drawIgnition(pos, angle, running)
        local cx, cy = IGN_CX, IGN_CY
        disc(cx, cy, IGN_TICK_R + 3, HOOD_RIM)
        disc(cx, cy, IGN_TICK_R + 2.4, HOOD)
        for _, name in ipairs(logic.KEY_ORDER) do
            local a = math.rad(logic.KEY_ANGLES[name])
            local lit = name == pos
            disc(
                cx + math.sin(a) * IGN_TICK_R,
                cy - math.cos(a) * IGN_TICK_R,
                lit and 1.5 or 1.1,
                lit and rgba(running and name == "acc" and RUNNING or TICK[name], 255) or UNLIT_LAMP
            )
        end
        disc(cx, cy, IGN_R + 0.6, CHROME_DARK)
        disc(cx, cy, IGN_R, CHROME)
        disc(cx, cy, IGN_R - 1.4, CHROME_DARK)
        -- key out (OFF, once it has turned back there): the bare cylinder with its black keyway at the OFF angle
        local out = pos == "off" and math.abs(angle - logic.KEY_ANGLES.off) < 1
        if out then
            local o = math.rad(logic.KEY_ANGLES.off)
            local ox, oy = math.sin(o), -math.cos(o)
            stroke(
                cx - ox * (IGN_R - 2.6),
                cy - oy * (IGN_R - 2.6),
                cx + ox * (IGN_R - 2.6),
                cy + oy * (IGN_R - 2.6),
                SLOT,
                1.6
            )
            return
        end
        -- key in: its brass bow across the barrel, overhanging it, turning with the key; the ring hole at the
        -- end that points at the position
        local a = math.rad(angle)
        local dx, dy = math.sin(a), -math.cos(a)
        local tipX, tipY = cx + dx * (IGN_R + 1.5), cy + dy * (IGN_R + 1.5)
        local tailX, tailY = cx - dx * (IGN_R - 1), cy - dy * (IGN_R - 1)
        stroke(tailX, tailY, tipX, tipY, KEY_EDGE, 6)
        disc(tipX, tipY, 3, KEY_EDGE)
        disc(tailX, tailY, 3, KEY_EDGE)
        stroke(tailX, tailY, tipX, tipY, KEY, 4.6)
        disc(tipX, tipY, 2.3, KEY)
        disc(tailX, tailY, 2.3, KEY)
        stroke(tailX + dy * 1, tailY - dx * 1, tipX + dy * 1, tipY - dx * 1, KEY_SHINE, 0.6) -- light along one edge
        disc(tipX - dx * 0.6, tipY - dy * 0.6, 1.1, HOOD) -- the ring hole
    end

    local function ease(current, target, dt, ms)
        return current + (target - current) * math.min(1, dt / ms)
    end

    -- the dashboard of `vehicle` (vt: its data vehicle type) for its driver; every frame
    function M.draw(vehicle, vt)
        local now = getTickCount()
        local dt = lastTick and math.max(0, math.min(100, now - lastTick)) or 0
        lastTick = now
        track(vehicle)
        local s = stateOf(vehicle, vt)
        local powered = logic.powered(s)
        local shot = nil
        if performance and performance.vehicle == vehicle then
            shot = logic.sample(performance, now - performance.start, math.random)
        end
        if not shot then
            performance = nil
        end
        local glow = powered and (s.engine and 1 or 0.75) or 0
        if shot and (shot.bulb or shot.rpm) then
            glow = powered and 1 or 0 -- the key is turned: full backlight while the starter runs
        end
        if shot and shot.glow then
            glow = powered and shot.glow or 0
        end
        local kmh = logic.kmh(getElementVelocity(vehicle))
        local target = targetRpm(vehicle, s, kmh)
        if shot and shot.rpm then
            needle = shot.rpm
        else
            needle = logic.needle(needle, target, dt)
        end
        local volts = shot and shot.volts or logic.volts(s)
        shown.speed = ease(shown.speed, powered and math.min(kmh, speedTop) or 0, dt, 120)
        shown.fuel = ease(shown.fuel, powered and logic.fuelShare(s.fuel, s.maxFuel) or 0, dt, 350)
        shown.volts = ease(shown.volts, logic.voltShare(volts), dt, shot and 60 or 250)

        drawHood()
        drawSpeedo(kmh, powered, glow)
        drawTacho(powered, glow)
        drawSmall(FUEL_CX, shown.fuel, "E", "F", "FUEL", 0.125, powered, glow)
        drawSmall(VOLT_CX, shown.volts, "8", "16", "VOLT", logic.voltShare(logic.VOLTS_LOW), powered, glow)
        drawTelltales(s, shot, powered, glow, now)

        local pos = logic.keyPosition(s, shot)
        local keyTarget = logic.KEY_ANGLES[pos]
        if vehicle ~= keyVehicle then
            keyVehicle, keyAngle = vehicle, keyTarget -- the key is already where it is on getting in
        end
        keyAngle = logic.keyStep(keyAngle, keyTarget, dt)
        drawIgnition(pos, keyAngle, s.engine)
    end

    -- dev preview: overrides (a table of state fields: battery, bay, engine, acc, lights, locked, health, fuel,
    -- maxFuel) replace the vehicle's own until cleared with false (nil keeps them); kind "crank" | "stall" with a
    -- code plays that performance on the vehicle driven, as if vehicles had sent it
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
