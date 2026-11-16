-- The driver's dashboard, bottom centre (rules in hud/shared/logic/dashboard.lua). Each class of vehicle has a
-- design of its own in client/dashboards/<name>.lua (logic.design picks it): the car's analog cluster, a sports
-- cluster, a motorbike's pods, a boat's console and the panels of a helicopter and a plane. This file is what they
-- share: the vehicle's state, the key's performances and sounds, the eased needles and a kit of drawing parts
-- (dials, needles, lamps, the ignition barrel, an artificial horizon, a heading tape).
-- A design is `function(kit) return { top = <canvas y of its top edge>, draw = function(f) end } end`; f is the
-- frame built in M.draw. The skill notice moves above `top` while a dashboard shows.
-- ctx = { canvas, c, logic, load }.
return function(ctx)
    local canvas, c, logic = ctx.canvas, ctx.c, ctx.logic
    local M = {}

    local DESIGNS = { "standard", "sports", "motorbike", "boat", "helicopter", "plane" }

    -- the ignition switch: a chrome barrel on its own plate, the key turning through its positions
    local IGN_R, IGN_TICK_R = 8.5, 14.5

    local P = {
        HOOD = tocolor(14, 14, 16, 250),
        HOOD_RIM = tocolor(58, 58, 62, 250),
        HOOD_EDGE = tocolor(90, 90, 96, 255),
        FACE = tocolor(6, 6, 8, 255),
        CHROME = tocolor(150, 150, 156, 255),
        CHROME_DARK = tocolor(48, 48, 52, 255),
        UNLIT_LAMP = tocolor(38, 38, 40, 255),
        UNLIT_INK = { 70, 70, 72 }, -- printed markings with the backlight off
        LIT_INK = { 236, 232, 220 }, -- warm white backlight
        NEEDLE_LIT = { 255, 72, 30 },
        NEEDLE_DARK = { 120, 50, 30 },
        LCD_BACK = tocolor(10, 16, 12, 255),
        LCD_INK = { 120, 255, 170 },
        AMBER = { 0xFF, 0xA8, 0x00 },
        GREEN = { 0x33, 0xFF, 0x33 },
        RED = logic.RED,
        SKY = { 60, 130, 210 },
        GROUND = { 120, 78, 40 },
    }
    local TICK = { off = { 170, 170, 170 }, acc = P.AMBER, start = { 0xFF, 0x22, 0x22 } }
    local KEY = tocolor(235, 200, 95, 255) -- the key's brass bow
    local KEY_EDGE = tocolor(110, 85, 30, 255)
    local KEY_SHINE = tocolor(255, 240, 190, 255)
    local SLOT = tocolor(0, 0, 0, 255)

    local LAMP = { fuel = logic.FUEL_LAMP }
    for _, lamp in ipairs(logic.LAMPS) do
        LAMP[lamp.key] = lamp
    end

    local performance = nil -- { kind = "crank" | "stall", code, vehicle, start }
    local preview = nil -- dashboardPreview overrides of the vehicle's state
    local needle, lastTick, lastVehicle, handling = 0, nil, nil, nil
    local keyAngle, keyVehicle = 0, nil -- the key's shown angle and the vehicle it was set for
    local shown = { speed = 0, fuel = 0, volts = 0 } -- the eased needles of the speedometer and the small gauges
    local speedTop = 160

    local function rgba(rgb, a)
        return tocolor(rgb[1], rgb[2], rgb[3], math.floor(math.max(0, math.min(255, a)) + 0.5))
    end

    -- the colour `from` blended up to `to` by glow 0..1
    local function blend(glow, to, from)
        local g = math.max(0, math.min(1, glow))
        return tocolor(
            from[1] + (to[1] - from[1]) * g,
            from[2] + (to[2] - from[2]) * g,
            from[3] + (to[3] - from[3]) * g,
            255
        )
    end

    -- the backlit ink: the unlit print blended up to the warm backlight (or `rgb`) by glow 0..1
    local function ink(glow, rgb)
        return blend(glow, rgb or P.LIT_INK, P.UNLIT_INK)
    end

    local function ease(current, target, dt, ms)
        return current + (target - current) * math.min(1, dt / ms)
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
    -- vehicles: the lights were asked for on a dead battery: a relay click (the dim flicker is the server's)
    addEventHandler("lightsFlickered", root, function()
        if source ~= getPedOccupiedVehicle(localPlayer) then
            return
        end
        local click = playSound("sounds/crank_dead.wav", false)
        if click then
            setSoundVolume(click, SOUND_VOLUME)
        end
    end)
    addEventHandler("engineStalled", root, function(code)
        perform("stall", source, code)
    end)

    local function stateOf(vehicle, vt)
        local kind = getVehicleType(vehicle)
        local matrix = getElementMatrix(vehicle)
        local _, _, z = getElementPosition(vehicle)
        local vx, vy, vz = getElementVelocity(vehicle)
        local pitch, roll, heading = logic.attitude(matrix[1], matrix[2], matrix[3])
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
            kmh = logic.kmh(vx, vy, vz),
            -- what the flight and marine instruments read
            pitch = pitch,
            roll = roll,
            heading = heading,
            altitude = logic.feet(z),
            climb = logic.verticalFpm(vz),
            rotor = kind == "Helicopter" and logic.rotorShare(getHelicopterRotorSpeed(vehicle)) or 0,
            gearDown = kind ~= "Plane" or getVehicleLandingGearDown(vehicle) ~= false,
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
            return true
        end
        return false
    end

    local function targetRpm(vehicle, s)
        if not s.engine then
            return 0
        end
        local throttle = getPedControlState(localPlayer, "accelerate")
        local gear = getVehicleCurrentGear(vehicle)
        return logic.rpm(s.kmh, gear, handling and handling.maxVelocity, handling and handling.numberOfGears, throttle)
    end

    -- The drawing parts in a design's own units: a design is laid out about canvas x 320 at its natural size and
    -- drawn K times that, scaled about its bottom centre so that its edge `base` sits at canvas y `bottom`.
    local function layout(K, bottom, base)
        local L = {}

        local function px(x)
            return canvas.x(c, 320 + (x - 320) * K, "center")
        end

        local function py(y)
            return canvas.y(c, bottom + (y - base) * K)
        end

        local function len(u)
            return canvas.len(c, u * K)
        end

        -- text centred on (x, y), letter height ly; font 1 (Tahoma Bold) for the numerals, 2 for the labels
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

        -- the point `r` out from (cx, cy) at `deg` degrees clockwise from straight up
        local function at(cx, cy, deg, r)
            local a = math.rad(deg)
            return cx + math.sin(a) * r, cy - math.cos(a) * r
        end

        -- a dial's geometry: the point at `frac` (0 .. 1 along a sweep of +-`sweep` degrees from straight up)
        local function polar(cx, cy, sweep, frac, r)
            return at(cx, cy, -sweep + 2 * sweep * frac, r)
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

        -- a hand from `tail` behind the pivot out to `reach`, pointing `deg` clockwise from straight up
        local function hand(cx, cy, deg, reach, tail, width, colour)
            local tx, ty = at(cx, cy, deg, reach)
            local sx, sy = at(cx, cy, deg, -tail)
            stroke(sx, sy, tx, ty, colour, width)
        end

        local function needleAt(cx, cy, sweep, frac, reach, tail, width, powered, rgb)
            hand(
                cx,
                cy,
                -sweep + 2 * sweep * frac,
                reach,
                tail,
                width,
                rgba(powered and (rgb or P.NEEDLE_LIT) or P.NEEDLE_DARK, 255)
            )
        end

        local function hub(cx, cy, r)
            disc(cx, cy, r, P.CHROME_DARK)
            disc(cx, cy, r * 0.55, P.CHROME)
        end

        -- a dial's bezel and face
        local function bezel(cx, cy, r, face, ring)
            disc(cx, cy, r + 1.8, P.CHROME_DARK)
            disc(cx, cy, r + 1.1, ring or P.CHROME)
            disc(cx, cy, r + 0.4, P.CHROME_DARK)
            disc(cx, cy, r, face or P.FACE)
        end

        -- a dial's markings: 0 .. top over +-sweep degrees, a numbered tick every `major` (printed divided by
        -- `div`), `minors` divisions between them; `size` scales the ticks for a dial of another radius than 21
        local function scale(cx, cy, r, sweep, top, major, minors, col, ly, div)
            local size = r / 21
            local steps = top / major * minors
            for i = 0, steps do
                local frac = i / steps
                if i % minors == 0 then
                    tick(cx, cy, sweep, frac, r - 0.8, r - 4 * size, col, 0.8)
                    local lx, lyy = polar(cx, cy, sweep, frac, r - 7.6 * size)
                    text(tostring(math.floor(frac * top / (div or 1) + 0.5)), lx, lyy, col, ly)
                else
                    tick(cx, cy, sweep, frac, r - 0.8, r - 2.4 * size, col, 0.5)
                end
            end
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

        -- the check-engine symbol: an engine seen from the side in outline, the air cleaner on its stem over the
        -- intake, the block with two cylinders, the fan end on the left, the exhaust end on the right, the oil pan
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

        -- a side-on car door: the roofline, the stepped A-pillar over the window, the sill, the lower panel, a handle
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

        -- whether lamp `key` shows lit in frame f and in which colour, a performance's shot laid over its state
        local function lampShows(f, key)
            local lamp, st, shot = LAMP[key], f.lamps[key], f.shot
            local on = logic.lit(st.mode, f.now)
            local rgb = st.colour or lamp.colour
            if shot then
                if shot.bulb or (shot.solid and shot.solid[key]) then
                    on = true
                end
                if shot.flash == key then
                    on, rgb = logic.lit("fast", f.now), logic.RED
                end
            end
            return on and f.powered and f.glow > 0, rgb
        end

        -- a row of tell-tale symbols: lamp `keys` at the x positions `xs`
        local function telltales(f, keys, xs, y)
            for i, key in ipairs(keys) do
                local on, rgb = lampShows(f, key)
                local x = xs[i]
                if on then
                    disc(x, y, 6, rgba(rgb, 40 * f.glow)) -- the glow bleeding round the symbol
                    ICONS[key](x, y, rgba(rgb, 255 * math.max(0.5, f.glow)))
                else
                    ICONS[key](x, y, P.UNLIT_LAMP)
                end
            end
        end

        -- an annunciator caption, as an aircraft's warning panel has them: a legend in a window, lit from behind
        local function caption(x, y, w, h, label, on, rgb, glow)
            local back = P.FACE
            if on then
                local dim = 0.2 + 0.12 * glow -- the window glows faintly in the legend's colour
                back = tocolor(rgb[1] * dim, rgb[2] * dim, rgb[3] * dim, 255)
            end
            rect(x, y, w, h, P.CHROME_DARK)
            rect(x + 0.4, y + 0.4, w - 0.8, h - 0.8, back)
            text(label, x + w / 2, y + h / 2, on and rgba(rgb, 255) or P.UNLIT_LAMP, 0.36, 2)
        end

        -- the ignition cylinder at (cx, cy): the three positions as ticks (the one the key is in lit, green for ACC
        -- with the engine running), the key pointing at its angle
        local function ignition(f, cx, cy)
            local pos, angle, running = f.keyPos, f.keyAngle, f.s.engine
            disc(cx, cy, IGN_TICK_R + 3, P.HOOD_RIM)
            disc(cx, cy, IGN_TICK_R + 2.4, P.HOOD)
            for _, name in ipairs(logic.KEY_ORDER) do
                local a = math.rad(logic.KEY_ANGLES[name])
                local lit = name == pos
                disc(
                    cx + math.sin(a) * IGN_TICK_R,
                    cy - math.cos(a) * IGN_TICK_R,
                    lit and 1.5 or 1.1,
                    lit and rgba(running and name == "acc" and P.GREEN or TICK[name], 255) or P.UNLIT_LAMP
                )
            end
            disc(cx, cy, IGN_R + 0.6, P.CHROME_DARK)
            disc(cx, cy, IGN_R, P.CHROME)
            disc(cx, cy, IGN_R - 1.4, P.CHROME_DARK)
            -- key out (OFF, once it has turned back there): the bare cylinder, its black keyway at the OFF angle
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
            stroke(tailX + dy * 1, tailY - dx * 1, tipX + dy * 1, tipY - dx * 1, KEY_SHINE, 0.6) -- light on one edge
            disc(tipX - dx * 0.6, tipY - dy * 0.6, 1.1, P.HOOD) -- the ring hole
        end

        -- an artificial horizon of radius r: the sky over the ground behind a fixed aircraft symbol, the horizon
        -- sinking as the nose rises (`pitch` degrees) and tilting against the bank (`roll` degrees, right positive).
        -- Drawn as columns across the ball, each split where the horizon crosses it.
        local function horizon(cx, cy, r, pitch, roll, glow)
            bezel(cx, cy, r)
            local lit = 0.35 + 0.65 * math.max(0, math.min(1, glow))
            local sky = tocolor(P.SKY[1] * lit, P.SKY[2] * lit, P.SKY[3] * lit, 255)
            local ground = tocolor(P.GROUND[1] * lit, P.GROUND[2] * lit, P.GROUND[3] * lit, 255)
            local a = math.rad(roll)
            local cosA, sinA = math.cos(a), math.sin(a)
            if cosA < 0 then
                sky, ground = ground, sky -- on its back: the ground is overhead
            end
            local slope = math.abs(cosA) < 0.02 and (sinA * cosA < 0 and -50 or 50) or sinA / cosA
            local drop = math.max(-r, math.min(r, pitch / 30 * r)) * (cosA < 0 and -1 or 1)
            local columns = 30
            local w = 2 * r / columns
            for i = 0, columns - 1 do
                local x = -r + (i + 0.5) * w
                local half = math.sqrt(math.max(0, r * r - x * x))
                local yh = math.max(-half, math.min(half, drop - x * slope))
                rect(cx + x - w / 2, cy - half, w + 0.05, yh + half, sky)
                rect(cx + x - w / 2, cy + yh, w + 0.05, half - yh, ground)
            end
            -- the aircraft: two wings and a dot, fixed to the panel
            local mark = ink(glow, P.AMBER)
            stroke(cx - r * 0.62, cy, cx - r * 0.22, cy, mark, 1)
            stroke(cx + r * 0.22, cy, cx + r * 0.62, cy, mark, 1)
            disc(cx, cy, 0.9, mark)
            arc(cx, cy, 180, 0, 1, r + 0.2, P.CHROME_DARK, 1.2) -- the ring tidies the ball's stepped edge
        end

        -- a heading tape w wide centred on (cx, y): 90 degrees of the compass sliding under a fixed lubber line
        local CARDINAL = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
        local function tape(cx, y, w, h, heading, glow, powered)
            rect(cx - w / 2 - 0.6, y - 0.6, w + 1.2, h + 1.2, P.CHROME_DARK)
            rect(cx - w / 2, y, w, h, P.FACE)
            local col = ink(glow)
            local span = 45
            for d = math.floor((heading - span) / 10) * 10, heading + span, 10 do
                local off = d - heading
                if math.abs(off) <= span - 4 then
                    local x = cx + off / span * (w / 2)
                    local deg = d % 360
                    if deg % 30 == 0 then
                        stroke(x, y, x, y + h * 0.3, col, 0.6)
                        text(CARDINAL[deg] or tostring(deg / 10), x, y + h * 0.66, col, 0.42, CARDINAL[deg] and 2 or 1)
                    else
                        stroke(x, y, x, y + h * 0.2, col, 0.4)
                    end
                end
            end
            stroke(cx, y - 0.6, cx, y + h + 0.6, rgba(powered and P.NEEDLE_LIT or P.NEEDLE_DARK, 255), 0.8)
        end

        -- a small gauge: a scale of +-sweep degrees, its low end red up to `redTo`, labels at both ends and a
        -- name under the pivot
        local function small(cx, cy, r, sweep, frac, lowLabel, highLabel, name, redTo, f)
            local col, red = ink(f.glow), ink(f.glow, logic.RED)
            arc(cx, cy, sweep, 0, redTo, r, red, 0.6)
            arc(cx, cy, sweep, redTo, 1, r, col, 0.6)
            for i = 0, 4 do
                local fr = i / 4
                tick(cx, cy, sweep, fr, r, r - (i % 2 == 0 and 3 or 1.8), fr < redTo and red or col, 0.6)
            end
            -- the end labels just under the arc's ends and the name under the pivot, clear of the needle's sweep
            local lx, ly = polar(cx, cy, sweep, 0, r)
            text(lowLabel, lx - 0.6, ly + 4, red, 0.44, 2)
            local hx, hy = polar(cx, cy, sweep, 1, r)
            text(highLabel, hx + 0.6, hy + 4, col, 0.44, 2)
            text(name, cx, cy + 4.6, col, 0.36, 2)
            needleAt(cx, cy, sweep, frac, r - 1.5, 2, 0.8, f.powered)
            hub(cx, cy, 1.5)
        end

        -- a flat instrument panel: a plate with a lighter rim, a bright top lip and a screw in each corner
        local function panel(x, y, w, h, plate, rim)
            rect(x - 1, y - 1, w + 2, h + 2, rim or P.HOOD_RIM)
            rect(x, y, w, h, plate or P.HOOD)
            rect(x, y - 1, w, 0.5, P.HOOD_EDGE)
            for _, sx in ipairs({ x + 3, x + w - 3 }) do
                for _, sy in ipairs({ y + 3, y + h - 3 }) do
                    disc(sx, sy, 1.1, P.CHROME_DARK)
                    stroke(sx - 0.7, sy - 0.7, sx + 0.7, sy + 0.7, P.HOOD_EDGE, 0.3)
                end
            end
        end

        -- an airspeed indicator: 0 .. top knots, numbered every `major`, with coloured range arcs
        -- ({ from, to, rgb } as shares of the scale) inside the ticks
        local function airspeed(cx, cy, r, knots, top, major, arcs, f)
            local sweep = 150
            bezel(cx, cy, r)
            for _, band in ipairs(arcs) do
                arc(cx, cy, sweep, band[1], band[2], r - 1.4, ink(f.glow, band[3]), 1.4)
            end
            local col = ink(f.glow)
            scale(cx, cy, r, sweep, top, major, 2, col, 0.36)
            text("KT", cx, cy + 5.5, col, 0.36, 2)
            needleAt(
                cx,
                cy,
                sweep,
                math.max(0, math.min(1, knots / top)),
                r - 2,
                2.5,
                0.9,
                true,
                f.powered and P.LIT_INK or P.UNLIT_INK
            )
            hub(cx, cy, 1.8)
        end

        -- an altimeter: a long hand turning once per 1000 ft, a short one once per 10000 ft, the height in digits
        local function altimeter(cx, cy, r, feet, f)
            feet = math.max(0, feet)
            bezel(cx, cy, r)
            local col = ink(f.glow)
            for i = 0, 49 do
                local deg = i * 7.2
                local ax, ay = at(cx, cy, deg, r - 0.8)
                local bx, by = at(cx, cy, deg, r - (i % 5 == 0 and 3 or 1.8))
                stroke(ax, ay, bx, by, col, i % 5 == 0 and 0.7 or 0.4)
                if i % 5 == 0 then
                    local lx, lyy = at(cx, cy, deg, r - 5.4)
                    text(tostring(i / 5), lx, lyy, col, 0.36)
                end
            end
            text("ALT", cx, cy - 4.2, col, 0.32, 2)
            rect(cx - 5.2, cy + 2, 10.4, 3.8, P.LCD_BACK)
            if f.powered then
                text(
                    string.format("%d", math.floor(feet / 10 + 0.5) * 10),
                    cx,
                    cy + 3.9,
                    rgba(P.LCD_INK, 255 * f.glow),
                    0.4
                )
            end
            local white = rgba(f.powered and P.LIT_INK or P.UNLIT_INK, 255)
            hand(cx, cy, feet % 10000 / 10000 * 360, r * 0.5, 1.5, 1.4, white)
            hand(cx, cy, feet % 1000 / 1000 * 360, r - 2.5, 2.5, 0.7, white)
            hub(cx, cy, 1.6)
        end

        -- a vertical speed indicator: level at nine o'clock, the hand rising for a climb, +-2000 ft/min
        local function climb(cx, cy, r, fpm, f)
            bezel(cx, cy, r)
            local col = ink(f.glow)
            for i = -4, 4 do
                local deg = -90 + i * 40
                local ax, ay = at(cx, cy, deg, r - 0.8)
                local bx, by = at(cx, cy, deg, r - (i % 2 == 0 and 3 or 1.8))
                stroke(ax, ay, bx, by, col, i % 2 == 0 and 0.7 or 0.4)
                if i % 2 == 0 then
                    local lx, lyy = at(cx, cy, deg, r - 5.4)
                    text(tostring(math.abs(i) / 2), lx, lyy, col, 0.36)
                end
            end
            text("UP", cx + 3, cy - 4.4, col, 0.3, 2)
            text("DN", cx + 3, cy + 4.4, col, 0.3, 2)
            local share = math.max(-1, math.min(1, fpm / 2000))
            hand(cx, cy, -90 + share * 160, r - 2.5, 2.5, 0.8, rgba(f.powered and P.LIT_INK or P.UNLIT_INK, 255))
            hub(cx, cy, 1.6)
        end

        -- a directional gyro: the compass card turning under a fixed aircraft and lubber line
        local function gyro(cx, cy, r, heading, f)
            bezel(cx, cy, r)
            local col = ink(f.glow)
            for d = 0, 350, 10 do
                local deg = d - heading
                local ax, ay = at(cx, cy, deg, r - 0.8)
                local bx, by = at(cx, cy, deg, r - (d % 30 == 0 and 3 or 1.8))
                stroke(ax, ay, bx, by, col, d % 30 == 0 and 0.7 or 0.4)
                if d % 90 == 0 then
                    local lx, lyy = at(cx, cy, deg, r - 6)
                    text(CARDINAL[d], lx, lyy, col, 0.46, 2)
                end
            end
            local mark = ink(f.glow, P.AMBER)
            stroke(cx, cy - 3.6, cx, cy + 3.4, mark, 0.8) -- the aircraft from above: fuselage, wings, tailplane
            stroke(cx - 3.4, cy - 0.4, cx + 3.4, cy - 0.4, mark, 0.8)
            stroke(cx - 1.4, cy + 2.8, cx + 1.4, cy + 2.8, mark, 0.6)
            stroke(cx, cy - r + 0.6, cx, cy - r + 3.4, rgba(f.powered and P.NEEDLE_LIT or P.NEEDLE_DARK, 255), 1)
        end

        L.panel, L.airspeed, L.altimeter, L.climb, L.gyro = panel, airspeed, altimeter, climb, gyro
        L.text, L.rect, L.stroke, L.disc, L.frame = text, rect, stroke, disc, frame
        L.at, L.polar, L.tick, L.arc, L.hand, L.needleAt, L.hub, L.bezel, L.scale =
            at, polar, tick, arc, hand, needleAt, hub, bezel, scale
        L.lampShows, L.telltales, L.caption, L.ignition, L.horizon, L.tape, L.small =
            lampShows, telltales, caption, ignition, horizon, tape, small
        return L
    end

    local kit = { logic = logic, P = P, layout = layout, ink = ink, blend = blend, rgba = rgba, ease = ease }
    local designs = {}
    for _, name in ipairs(DESIGNS) do
        designs[name] = ctx.load("client/dashboards/" .. name .. ".lua", "=hud/dashboards/" .. name .. ".lua")(kit)
    end

    -- the design a vehicle type's driver sees, or nil for none (the dev preview can force one)
    local function designOf(vt)
        local name = logic.design(vt)
        if name and preview and preview.design then
            name = preview.design
        end
        return name and designs[name] or nil
    end

    -- canvas y of the top edge of vt's dashboard, nil when it has none (a bicycle, a trailer)
    function M.top(vt)
        local design = designOf(vt)
        return design and design.top or nil
    end

    -- the dashboard of `vehicle` (vt: its data vehicle type) for its driver; every frame
    function M.draw(vehicle, vt)
        local design = designOf(vt)
        if not design then
            return
        end
        local now = getTickCount()
        local dt = lastTick and math.max(0, math.min(100, now - lastTick)) or 0
        lastTick = now
        local fresh = track(vehicle)
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
        if shot and shot.rpm then
            needle = shot.rpm
        elseif s.rpmShare then
            needle = s.rpmShare * logic.MAX_RPM -- dev preview
        else
            needle = logic.needle(needle, targetRpm(vehicle, s), dt)
        end
        local volts = shot and shot.volts or logic.volts(s)
        shown.speed = ease(shown.speed, powered and s.kmh or 0, dt, 120)
        shown.fuel = ease(shown.fuel, powered and logic.fuelShare(s.fuel, s.maxFuel) or 0, dt, 350)
        shown.volts = ease(shown.volts, logic.voltShare(volts), dt, shot and 60 or 250)

        local pos = logic.keyPosition(s, shot)
        local keyTarget = logic.KEY_ANGLES[pos]
        if vehicle ~= keyVehicle then
            keyVehicle, keyAngle = vehicle, keyTarget -- the key is already where it is on getting in
        end
        keyAngle = logic.keyStep(keyAngle, keyTarget, dt)

        design.draw({
            vehicle = vehicle,
            vt = vt,
            fresh = fresh, -- the first frame in this vehicle: a design's own needles go back to rest
            s = s,
            powered = powered,
            glow = glow,
            shot = shot,
            now = now,
            dt = dt,
            kmh = s.kmh,
            rpmShare = powered and math.max(0, math.min(1, needle / logic.MAX_RPM)) or 0,
            cranking = shot ~= nil and shot.rpm ~= nil,
            gear = getVehicleCurrentGear(vehicle),
            shown = shown,
            speedTop = speedTop, -- km/h, from the handling's top speed
            topKmh = handling and handling.maxVelocity,
            lamps = logic.lamps(s),
            keyPos = pos,
            keyAngle = keyAngle,
        })
    end

    -- dev preview: overrides (a table of state fields: battery, bay, engine, acc, lights, locked, health, fuel,
    -- maxFuel, kmh, rpmShare, pitch, roll, heading, altitude, climb, rotor, gearDown, and design = the name of a
    -- design to show instead of the vehicle's own) replace the vehicle's own until cleared with false (nil keeps
    -- them); kind "crank" | "stall" with a code plays that performance on the vehicle driven, as if vehicles had
    -- sent it
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
