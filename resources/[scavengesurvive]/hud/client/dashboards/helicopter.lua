-- The helicopter's dashboard: a flat avionics panel. A heading tape over five instruments (airspeed in knots, the
-- artificial horizon, the altimeter in feet, vertical speed in thousands of feet a minute, rotor speed in percent
-- with its green band), and on the right the fuel gauge over an annunciator panel: ENG, FUEL, LTS, DOOR and a red
-- ROTOR caption while the rotor turns too slowly to fly.
return function(kit)
    local logic, P, ink = kit.logic, kit.P, kit.ink

    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 206, 422, 228, 52
    local L = kit.layout(K, BOTTOM, Y + H)
    local R, CY, PITCH = 14.5, Y + 32, 33
    local CX = { X + 19, X + 19 + PITCH, X + 19 + 2 * PITCH, X + 19 + 3 * PITCH, X + 19 + 4 * PITCH }
    local SIDE = X + 171 -- the right-hand column: fuel over the annunciators
    local KNOTS_TOP = 120
    local ARCS = { { 0.17, 0.8, P.GREEN }, { 0.8, 0.92, P.AMBER }, { 0.92, 1, P.RED } }
    local ROTOR_TOP = 120 -- percent

    local function drawRotor(f)
        local cx, cy, r = CX[5], CY, R
        local col = ink(f.glow)
        L.bezel(cx, cy, r)
        L.arc(cx, cy, 120, 0, logic.ROTOR_LOW * 100 / ROTOR_TOP, r - 1.4, ink(f.glow, P.RED), 1.4)
        L.arc(cx, cy, 120, 90 / ROTOR_TOP, 110 / ROTOR_TOP, r - 1.4, ink(f.glow, P.GREEN), 1.4)
        L.scale(cx, cy, r, 120, ROTOR_TOP, 20, 2, col, 0.36, 10)
        L.text("ROTOR", cx, cy + 5, col, 0.3, 2)
        L.text("% x10", cx, cy + 9, col, 0.3, 2)
        local share = math.min(1, f.s.rotor * 100 / ROTOR_TOP)
        L.needleAt(cx, cy, 120, share, r - 2, 2.5, 0.9, f.powered)
        L.hub(cx, cy, 1.8)
    end

    local function caption(f, col, row, span, label, key)
        local on, rgb = L.lampShows(f, key)
        L.caption(SIDE + col * 18, Y + 31.5 + row * 8.5, 17 + (span - 1) * 18, 7.5, label, on, rgb, f.glow)
    end

    local function draw(f)
        local s = f.s
        L.panel(X, Y, W, H)
        L.tape(X + 19 + 2 * PITCH, Y + 4, 96, 8.5, s.heading, f.glow, f.powered)
        L.airspeed(CX[1], CY, R, logic.knots(f.kmh), KNOTS_TOP, 20, ARCS, f)
        L.horizon(CX[2], CY, R, s.pitch, s.roll, f.glow)
        L.altimeter(CX[3], CY, R, s.altitude, f)
        L.climb(CX[4], CY, R, s.climb, f)
        drawRotor(f)
        L.small(SIDE + 26.5, Y + 19, 11, 55, f.shown.fuel, "E", "F", "FUEL", 0.125, f)
        caption(f, 0, 0, 1, "ENG", "chk")
        caption(f, 1, 0, 1, "FUEL", "fuel")
        caption(f, 2, 0, 1, "LTS", "lgt")
        caption(f, 0, 1, 1, "DOOR", "dor")
        -- the rotor turning too slowly to fly, with the engine running: red, flashing; lit in the bulb check
        local low = s.engine and s.rotor < logic.ROTOR_LOW and logic.lit("slow", f.now)
        local bulb = f.shot and f.shot.bulb
        L.caption(SIDE + 18, Y + 40, 35, 7.5, "ROTOR", f.powered and (low or bulb) or false, P.RED, f.glow)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
