-- The boat's dashboard: a helm console in navy with a brass rim. White-faced dials, a log reading knots on the left
-- and the tachometer on the right, and between them a compass strip over the fuel gauge and three tell-tales (check
-- engine, fuel, navigation lights). The dial faces glow cream with the panel lit and go grey with it dark.
return function(kit)
    local logic, blend = kit.logic, kit.blend

    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 214, 430, 212, 48
    local L = kit.layout(K, BOTTOM, Y + H)
    local DIAL_R, DIAL_CY = 21, Y + 24.5
    local LOG_CX, TACHO_CX = X + 27, X + W - 27
    local FUEL_CY, FUEL_R = Y + 26, 11
    local TELL_Y = Y + 40.5
    local TELL_X = { 303.5, 320, 336.5 }
    local TELLTALES = { "chk", "fuel", "lgt" }
    local NAVY, BRASS = tocolor(14, 22, 40, 250), tocolor(168, 132, 62, 255)
    local FACE_LIT, FACE_DARK = { 232, 226, 206 }, { 92, 92, 88 }
    local PRINT_LIT, PRINT_DARK = { 18, 22, 34 }, { 30, 30, 32 }
    local PRINT_RED = { 190, 20, 20 }

    local function drawLog(f, face, print)
        local cx, cy, r = LOG_CX, DIAL_CY, DIAL_R
        local top, step = logic.knotScale(f.topKmh)
        L.bezel(cx, cy, r, face, BRASS)
        L.scale(cx, cy, r, 120, top, step, 2, print, 0.5)
        L.text("KNOTS", cx, cy + 8, print, 0.4, 2)
        L.needleAt(cx, cy, 120, math.min(1, logic.knots(f.shown.speed) / top), r - 2, 3.5, 1.1, f.powered)
        L.hub(cx, cy, 2.4)
    end

    local function drawTacho(f, face, print)
        local cx, cy, r = TACHO_CX, DIAL_CY, DIAL_R
        local red = blend(f.glow, PRINT_RED, PRINT_DARK)
        L.bezel(cx, cy, r, face, BRASS)
        L.arc(cx, cy, 120, logic.REDLINE, 1, r - 1.6, red, 1.8)
        local thousands = logic.MAX_RPM / 1000
        for i = 0, thousands * 2 do
            local frac = i / (thousands * 2)
            local tc = frac >= logic.REDLINE and red or print
            if i % 2 == 0 then
                L.tick(cx, cy, 120, frac, r - 0.8, r - 4, tc, 0.8)
                local lx, ly = L.polar(cx, cy, 120, frac, r - 7.6)
                L.text(tostring(i / 2), lx, ly, tc, 0.6)
            else
                L.tick(cx, cy, 120, frac, r - 0.8, r - 2.6, tc, 0.5)
            end
        end
        L.text("x1000", cx, cy - 6, print, 0.4, 2)
        L.text("RPM", cx, cy + 8.5, print, 0.44, 2)
        L.needleAt(cx, cy, 120, f.rpmShare, r - 2, 3.5, 1.1, f.powered)
        L.hub(cx, cy, 2.4)
    end

    local function draw(f)
        local face = blend(f.glow, FACE_LIT, FACE_DARK)
        local print = blend(f.glow, PRINT_LIT, PRINT_DARK)
        L.panel(X, Y, W, H, NAVY, BRASS)
        drawLog(f, face, print)
        drawTacho(f, face, print)
        L.tape(320, Y + 3.5, 78, 8.5, f.s.heading, f.glow, f.powered)
        L.small(320, FUEL_CY, FUEL_R, 55, f.shown.fuel, "E", "F", "FUEL", 0.125, f)
        L.telltales(f, TELLTALES, TELL_X, TELL_Y)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
