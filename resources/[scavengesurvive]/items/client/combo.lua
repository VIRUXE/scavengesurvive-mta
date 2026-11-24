-- The Combination Padlock close-up (server/smallitems.lua): Use puts the padlock in front of the player and the camera
-- pans onto its dials. Left/Right pick a dial, Up/Down or a digit key turn it, S spins them all, Space pushes the
-- shackle (down onto an open padlock to shut it; on a shut one it springs up and turns out when the dials show the
-- code, which only the server knows), R makes the dials the code while it is open, Esc or a step away ends it.
-- The padlock is two objects, combo_padlock_body and combo_shackle (tools/make_props.py): the shackle is attached on
-- its long leg's axis, raised and turned by the numbers make_props built combo_padlock with. The dials' digits are a
-- render target swapped in for the body's digit texture (replace.fx), redrawn whenever a dial turns.
-- ctx = { models = client/models.lua, lang = lib lang }
return function(ctx)
    local models, lang = ctx.models, ctx.lang
    local BODY_MODEL, SHACKLE_MODEL = 20264, 20265
    local SHOWN = { 2, 7, 4, 9 } -- make_props COMBO_SHOWN: the motel-number cell (1 to 9) each dial's facet shows
    local LEG_X = -0.0145 -- COMBO_SHACKLE: the long leg's axis
    local RAISE, TURN = 0.01, 90 -- COMBO_RAISE, COMBO_TURN: the shackle open
    local DIGIT_TEXTURE = "mp_motel_numbers"
    local RT_W, RT_H = 128, 256 -- that texture's size: a 3 x 3 grid of cells
    local PAN_MS = 650
    local WALK_AWAY = 1.5
    -- lang:begin
    local HINTS = {
        dials = "Left/Right: dial   Up/Down or 0-9: turn   S: scramble",
        open = "Space: push the shackle down   R: save these digits as the code   Esc: done",
        shut = "Space: push the shackle (it opens on the right code)   Esc: done",
    }
    -- lang:end

    local s -- the open close-up, or nil

    local function lerp(a, b, f)
        return a + (b - a) * f
    end

    local function ease(f)
        return f < 0.5 and 2 * f * f or 1 - (-2 * f + 2) ^ 2 / 2
    end

    local function dialString()
        return table.concat(s.dials)
    end

    local function drawDials()
        if not s or not isElement(s.rt) then
            return
        end
        dxSetRenderTarget(s.rt, true)
        local cw, ch = RT_W / 3, RT_H / 3
        local scale = ch * 0.72 / dxGetFontHeight(1, "default-bold")
        for i, cell in ipairs(SHOWN) do
            local x, y = ((cell - 1) % 3) * cw, math.floor((cell - 1) / 3) * ch
            -- the dial being turned: its digit red over a yellow bar (a see-through tint would not show)
            if i == s.sel then
                dxDrawRectangle(x + cw * 0.1, y + ch * 0.86, cw * 0.8, ch * 0.08, tocolor(255, 196, 0, 255))
            end
            local c = i == s.sel and tocolor(190, 20, 20, 255) or tocolor(10, 10, 10, 255)
            dxDrawText(tostring(s.dials[i]), x, y, x + cw, y + ch, c, scale, "default-bold", "center", "center")
        end
        dxSetRenderTarget()
    end

    local function poseShackle(raise, turn)
        if s and isElement(s.shackle) then
            setElementAttachedOffsets(s.shackle, LEG_X, 0, raise, 0, 0, turn)
        end
        s.raise, s.turn = raise, turn
    end

    -- keys = { { raise, turn, ms }, ... } from the pose the shackle is in
    local function animate(keys, done)
        s.anim = { keys = keys, i = 1, from = { s.raise, s.turn }, start = getTickCount(), done = done }
    end

    local function cameraPose()
        local m = getElementMatrix(s.body)
        local function point(x, y, z)
            return x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
                x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
                x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
        end
        local lx, ly, lz = point(0, 0, 0.05)
        local cx, cy, cz = point(0, -0.3, 0.085)
        return { cx, cy, cz, lx, ly, lz, 0, 40 }
    end

    local function close(silent)
        if not s then
            return
        end
        if not silent then
            triggerServerEvent("comboPadlockActed", localPlayer, s.itemId, "leave", dialString())
        end
        for _, e in ipairs({ s.shackle, s.body, s.shader, s.rt }) do
            if isElement(e) then
                destroyElement(e)
            end
        end
        s = nil
        resetNearClipDistance()
        setCameraTarget(localPlayer)
    end

    local function open(itemId, shut, dials, savedCode)
        close(true)
        local body = createObject(models.forSamp(BODY_MODEL) or models.FALLBACK, 0, 0, -1000)
        local shackle = createObject(models.forSamp(SHACKLE_MODEL) or models.FALLBACK, 0, 0, -1000)
        if not body or not shackle then
            return
        end
        local px, py, pz = getElementPosition(localPlayer)
        -- along the game camera's line of sight, between it and the player: the camera keeps that clear of walls and
        -- slopes, where a spot in front of the player can be inside a hillside
        local cx, cy, cz, lx, ly, lz = getCameraMatrix()
        local dx, dy, dz = lx - cx, ly - cy, lz - cz
        local len = math.max(0.001, math.sqrt(dx * dx + dy * dy + dz * dz))
        dx, dy, dz = dx / len, dy / len, dz / len
        local heading = math.deg(math.atan2(-dx, dy))
        local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
        for _, o in ipairs({ body, shackle }) do
            setElementCollisionsEnabled(o, false)
            setElementInterior(o, int)
            setElementDimension(o, dim)
        end
        -- its dials (-Y) toward the camera, its middle on the line of sight
        setElementPosition(body, cx + dx * 0.7, cy + dy * 0.7, cz + dz * 0.7 - 0.04)
        setElementRotation(body, 0, 0, heading)
        attachElements(shackle, body)
        s = { itemId = itemId, shut = shut, body = body, shackle = shackle, sel = 1, dials = {} }
        s.savedCode = savedCode
        s.start = { px, py, pz }
        for i = 1, 4 do
            s.dials[i] = tonumber(tostring(dials or "0000"):sub(i, i)) or 0
        end
        poseShackle(shut and 0 or RAISE, shut and 0 or TURN)
        s.rt = dxCreateRenderTarget(RT_W, RT_H, true)
        s.shader = s.rt and dxCreateShader("client/replace.fx") or nil
        if s.shader then
            dxSetShaderValue(s.shader, "Tex", s.rt)
            engineApplyShaderToWorldTexture(s.shader, DIGIT_TEXTURE, body)
        end
        drawDials()
        s.pan = { from = { getCameraMatrix() }, start = getTickCount() }
        setNearClipDistance(0.02) -- the default 0.3 m would cut the padlock away 0.2 m from the camera
    end

    local function turnDial(i, by)
        s.dials[i] = (s.dials[i] + by) % 10
        playSoundFrontEnd(1)
        drawDials()
    end

    addEventHandler("comboPadlockOpened", root, function(itemId, shut, dials, savedCode)
        open(itemId, shut == true, dials, savedCode)
    end)

    -- the server's answer to a push: moved false = a shut padlock on the wrong code, the shackle only gives a little
    addEventHandler("comboPadlockChanged", root, function(itemId, shut, moved, savedCode)
        if not s or s.itemId ~= itemId then
            return
        end
        if moved == nil then
            s.savedCode = savedCode
            return
        end
        s.savedCode = savedCode
        s.busy = nil
        if not moved then
            playSoundFrontEnd(4)
            return animate({ { -0.0015, 0, 90 }, { 0, 0, 110 } })
        end
        s.shut = shut
        if shut then
            playSoundFrontEnd(1)
            animate({ { RAISE, 0, 260 }, { 0, 0, 160 } })
        else
            playSoundFrontEnd(12)
            animate({ { -0.002, 0, 90 }, { RAISE, 0, 110 }, { RAISE, TURN, 320 } })
        end
    end)

    addEventHandler("onClientKey", root, function(key, press)
        if not s or not press or isChatBoxInputActive() or isConsoleActive() then
            return
        end
        local digit = key:match("^num_(%d)$") or key:match("^(%d)$")
        if key == "escape" then
            cancelEvent()
            return close()
        elseif key == "arrow_l" then
            s.sel = s.sel == 1 and 4 or s.sel - 1
            drawDials()
        elseif key == "arrow_r" then
            s.sel = s.sel % 4 + 1
            drawDials()
        elseif key == "arrow_u" or key == "mouse_wheel_up" then
            turnDial(s.sel, 1)
        elseif key == "arrow_d" or key == "mouse_wheel_down" then
            turnDial(s.sel, -1)
        elseif digit then
            s.dials[s.sel] = tonumber(digit)
            s.sel = s.sel % 4 + 1
            playSoundFrontEnd(1)
            drawDials()
        elseif key == "s" then
            for i = 1, 4 do
                s.dials[i] = math.random(0, 9)
            end
            playSoundFrontEnd(1)
            drawDials()
        elseif key == "space" then
            if not s.anim and not s.busy then
                s.busy = true
                triggerServerEvent("comboPadlockActed", localPlayer, s.itemId, "push", dialString())
            end
        elseif key == "r" then
            if not s.shut then
                triggerServerEvent("comboPadlockActed", localPlayer, s.itemId, "set", dialString())
            end
        else
            return
        end
        cancelEvent()
    end)

    addEventHandler("onClientRestore", root, function()
        drawDials()
    end)

    addEventHandler("onClientPreRender", root, function()
        if not s then
            return
        end
        local px, py, pz = getElementPosition(localPlayer)
        local sx, sy, sz = unpack(s.start)
        if getDistanceBetweenPoints3D(px, py, pz, sx, sy, sz) > WALK_AWAY or isPedDead(localPlayer) then
            return close()
        end
        local now = getTickCount()
        local a = s.anim
        if a then
            local key = a.keys[a.i]
            local f = math.min(1, (now - a.start) / key[3])
            local e = ease(f)
            poseShackle(lerp(a.from[1], key[1], e), lerp(a.from[2], key[2], e))
            if f >= 1 then
                a.i, a.from, a.start = a.i + 1, { key[1], key[2] }, now
                if not a.keys[a.i] then
                    s.anim = nil
                end
            end
        end
        local to = cameraPose()
        local p = s.pan
        local f = p and ease(math.min(1, (now - p.start) / PAN_MS)) or 1
        local m = {}
        for i = 1, 8 do
            m[i] = p and lerp(p.from[i] or to[i], to[i], f) or to[i]
        end
        setCameraMatrix(unpack(m))
    end)

    addEventHandler("onClientRender", root, function()
        if not s then
            return
        end
        local sw, sh = guiGetScreenSize()
        local lines = { lang.text(HINTS.dials), lang.text(s.shut and HINTS.shut or HINTS.open) }
        if not s.shut and s.savedCode then
            table.insert(lines, 1, lang.format("Saved combination: %s", s.savedCode))
        end
        for i, text in ipairs(lines) do
            local y = sh - 26 - #lines * 22 + (i - 1) * 22
            dxDrawText(text, 1, y + 1, sw + 1, y + 21, tocolor(0, 0, 0, 200), 1.1, "default-bold", "center")
            dxDrawText(text, 0, y, sw, y + 20, tocolor(255, 255, 255, 235), 1.1, "default-bold", "center")
        end
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        if s then
            close(true)
        end
    end)

    return {
        isOpen = function()
            return s ~= nil
        end,
    }
end
