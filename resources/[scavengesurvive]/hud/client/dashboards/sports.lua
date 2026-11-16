-- The sports car's dashboard (a vehicle type with dash = "sports"): the tachometer is the instrument, big and in
-- the middle, reading to 9000 with the gear in a window on its face and a shift light that flashes at the top of
-- each gear. The speedometer sits smaller on its left, the fuel gauge and voltmeter on its right over the
-- tell-tale lamps, all in a low carbon binnacle with a red lip; the needles are yellow.
return function(kit)
    local logic, P, ink, rgba = kit.logic, kit.P, kit.ink, kit.rgba

    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 214, 420, 212, 54
    local L = kit.layout(K, BOTTOM, Y + H)
    local CY = Y + 27
    local SPEEDO_CX, SPEEDO_R = X + 30, 18
    local TACHO_CX, TACHO_R, TACHO_SWEEP, TACHO_TOP = 320, 25, 135, 9
    local FUEL_CX, VOLT_CX, SMALL_CY, SMALL_R = 368, 398, Y + 22, 11
    local TELL_Y = Y + 43
    local TELL_X = { 355, 368.5, 382, 395.5, 409 }
    local TELLTALES = { "bat", "chk", "fuel", "lgt", "dor" }
    local CARBON = tocolor(10, 10, 12, 252)
    local LIP = tocolor(200, 30, 24, 255)
    local RING = tocolor(170, 34, 28, 255) -- the tachometer's red bezel
    local YELLOW = { 255, 214, 0 }

    local function drawHood()
        local r = H / 2
        L.disc(X + r, Y + r, r + 1, P.HOOD_RIM)
        L.disc(X + W - r, Y + r, r + 1, P.HOOD_RIM)
        L.rect(X + r, Y - 1, W - 2 * r, H + 2, P.HOOD_RIM)
        L.disc(X + r, Y + r, r, CARBON)
        L.disc(X + W - r, Y + r, r, CARBON)
        L.rect(X + r, Y, W - 2 * r, H, CARBON)
        L.rect(X + r, Y - 1, W - 2 * r, 0.7, LIP)
    end

    local function drawSpeedo(f)
        local cx, cy, r = SPEEDO_CX, CY, SPEEDO_R
        local top = f.speedTop
        local col = ink(f.glow)
        L.bezel(cx, cy, r)
        L.scale(cx, cy, r, 120, top, logic.speedStep(top), 2, col, 0.42)
        L.text("km/h", cx, cy - 5, col, 0.36, 2)
        L.rect(cx - 5.5, cy + 5, 11, 5, P.LCD_BACK)
        if f.powered then
            L.text(string.format("%d", math.floor(f.kmh + 0.5)), cx, cy + 7.6, rgba(P.LCD_INK, 255 * f.glow), 0.48)
        end
        L.needleAt(cx, cy, 120, math.min(f.shown.speed, top) / top, r - 2, 3, 1, f.powered, YELLOW)
        L.hub(cx, cy, 2)
    end

    -- the gear in the window: R in reverse, a dash with the engine off
    local function gearText(f)
        if not f.s.engine then
            return "-"
        end
        return (f.gear or 1) <= 0 and "R" or tostring(f.gear)
    end

    local function drawTacho(f)
        local cx, cy, r = TACHO_CX, CY, TACHO_R
        local col, red = ink(f.glow), ink(f.glow, logic.RED)
        L.bezel(cx, cy, r, nil, RING)
        L.arc(cx, cy, TACHO_SWEEP, logic.REDLINE, 1, r - 1.8, red, 2.2)
        for i = 0, TACHO_TOP * 2 do
            local frac = i / (TACHO_TOP * 2)
            local tc = frac >= logic.REDLINE and red or col
            if i % 2 == 0 then
                L.tick(cx, cy, TACHO_SWEEP, frac, r - 0.8, r - 4.4, tc, 0.9)
                local lx, ly = L.polar(cx, cy, TACHO_SWEEP, frac, r - 8)
                L.text(tostring(i / 2), lx, ly, tc, 0.62)
            else
                L.tick(cx, cy, TACHO_SWEEP, frac, r - 0.8, r - 2.8, tc, 0.5)
            end
        end
        -- the shift light: dark until the needle nears the red, then flashing
        local shift = f.powered and f.rpmShare >= logic.REDLINE - 0.03 and logic.lit("fast", f.now)
        L.disc(cx, cy - 9.5, 2.6, P.CHROME_DARK)
        L.disc(cx, cy - 9.5, 2, shift and rgba(logic.RED, 255) or P.UNLIT_LAMP)
        if shift then
            L.disc(cx, cy - 9.5, 4.2, rgba(logic.RED, 60))
        end
        L.rect(cx - 4.5, cy + 6, 9, 8, P.LCD_BACK)
        if f.powered then
            L.text(gearText(f), cx, cy + 10.2, rgba(P.LCD_INK, 255 * f.glow), 0.8)
        end
        L.text("RPM x1000", cx, cy + 17.5, col, 0.36, 2)
        L.needleAt(cx, cy, TACHO_SWEEP, f.rpmShare, r - 2.5, 4, 1.2, f.powered, YELLOW)
        L.hub(cx, cy, 2.8)
    end

    local function draw(f)
        drawHood()
        drawSpeedo(f)
        drawTacho(f)
        L.small(FUEL_CX, SMALL_CY, SMALL_R, 55, f.shown.fuel, "E", "F", "FUEL", 0.125, f)
        L.small(VOLT_CX, SMALL_CY, SMALL_R, 55, f.shown.volts, "8", "16", "VOLT", logic.voltShare(logic.VOLTS_LOW), f)
        L.telltales(f, TELLTALES, TELL_X, TELL_Y)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
