-- The plane's dashboard: the flight instruments in a row as a light aircraft has them: airspeed in knots, the
-- artificial horizon, the altimeter in feet, the directional gyro and vertical speed, and on the right the fuel
-- gauge and engine revs over an annunciator panel: ENG, FUEL, LTS, DOOR and a green GEAR caption while the
-- undercarriage is down.
return function(kit)
    local logic, P = kit.logic, kit.P

    local K, BOTTOM = 1.45, 474
    local X, Y, W, H = 206, 426, 228, 48
    local L = kit.layout(K, BOTTOM, Y + H)
    local R, CY, PITCH = 15, Y + 28, 33
    local CX = { X + 20, X + 20 + PITCH, X + 20 + 2 * PITCH, X + 20 + 3 * PITCH, X + 20 + 4 * PITCH }
    local SIDE = X + 171
    local KNOTS_TOP = 180
    local ARCS = { { 0.2, 0.45, P.LIT_INK }, { 0.3, 0.75, P.GREEN }, { 0.75, 0.92, P.AMBER }, { 0.92, 1, P.RED } }
    local revs = 0 -- the eased engine revs, as a share of the gauge

    local function caption(f, col, row, label, key)
        local on, rgb = L.lampShows(f, key)
        L.caption(SIDE + col * 18, Y + 27.5 + row * 8.5, 17, 7.5, label, on, rgb, f.glow)
    end

    local function draw(f)
        local s = f.s
        if f.fresh then
            revs = 0
        end
        local throttle = getPedControlState(localPlayer, "accelerate")
        local brake = getPedControlState(localPlayer, "brake_reverse")
        revs = kit.ease(revs, f.cranking and f.rpmShare or logic.propShare(s.engine, throttle, brake), f.dt, 400)

        L.panel(X, Y, W, H)
        L.airspeed(CX[1], CY, R, logic.knots(f.kmh), KNOTS_TOP, 30, ARCS, f)
        L.horizon(CX[2], CY, R, s.pitch, s.roll, f.glow)
        L.altimeter(CX[3], CY, R, s.altitude, f)
        L.gyro(CX[4], CY, R, s.heading, f)
        L.climb(CX[5], CY, R, s.climb, f)
        L.small(SIDE + 12.5, Y + 16, 10, 55, f.shown.fuel, "E", "F", "FUEL", 0.125, f)
        L.small(SIDE + 40.5, Y + 16, 10, 55, f.powered and revs or 0, "0", "MAX", "RPM", 0, f)
        caption(f, 0, 0, "ENG", "chk")
        caption(f, 1, 0, "FUEL", "fuel")
        caption(f, 2, 0, "LTS", "lgt")
        caption(f, 0, 1, "DOOR", "dor")
        local bulb = f.shot and f.shot.bulb
        L.caption(SIDE + 18, Y + 36, 35, 7.5, "GEAR", f.powered and (s.gearDown or bulb) or false, P.GREEN, f.glow)
        L.ignition(f, X - 20, Y + H - 17.5)
    end

    return { top = BOTTOM - H * K, draw = draw }
end
