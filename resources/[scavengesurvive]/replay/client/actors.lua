-- Ghost peds and vehicles for a replay: one ped per character with samples, one vehicle per recorded vehicle track,
-- driven every frame from the interpolated samples (shared/logic/interp.lua). The peds are local to this client,
-- frozen and without collision, so they cannot hurt or block anyone; shots are a flash and a tracer, never a bullet.
return function(ctx)
    local interp = ctx.interp
    local M = {}

    local ANIM = {
        walk = { "ped", "WALK_player" },
        run = { "ped", "run_player" },
        sprint = { "ped", "sprint_civi" },
        jump = { "ped", "JUMP_glide" },
        fall = { "ped", "FALL_fall" },
        swim = { "swim", "Swim_Tread" },
        climb = { "ped", "CLIMB_idle" },
    }
    local SUBJECT_ALPHA, OTHER_ALPHA, VEHICLE_ALPHA = 230, 110, 190
    local VEHICLE_TAIL_MS = 3000 -- a vehicle track's ghost stays this long after its last sample

    local ghostSet = setmetatable({}, { __mode = "k" }) -- every element this module made
    local peds = {} -- char_id -> { ped, anim, weapon, aiming, crouched, lastSample, vehicle, name, state }
    local vehicles = {} -- key -> { vehicle, model }
    local tracers = {} -- { x1, y1, z1, x2, y2, z2, untilTick }
    local muzzle = {} -- effects to clean

    local function destroyPed(g)
        if isElement(g.ped) then
            destroyElement(g.ped)
        end
    end

    function M.clear()
        for _, g in pairs(peds) do
            destroyPed(g)
        end
        for _, v in pairs(vehicles) do
            if isElement(v.vehicle) then
                destroyElement(v.vehicle)
            end
        end
        for _, fx in ipairs(muzzle) do
            if isElement(fx.el) then
                destroyElement(fx.el)
            end
        end
        peds, vehicles, tracers, muzzle = {}, {}, {}, {}
    end

    function M.isGhost(el)
        return ghostSet[el] == true
    end

    local function ghostify(el, alpha)
        ghostSet[el] = true
        setElementAlpha(el, alpha)
        setElementCollisionsEnabled(el, false)
        setElementFrozen(el, true)
    end

    local function createGhostPed(char, actor)
        local ped = createPed(actor.skin or 0, 0, 0, 0)
        if not ped then
            return nil
        end
        ghostify(ped, actor.role == "subject" and SUBJECT_ALPHA or OTHER_ALPHA)
        setPedWalkingStyle(ped, 0)
        return { ped = ped, char = char, name = actor.name or ("#" .. tostring(char)), role = actor.role }
    end

    local function setAnim(g, key, block, name)
        if g.anim == key then
            return
        end
        g.anim = key
        if block then
            setPedAnimation(g.ped, block, name, -1, true, false, false, false, 250)
        else
            setPedAnimation(g.ped)
        end
    end

    local function applyWeapon(g, st)
        local w = tonumber(st.weapon) or 0
        if g.weapon ~= w then
            g.weapon = w
            takeAllWeapons(g.ped)
            if w > 0 then
                giveWeapon(g.ped, w, 900, true)
            end
        end
        local aim = st.aim
        local aiming = w > 0 and type(aim) == "table" and (aim.x or aim[1]) ~= nil
        if aiming then
            local ax, ay, az = aim.x or aim[1], aim.y or aim[2], aim.z or aim[3]
            setPedControlState(g.ped, "aim_weapon", true)
            setPedAimTarget(g.ped, ax, ay, az)
            g.aimAt = { ax, ay, az }
        elseif g.aiming then
            setPedControlState(g.ped, "aim_weapon", false)
            g.aimAt = nil
        end
        g.aiming = aiming
    end

    -- a shot: gunflash at the muzzle and a short tracer towards the aim point (or 40 m ahead)
    local function shoot(g, x, y, z, rz)
        local rad = math.rad(rz or 0)
        local fx, fy = -math.sin(rad), math.cos(rad)
        local mx, my, mz = x + fx * 0.7, y + fy * 0.7, z + 0.25
        local el = createEffect("gunflash", mx, my, mz, 0, 0, rz or 0)
        if el then
            muzzle[#muzzle + 1] = { el = el, untilTick = getTickCount() + 150 }
        end
        local tx, ty, tz
        if g.aimAt then
            tx, ty, tz = g.aimAt[1], g.aimAt[2], g.aimAt[3]
        else
            tx, ty, tz = x + fx * 40, y + fy * 40, mz
        end
        tracers[#tracers + 1] = { mx, my, mz, tx, ty, tz, untilTick = getTickCount() + 180 }
    end

    local function setPlace(el, st)
        setElementInterior(el, st.int or 0)
        setElementDimension(el, st.dim or 0)
    end

    local function updatePed(g, st, track)
        local veh = st.veh and vehicles[st.veh]
        local inCar = veh and isElement(veh.vehicle)
        if inCar then
            if getPedOccupiedVehicle(g.ped) ~= veh.vehicle then
                setPlace(g.ped, st)
                warpPedIntoVehicle(g.ped, veh.vehicle, tonumber(st.seat) or 0)
            end
            g.anim = nil
        else
            if getPedOccupiedVehicle(g.ped) then
                removePedFromVehicle(g.ped)
            end
            setPlace(g.ped, st)
            setElementPosition(g.ped, st.x, st.y, st.z)
            setElementRotation(g.ped, 0, 0, st.rz or g.rz or 0)
            g.rz = st.rz or g.rz
            local move = interp.moveState(st, interp.speed(track, st.t or 0))
            local pose = ANIM[move]
            if st.anim and st.anim ~= "" then
                local block, name = tostring(st.anim):match("^(.-)|(.+)$")
                if block then
                    setAnim(g, st.anim, block, name)
                end
            elseif pose and not st.gap then
                setAnim(g, move, pose[1], pose[2])
            else
                setAnim(g, "stand")
            end
            local crouch = move == "crouch"
            if g.crouched ~= crouch then
                g.crouched = crouch
                setPedControlState(g.ped, "crouch", crouch)
            end
        end
        applyWeapon(g, st)
        if st.hp then
            setElementHealth(g.ped, math.max(1, math.min(100, st.hp)))
        end
        g.state = st
        -- one shot per sample that carries `fire`
        if st.sample ~= g.lastSample then
            g.lastSample = st.sample
            if st.sample and st.sample.fire and g.weapon and g.weapon > 0 then
                shoot(g, st.x, st.y, st.z, st.rz)
            end
        end
    end

    local function updateVehicle(key, v, t)
        local st = interp.at(v.samples, t)
        local last = v.samples[#v.samples]
        local live = st and last and t <= last.t + VEHICLE_TAIL_MS
        local g = vehicles[key]
        if not live then
            if g then
                if isElement(g.vehicle) then
                    destroyElement(g.vehicle)
                end
                vehicles[key] = nil
            end
            return
        end
        if not g or not isElement(g.vehicle) then
            local el = createVehicle(v.model or 411, st.x, st.y, st.z)
            if not el then
                return
            end
            ghostify(el, VEHICLE_ALPHA)
            setVehicleDamageProof(el, true)
            local c = v.colors
            if type(c) == "table" and #c >= 12 then
                setVehicleColor(el, c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
            elseif type(c) == "table" and #c >= 4 then
                setVehicleColor(el, c[1], c[2], c[3], c[4])
            end
            g = { vehicle = el }
            vehicles[key] = g
        end
        setPlace(g.vehicle, st)
        setElementPosition(g.vehicle, st.x, st.y, st.z)
        setElementRotation(g.vehicle, st.rx or 0, st.ry or 0, st.rz or 0)
        if st.hp then
            setElementHealth(g.vehicle, math.max(250, st.hp))
        end
    end

    -- t: replay time in ms; session: { actors, vehicles }
    function M.update(t, session)
        for key, v in pairs(session.vehicles or {}) do
            updateVehicle(key, v, t)
        end
        for char, actor in pairs(session.actors or {}) do
            local st = interp.at(actor.samples, t)
            local g = peds[char]
            if not st then
                if g then
                    destroyPed(g)
                    peds[char] = nil
                end
            else
                if not g or not isElement(g.ped) then
                    g = createGhostPed(char, actor)
                    peds[char] = g
                end
                if g then
                    st.t = t
                    updatePed(g, st, actor.samples)
                end
            end
        end
        local now = getTickCount()
        for i = #muzzle, 1, -1 do
            if now >= muzzle[i].untilTick then
                if isElement(muzzle[i].el) then
                    destroyElement(muzzle[i].el)
                end
                table.remove(muzzle, i)
            end
        end
        for i = #tracers, 1, -1 do
            if now >= tracers[i].untilTick then
                table.remove(tracers, i)
            end
        end
    end

    -- where the actor is drawn now: x, y, z, rz, interior, or nil
    function M.where(char)
        local g = peds[char]
        local st = g and g.state
        if not st then
            return nil
        end
        local x, y, z
        if isElement(g.ped) and getPedOccupiedVehicle(g.ped) then
            x, y, z = getElementPosition(g.ped)
        else
            x, y, z = st.x, st.y, st.z
        end
        return x, y, z, st.rz, st.int or 0, st.dim or 0
    end

    function M.state(char)
        local g = peds[char]
        return g and g.state, g
    end

    function M.drawTracers()
        for _, tr in ipairs(tracers) do
            dxDrawLine3D(tr[1], tr[2], tr[3], tr[4], tr[5], tr[6], tocolor(255, 220, 120, 230), 2)
        end
    end

    -- name tags over the ghosts: name, health, held weapon
    function M.drawTags(focusChar)
        local cx, cy, cz = getCameraMatrix()
        for char, g in pairs(peds) do
            local st = g.state
            if st and isElement(g.ped) then
                local x, y, z = getElementPosition(g.ped)
                local dx, dy, dz = x - cx, y - cy, z - cz
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d < 120 then
                    local sx, sy = getScreenFromWorldPosition(x, y, z + 1.15, 0.1, false)
                    if sx then
                        local subject = g.role == "subject"
                        local color = subject and tocolor(255, 120, 90, 255) or tocolor(200, 200, 200, 230)
                        local scale = math.max(0.7, math.min(1.4, 18 / math.max(d, 6)))
                        local text = g.name
                        if st.hp then
                            text = text .. string.format("  %d hp", st.hp)
                        end
                        if g.weapon and g.weapon > 0 then
                            text = text .. "  [" .. (getWeaponNameFromID(g.weapon) or g.weapon) .. "]"
                        end
                        if char == focusChar then
                            text = "> " .. text
                        end
                        dxDrawText(
                            text,
                            sx + 1,
                            sy + 1,
                            sx + 1,
                            sy + 1,
                            tocolor(0, 0, 0, 220),
                            scale,
                            "default-bold",
                            "center",
                            "bottom"
                        )
                        dxDrawText(text, sx, sy, sx, sy, color, scale, "default-bold", "center", "bottom")
                    end
                end
            end
        end
    end

    return M
end
