-- The motorbike's dashboard: two chrome pods on a short bracket, as they sit over a headlamp. The speedometer (with
-- its digital readout) in the big pod, the tachometer in the small one, and between them a fuel level in LCD bars
-- over three tell-tales (check engine, fuel, headlight). A bike has no doors to lock and no battery level to read.
return function(kit)
    local logic, P, ink, rgba = kit.logic, kit.P, kit.ink, kit.rgba

    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 250, 428, 140, 46
    local L = kit.layout(K, BOTTOM, Y + H)
    local SPEEDO_CX, SPEEDO_CY, SPEEDO_R = X + 25, Y + 23, 20
    local TACHO_CX, TACHO_CY, TACHO_R = X + W - 21, Y + 25, 16
    local MID = 323
    local BAR_X, BAR_Y, BAR_W, BAR_H, BARS = MID - 19, Y + 9, 38, 7, 8
    local TELL_Y = Y + 35
    local TELL_X = { MID - 16, MID, MID + 16 }
    local TELLTALES = { "chk", "fuel", "lgt" }
    local BRIGHT = tocolor(196, 196, 204, 255) -- polished pod rims

    -- the bracket: a plate between the pods, the pods' housings standing proud of it
    local function drawBracket()
        L.rect(SPEEDO_CX, Y + 5, TACHO_CX - SPEEDO_CX, H - 9, P.HOOD_RIM)
        L.rect(SPEEDO_CX, Y + 6, TACHO_CX - SPEEDO_CX, H - 11, P.HOOD)
        L.rect(SPEEDO_CX, Y + 5, TACHO_CX - SPEEDO_CX, 0.5, P.HOOD_EDGE)
        L.disc(SPEEDO_CX, SPEEDO_CY, SPEEDO_R + 3, P.HOOD_RIM)
        L.disc(TACHO_CX, TACHO_CY, TACHO_R + 3, P.HOOD_RIM)
    end

    local function drawSpeedo(f)
        local cx, cy, r = SPEEDO_CX, SPEEDO_CY, SPEEDO_R
        local top = f.speedTop
        local col = ink(f.glow)
        L.bezel(cx, cy, r, nil, BRIGHT)
        L.scale(cx, cy, r, 120, top, logic.speedStep(top), 2, col, 0.48)
        L.text("km/h", cx, cy - 5.6, col, 0.4, 2)
        L.rect(cx - 6, cy + 5.6, 12, 5.4, P.LCD_BACK)
        if f.powered then
            L.text(string.format("%d", math.floor(f.kmh + 0.5)), cx, cy + 8.4, rgba(P.LCD_INK, 255 * f.glow), 0.52)
        end
        L.needleAt(cx, cy, 120, math.min(f.shown.speed, top) / top, r - 2, 3.2, 1, f.powered)
        L.hub(cx, cy, 2.2)
    end

    local function drawTacho(f)
        local cx, cy, r = TACHO_CX, TACHO_CY, TACHO_R
        local col, red = ink(f.glow), ink(f.glow, logic.RED)
        L.bezel(cx, cy, r, nil, BRIGHT)
        L.arc(cx, cy, 120, logic.REDLINE, 1, r - 1.4, red, 1.5)
        local thousands = logic.MAX_RPM / 1000
        for i = 0, thousands * 2 do
            local frac = i / (thousands * 2)
            local tc = frac >= logic.REDLINE and red or col
            if i % 2 == 0 then
                L.tick(cx, cy, 120, frac, r - 0.8, r - 3.2, tc, 0.7)
                local lx, ly = L.polar(cx, cy, 120, frac, r - 5.8)
                L.text(tostring(i / 2), lx, ly, tc, 0.44)
            else
                L.tick(cx, cy, 120, frac, r - 0.8, r - 2.2, tc, 0.4)
            end
        end
        L.text("RPM", cx, cy + 7, col, 0.38, 2)
        L.needleAt(cx, cy, 120, f.rpmShare, r - 2, 2.8, 0.9, f.powered)
        L.hub(cx, cy, 1.9)
    end

    -- the fuel level: LCD bars filling left to right, the last one blinking on a low tank
    local function drawFuel(f)
        local col = ink(f.glow)
        L.rect(BAR_X - 1.5, BAR_Y - 1.5, BAR_W + 3, BAR_H + 3, P.CHROME_DARK)
        L.rect(BAR_X - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2, P.LCD_BACK)
        local share = f.shown.fuel
        local lit = math.ceil(share * BARS - 0.001)
        local low = share <= logic.FUEL_LOW
        local w = BAR_W / BARS
        for i = 1, BARS do
            local on = f.powered and i <= lit and not (low and i == lit and not logic.lit("slow", f.now))
            local rgb = low and logic.RED or P.LCD_INK
            L.rect(
                BAR_X + (i - 1) * w + 0.4,
                BAR_Y,
                w - 0.8,
                BAR_H,
                on and rgba(rgb, 255 * f.glow) or tocolor(18, 30, 22, 255)
            )
        end
        L.text("E", BAR_X - 1, BAR_Y + BAR_H + 5, ink(f.glow, logic.RED), 0.4, 2)
        L.text("FUEL", MID, BAR_Y + BAR_H + 5, col, 0.34, 2)
        L.text("F", BAR_X + BAR_W + 1, BAR_Y + BAR_H + 5, col, 0.4, 2)
    end

    local function draw(f)
        drawBracket()
        drawSpeedo(f)
        drawTacho(f)
        drawFuel(f)
        L.telltales(f, TELLTALES, TELL_X, TELL_Y)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
