-- The car's and the truck's dashboard: an analog instrument cluster in a dark binnacle. A speedometer dial (with a
-- digital readout) on the left, a tachometer on the right, a fuel gauge and a voltmeter between them over a row of
-- tell-tale lamps, and the ignition barrel outside the hood's left end. The markings are lit by the backlight only
-- while the panel has power; the needles rest at their stops otherwise. It spans y 404..474 on screen.
return function(kit)
    local logic, P, ink, rgba = kit.logic, kit.P, kit.ink, kit.rgba

    -- design units: the cluster is laid out at 212 x 48 and drawn K times that, a little clear of the screen's edge
    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 214, 430, 212, 48
    local L = kit.layout(K, BOTTOM, Y + H)
    local DIAL_R, DIAL_CY = 21, Y + 25
    local SPEEDO_CX, TACHO_CX = X + 38, X + W - 38
    local DIAL_SWEEP = 120 -- degrees either side of straight up
    local SMALL_R, SMALL_CY, SMALL_SWEEP = 12, Y + 27, 55
    local FUEL_CX, VOLT_CX = 302, 338
    local TELL_Y = Y + 40
    local TELL_X = { 287, 303.5, 320, 336.5, 353 }
    local TELLTALES = { "bat", "chk", "fuel", "lgt", "dor" } -- the tell-tale row, left to right

    -- the binnacle: a stadium-shaped hood with a lighter rim and a bright lip along its top edge
    local function drawHood()
        local r = H / 2
        L.disc(X + r, Y + r, r + 1, P.HOOD_RIM)
        L.disc(X + W - r, Y + r, r + 1, P.HOOD_RIM)
        L.rect(X + r, Y - 1, W - 2 * r, H + 2, P.HOOD_RIM)
        L.disc(X + r, Y + r, r, P.HOOD)
        L.disc(X + W - r, Y + r, r, P.HOOD)
        L.rect(X + r, Y, W - 2 * r, H, P.HOOD)
        L.rect(X + r, Y - 1, W - 2 * r, 0.5, P.HOOD_EDGE)
    end

    -- the speedometer: 0 .. speedTop km/h over 240 degrees, numbered every major step, with an LCD under the pivot
    local function drawSpeedo(f)
        local cx, cy, r = SPEEDO_CX, DIAL_CY, DIAL_R
        local top = f.speedTop
        L.bezel(cx, cy, r)
        local major = logic.speedStep(top)
        local col = ink(f.glow)
        local steps = top / (major / 4)
        for i = 0, steps do
            local frac = i / steps
            if i % 4 == 0 then
                L.tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 4, col, 0.8)
                local lx, ly = L.polar(cx, cy, DIAL_SWEEP, frac, r - 7.6)
                L.text(tostring(math.floor(frac * top + 0.5)), lx, ly, col, 0.5)
            elseif i % 2 == 0 then
                L.tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2.8, col, 0.5)
            else
                L.tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2, col, 0.4)
            end
        end
        L.text("km/h", cx, cy - 6, col, 0.42, 2)
        -- the LCD: the speed in digits, dark with the panel off
        L.rect(cx - 6.5, cy + 6, 13, 5.6, P.LCD_BACK)
        if f.powered then
            L.text(string.format("%d", math.floor(f.kmh + 0.5)), cx, cy + 8.9, rgba(P.LCD_INK, 255 * f.glow), 0.55)
        end
        L.needleAt(cx, cy, DIAL_SWEEP, math.min(f.shown.speed, top) / top, r - 2, 3.5, 1.1, f.powered)
        L.hub(cx, cy, 2.4)
    end

    -- the tachometer: 0 .. MAX_RPM, a number every thousand, the red zone from the redline
    local function drawTacho(f)
        local cx, cy, r = TACHO_CX, DIAL_CY, DIAL_R
        L.bezel(cx, cy, r)
        local col = ink(f.glow)
        L.arc(cx, cy, DIAL_SWEEP, logic.REDLINE, 1, r - 1.6, ink(f.glow, logic.RED), 1.8)
        local thousands = logic.MAX_RPM / 1000
        for i = 0, thousands * 4 do
            local frac = i / (thousands * 4)
            local red = frac >= logic.REDLINE
            local tc = red and ink(f.glow, logic.RED) or col
            if i % 4 == 0 then
                L.tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 4, tc, 0.8)
                local lx, ly = L.polar(cx, cy, DIAL_SWEEP, frac, r - 7.6)
                L.text(tostring(i / 4), lx, ly, tc, 0.6)
            elseif i % 2 == 0 then
                L.tick(cx, cy, DIAL_SWEEP, frac, r - 0.8, r - 2.8, tc, 0.5)
            end
        end
        L.text("x1000", cx, cy - 6, col, 0.42, 2)
        L.text("RPM", cx, cy + 8.5, col, 0.46, 2)
        L.needleAt(cx, cy, DIAL_SWEEP, f.rpmShare, r - 2, 3.5, 1.1, f.powered)
        L.hub(cx, cy, 2.4)
    end

    local function draw(f)
        drawHood()
        drawSpeedo(f)
        drawTacho(f)
        L.small(FUEL_CX, SMALL_CY, SMALL_R, SMALL_SWEEP, f.shown.fuel, "E", "F", "FUEL", 0.125, f)
        local low = logic.voltShare(logic.VOLTS_LOW)
        L.small(VOLT_CX, SMALL_CY, SMALL_R, SMALL_SWEEP, f.shown.volts, "8", "16", "VOLT", low, f)
        L.telltales(f, TELLTALES, TELL_X, TELL_Y)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
