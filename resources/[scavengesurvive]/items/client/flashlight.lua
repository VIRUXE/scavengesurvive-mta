-- luacheck: read globals createLight playSFX getPedSimplestTask getElementBoneRotation getCameraMatrix
-- luacheck: read globals setMarkerColor
-- The Flashlight on every client (shared/logic/flashlight.lua has the numbers, server/flashlight.lua who has one on:
-- "items.torch" element data). While a player's is on, client/attach.lua calls in here each frame:
--   pose: the right arm comes up to point it ahead (bone rotations blended in over the animation playing, so the legs
--     keep walking), before the held object is placed on the hand;
--   shine: the beam leaves the placed object's lens along its axis (held near the way the player faces, so a run's
--     lean does not throw it at their feet): walls, ground and objects through the world
--     resource's blackout shader (world:setLight), peds and vehicles through a GTA point light down the beam
--     (createLight), and the lens glows (a corona) for whoever it looks toward.
-- The goggles key (the "goggles" command, J unless rebound) switches a held one on or off. With goggles worn as well
-- the key is shared: a tap is the Flashlight's, holding it HOLD_MS switches the goggles (client/goggles.lua leaves
-- the key alone while takesKey() says so).
-- ctx = { flashlight }
return function(ctx)
    local flashlight = ctx.flashlight
    local CLICK = { "genrl", 143, 64 } -- GTA's own goggles click (client/goggles.lua)
    local HOLD_MS = 300 -- the hud's own tap or hold threshold (hud/client/keys.lua)
    local holdTimer

    local on = {} -- player -> "items.torch", kept ahead of the element data (the change event fires before it changes)
    local raised = {} -- player -> { t = 0 .. 1 how far the arm is up, tick }
    local beams = {} -- player -> { id, light, corona, dx, dy, dz, tick, interior, dimension }
    local nextId = 0
    local worldUp, worldChecked = false, 0

    local function isOn(player)
        if on[player] == nil then
            on[player] = getElementData(player, "items.torch") == true
        end
        return on[player]
    end

    local function hasWorld()
        local now = getTickCount()
        if now - worldChecked > 1000 then
            worldChecked = now
            local res = getResourceFromName("world")
            worldUp = res and getResourceState(res) == "running" or false
        end
        return worldUp
    end

    local function drop(player)
        local b = beams[player]
        if not b then
            return
        end
        beams[player] = nil
        if isElement(b.light) then
            destroyElement(b.light)
        end
        if isElement(b.corona) then
            destroyElement(b.corona)
        end
        if hasWorld() then
            exports.world:removeLight(b.id)
        end
    end

    local function holds(player, held)
        return held ~= nil
            and held.uname == flashlight.UNAME
            and isElement(held.obj)
            and not isPedDead(player)
            and not isPedInVehicle(player)
    end

    -- held: the player's held attachment (client/attach.lua) or nil. Called before the attachments are placed.
    local function pose(player, held)
        local r = raised[player]
        if not holds(player, held) then
            raised[player] = nil
            return
        end
        local up = isOn(player)
            and not getPedAnimation(player)
            and not flashlight.NO_POSE_TASKS[getPedSimplestTask(player) or ""]
        if not r then
            if not up then
                return
            end
            r = { t = 0, tick = getTickCount() }
            raised[player] = r
        end
        local now = getTickCount()
        local step = (now - r.tick) / flashlight.RAISE_MS
        r.tick = now
        r.t = math.max(0, math.min(1, r.t + (up and step or -step)))
        if r.t <= 0 then
            raised[player] = nil
            return
        end
        local t = r.t * r.t * (3 - 2 * r.t)
        for bone, rot in pairs(flashlight.POSE) do
            local x, y, z = getElementBoneRotation(player, bone)
            if x then
                local a = flashlight.blend({ x, y, z }, rot, t)
                setElementBoneRotation(player, bone, a[1], a[2], a[3])
            end
        end
        updateElementRpHAnim(player)
    end

    -- Called after the attachments are placed: the light follows the object in the hand.
    local function shine(player, held)
        if not holds(player, held) or not isOn(player) then
            return drop(player)
        end
        local x, y, z, dx, dy, dz = flashlight.lensPose(getElementMatrix(held.obj))
        local facing = getElementMatrix(player)[2]
        dx, dy, dz = flashlight.steady(dx, dy, dz, facing[1], facing[2])
        local now = getTickCount()
        local b = beams[player]
        if not b then
            nextId = nextId + 1
            b = { id = "torch:" .. nextId, dx = dx, dy = dy, dz = dz, tick = now }
            beams[player] = b
        end
        local k = 1 - math.exp(-(now - b.tick) / flashlight.STEADY_MS)
        b.tick = now
        dx, dy, dz = b.dx + (dx - b.dx) * k, b.dy + (dy - b.dy) * k, b.dz + (dz - b.dz) * k
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 0.001 then
            return
        end
        dx, dy, dz = dx / len, dy / len, dz / len
        b.dx, b.dy, b.dz = dx, dy, dz
        local int, dim = getElementInterior(player), getElementDimension(player)
        local moved = int ~= b.interior or dim ~= b.dimension
        b.interior, b.dimension = int, dim
        local ahead = flashlight.PED_LIGHT_AHEAD
        local lx, ly, lz = x + dx * ahead, y + dy * ahead, z + dz * ahead
        if not isElement(b.light) then
            b.light = createLight(0, lx, ly, lz, flashlight.PED_LIGHT_RADIUS, 255, 242, 210) or nil
            moved = true
        end
        if not isElement(b.corona) then
            b.corona = createMarker(x, y, z, "corona", 0.12, 255, 244, 220, 0) or nil
            b.alpha = 0
            moved = true
        end
        if b.light then
            setElementPosition(b.light, lx, ly, lz)
        end
        if b.corona then
            setElementPosition(b.corona, x + dx * 0.02, y + dy * 0.02, z + dz * 0.02)
            -- GTA draws a corona through peds: the glow is only for a camera the lens looks toward, or it would
            -- show through the holder's own body from behind
            local cx, cy, cz = getCameraMatrix()
            local vx, vy, vz = cx - x, cy - y, cz - z
            local dist = math.sqrt(vx * vx + vy * vy + vz * vz)
            local toward = dist > 0.001 and (vx * dx + vy * dy + vz * dz) / dist or 0
            local alpha = flashlight.glowAlpha(toward)
            if alpha ~= b.alpha then
                b.alpha = alpha
                setMarkerColor(b.corona, 255, 244, 220, alpha)
            end
        end
        if moved then
            for _, e in ipairs({ b.light or false, b.corona or false }) do
                if e then
                    setElementInterior(e, int)
                    setElementDimension(e, dim)
                end
            end
        end
        if hasWorld() then
            local c, cone = flashlight.COLOUR, flashlight.CONE
            exports.world:setLight(
                b.id,
                x,
                y,
                z,
                dx,
                dy,
                dz,
                flashlight.RADIUS,
                c[1],
                c[2],
                c[3],
                int,
                dim,
                cone[1],
                cone[2]
            )
        end
    end

    local function forget(player)
        drop(player)
        on[player] = nil
        raised[player] = nil
    end

    -- whether the goggles key is the local player's Flashlight's now
    local function takesKey()
        return getElementData(localPlayer, "items.held") == flashlight.UNAME
            and not isPedDead(localPlayer)
            and not isPedInVehicle(localPlayer)
    end

    -- the key (or the dev resource's rcon press) is still down
    local function keyHeld()
        local key = string.lower(getKeyBoundToCommand("goggles") or "j")
        if getKeyState(key) then
            return true
        end
        local dev = getResourceFromName("dev")
        return dev and getResourceState(dev) == "running" and exports.dev:isHeld("goggles") == true
    end

    addCommandHandler("goggles", function()
        if not takesKey() or isTimer(holdTimer) then
            return
        end
        if not getElementData(localPlayer, "items.eyes") then
            return triggerServerEvent("flashlightToggleRequested", localPlayer)
        end
        local startTick = getTickCount()
        holdTimer = setTimer(function()
            local held = keyHeld()
            if held and getTickCount() - startTick < HOLD_MS then
                return
            end
            killTimer(holdTimer)
            holdTimer = nil
            triggerServerEvent(held and "gogglesToggleRequested" or "flashlightToggleRequested", localPlayer)
        end, 50, 0)
    end)

    addEventHandler("onClientElementDataChange", root, function(key, _, value)
        if key ~= "items.torch" or getElementType(source) ~= "player" then
            return
        end
        on[source] = value == true
        if source == localPlayer then
            local sound = playSFX(unpack(CLICK))
            if sound then
                setSoundVolume(sound, 0.6)
            end
        end
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        if isTimer(holdTimer) then
            killTimer(holdTimer)
        end
        for player in pairs(beams) do
            drop(player)
        end
    end)

    return { pose = pose, shine = shine, forget = forget, takesKey = takesKey }
end
