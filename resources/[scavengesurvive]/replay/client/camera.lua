-- Replay cameras: follow (smoothed, behind the focus), top-down, side, and a free fly camera.
-- Free fly: WASD + E/Q up/down, shift fast, mouse look while the cursor is hidden (Tab toggles it).
return function()
    local M = {}
    local MODES = { "follow", "top", "side", "free" }
    local mode = "follow"
    local pos = { 0, 0, 0 }
    local look = { 0, 0, 0 }
    local yaw, pitch = 0, 0
    local started = false
    local cursorVisible = false
    local lastTick = 0

    function M.modes()
        return MODES
    end

    function M.mode()
        return mode
    end

    function M.setMode(m)
        for _, v in ipairs(MODES) do
            if v == m then
                if m == "free" and mode ~= "free" then
                    -- start the free camera where the current one is
                    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
                    pos = { cx, cy, cz }
                    local dx, dy, dz = lx - cx, ly - cy, lz - cz
                    yaw = math.deg(math.atan2(dx, dy))
                    pitch = math.deg(math.atan2(dz, math.sqrt(dx * dx + dy * dy)))
                end
                mode = m
                return
            end
        end
    end

    function M.cycle()
        for i, v in ipairs(MODES) do
            if v == mode then
                M.setMode(MODES[i % #MODES + 1])
                return mode
            end
        end
    end

    function M.setCursorVisible(v)
        cursorVisible = v
    end

    function M.start(x, y, z)
        started = true
        pos = { x - 5, y - 5, z + 3 }
        look = { x, y, z }
        lastTick = getTickCount()
    end

    function M.stop()
        if started then
            started = false
            setCameraTarget(localPlayer)
            setCameraInterior(getElementInterior(localPlayer))
        end
    end

    -- mouse look for the free camera (onClientCursorMove gives the pointer in screen fractions)
    addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
        if started and mode == "free" and not cursorVisible then
            local sw, sh = guiGetScreenSize()
            local dx, dy = ax - sw / 2, ay - sh / 2
            if dx ~= 0 or dy ~= 0 then
                yaw = yaw + dx * 0.15
                pitch = math.max(-89, math.min(89, pitch - dy * 0.15))
                setCursorPosition(sw / 2, sh / 2)
            end
        end
    end)

    local function lerp(a, b, f)
        return a + (b - a) * f
    end

    -- fx, fy, fz, frz, int: the focus (the followed ghost) this frame, or nil when it is not on the map yet
    function M.update(fx, fy, fz, frz, int)
        if not started then
            return
        end
        local now = getTickCount()
        local dt = math.min(0.1, (now - lastTick) / 1000)
        lastTick = now
        setCameraInterior(int or 0)
        if mode == "free" then
            local speed = (getKeyState("lshift") and 40 or 8) * dt
            local ry, rp = math.rad(yaw), math.rad(pitch)
            local fx2, fy2, fz2 = math.sin(ry) * math.cos(rp), math.cos(ry) * math.cos(rp), math.sin(rp)
            local rx2, ry2 = math.cos(ry), -math.sin(ry)
            if not cursorVisible then
                if getKeyState("w") then
                    pos[1], pos[2], pos[3] = pos[1] + fx2 * speed, pos[2] + fy2 * speed, pos[3] + fz2 * speed
                end
                if getKeyState("s") then
                    pos[1], pos[2], pos[3] = pos[1] - fx2 * speed, pos[2] - fy2 * speed, pos[3] - fz2 * speed
                end
                if getKeyState("d") then
                    pos[1], pos[2] = pos[1] + rx2 * speed, pos[2] + ry2 * speed
                end
                if getKeyState("a") then
                    pos[1], pos[2] = pos[1] - rx2 * speed, pos[2] - ry2 * speed
                end
                if getKeyState("e") then
                    pos[3] = pos[3] + speed
                end
                if getKeyState("q") then
                    pos[3] = pos[3] - speed
                end
            end
            setCameraMatrix(pos[1], pos[2], pos[3], pos[1] + fx2, pos[2] + fy2, pos[3] + fz2)
            return
        end
        if not fx then
            setCameraMatrix(pos[1], pos[2], pos[3], look[1], look[2], look[3])
            return
        end
        local rad = math.rad(frz or 0)
        local bx, by = math.sin(rad), -math.cos(rad) -- behind the ghost (it faces -sin, +cos)
        local tx, ty, tz
        if mode == "follow" then
            tx, ty, tz = fx + bx * 5.5, fy + by * 5.5, fz + 2.4
        elseif mode == "top" then
            tx, ty, tz = fx, fy - 0.01, fz + 38
        else -- side
            tx, ty, tz = fx + by * -9, fy + bx * 9, fz + 2.2
        end
        local f = math.min(1, dt * (mode == "follow" and 5 or 3))
        if pos[1] == 0 and pos[2] == 0 then
            f = 1
        end
        pos = { lerp(pos[1], tx, f), lerp(pos[2], ty, f), lerp(pos[3], tz, f) }
        look = {
            lerp(look[1], fx, math.min(1, f * 2)),
            lerp(look[2], fy, math.min(1, f * 2)),
            lerp(look[3], fz + 0.6, math.min(1, f * 2)),
        }
        setCameraMatrix(pos[1], pos[2], pos[3], look[1], look[2], look[3])
    end

    -- the camera position, for culling the world around it
    function M.position()
        return pos[1], pos[2], pos[3]
    end

    return M
end
