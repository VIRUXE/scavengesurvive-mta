-- Server side of threading the lug nuts. The client reports wrench radians; the wheel comes off, or
-- a wheel laid beside the vehicle goes on, only once every nut has reached the end of its thread.
return function(ctx)
    local lug, wheels = ctx.lug, ctx.wheels
    local log, vehicleLine = ctx.log, ctx.vehicleLine
    local db, info, activeActions = ctx.db, ctx.info, ctx.activeActions
    local cancel, toast, lang = ctx.cancel, ctx.toast, ctx.lang
    local updateWheelFreeze, snapshot = ctx.updateWheelFreeze, ctx.snapshot

    local function stillThere(player, action)
        local vehicle = action.vehicle
        if not isElement(player) or not isElement(vehicle) or not info[vehicle] or isPedDead(player) then
            return false
        end
        local held = exports.items:getHeld(player)
        if
            not held
            or held.id ~= action.heldId
            or held.uname ~= "Wrench"
            or getPedOccupiedVehicle(player)
            or getElementDimension(player) ~= getElementDimension(vehicle)
            or getElementInterior(player) ~= getElementInterior(vehicle)
        then
            return false
        end
        local x, y, z = getElementPosition(player)
        if getDistanceBetweenPoints3D(x, y, z, action.x, action.y, action.z) > 0.8 then
            return false
        end
        -- the vehicle must stay put. Its position is compared rather than its velocity: a parked vehicle
        -- resting on a bare hub keeps the last velocity its syncer sent, which never settles to zero
        local vx, vy, vz = getElementPosition(vehicle)
        return getDistanceBetweenPoints3D(vx, vy, vz, action.vx, action.vy, action.vz) <= 0.5
    end

    local function finish(player)
        local action = activeActions[player]
        if not action or action.actionType ~= "wheel" or action.finishing then
            return
        end
        if not lug.allDone(action.states, action.sign) then
            return
        end
        action.finishing = true
        local vehicle, wheel, removing = action.vehicle, action.wheel, action.removing
        local tires = action.tires
        local inf = info[vehicle]
        cancel(player)
        if not isElement(vehicle) or not inf then
            return
        end
        local current = { getVehicleWheelStates(vehicle) }
        if current[wheel] ~= tires[wheel] then
            return
        end
        local x, y, z = getElementPosition(player)

        local function fitted()
            if not isElement(vehicle) or info[vehicle] ~= inf then
                return
            end
            current[wheel] = removing and 2 or (wheels.isFlat(action.wheelUname) and 1 or 0)
            setVehicleWheelStates(vehicle, unpack(current))
            if not removing and current[wheel] == 0 then
                triggerClientEvent(root, "vehicleWheelInstalled", vehicle, wheel)
            end
            updateWheelFreeze(vehicle)
            inf.damage = snapshot(vehicle)
            db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { toJSON(inf.damage), inf.id })
            if isElement(player) then
                exports.character:gainSkill(player, "Repair")
            end
        end

        if removing then
            -- a burst tyre comes off as the flat twin of the vehicle's wheel style
            local model = getElementModel(vehicle)
            local uname = wheels.itemFor(model, tires[wheel] == 1, getVehicleType(vehicle) == "Automobile")
            db.exec(
                "INSERT INTO items (type_uname, x, y, z, rz, interior, dimension) VALUES (?, ?, ?, ?, 0, ?, ?)",
                { uname, x, y, z - 0.8, getElementInterior(player), getElementDimension(player) },
                function(ok, _, _, id)
                    if ok and isElement(vehicle) then
                        fitted()
                        exports.items:resendWorldItem(tonumber(id))
                        log.event(
                            "vehicle.wheelRemoved",
                            vehicleLine(
                                vehicle,
                                { player = player, wheel = wheel, item_id = tonumber(id), uname = uname }
                            )
                        )
                    end
                end
            )
        else
            -- the wheel found when the job began is the one that goes on
            db.exec(
                "DELETE FROM items WHERE id = ? AND holder_char_id IS NULL AND container_id IS NULL",
                { action.wheelItemId },
                function(ok, _, affected)
                    if ok and tonumber(affected) == 1 then
                        exports.items:forgetWorldItem(tonumber(action.wheelItemId))
                        if isElement(vehicle) then
                            fitted()
                            log.event(
                                "vehicle.wheelFitted",
                                vehicleLine(vehicle, {
                                    player = isElement(player) and player or nil,
                                    wheel = wheel,
                                    item_id = action.wheelItemId,
                                    uname = action.wheelUname,
                                })
                            )
                        end
                    elseif isElement(player) then
                        toast(player, "WHEEL_LAY")
                    end
                end
            )
        end
    end

    local function start(player, vehicle, wheel, removing, held, px, py, pz, tires, fit)
        local count = ctx.lugCount(getElementModel(vehicle))
        local states = {}
        for _ = 1, count do
            states[#states + 1] = removing and 1 or 0
        end
        local scaled = exports.character:skillTimeModifier(player, 1000, "Repair")
        local turn = lug.TURN * (scaled / 1000)
        local sign = removing and -1 or 1
        local vx, vy, vz = getElementPosition(vehicle)
        local title = removing and lang.formatFor(player, "Removing wheel: %d lug nuts", count)
            or lang.formatFor(player, "Installing wheel: %d lug nuts", count)
        local action = {
            actionType = "wheel",
            vehicle = vehicle,
            wheel = wheel,
            removing = removing,
            tires = tires,
            wheelItemId = fit and fit.id,
            wheelUname = fit and fit.uname,
            heldId = held.id,
            states = states,
            sign = sign,
            turn = turn,
            x = px,
            y = py,
            z = pz,
            vx = vx,
            vy = vy,
            vz = vz,
        }
        activeActions[player] = action
        setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
        triggerClientEvent(
            player,
            "lugnutsStarted",
            vehicle,
            count,
            sign,
            turn,
            wheel,
            title,
            states,
            fit and wheels.modelFor(fit.uname) or nil
        )
        action.timer = setTimer(function()
            local current = activeActions[player]
            if current ~= action then
                return
            end
            if not stillThere(player, action) then
                cancel(player)
            end
        end, 200, 0)
    end

    -- Taking a wheel off starts at once. Fitting needs a wheel laid within 3 m: a good one goes on before a flat one
    -- (a flat just taken off lies at the player's feet), the nearest of its kind, and
    -- the job is refused up front when there is none, so nobody turns every nut for nothing.
    local function begin(player, vehicle, wheel, removing, held, px, py, pz, tires)
        if removing then
            return start(player, vehicle, wheel, removing, held, px, py, pz, tires)
        end
        db.query(
            "SELECT id, type_uname FROM items WHERE type_uname IN ("
                .. wheels.sqlList()
                .. ") AND holder_char_id IS NULL AND container_id IS NULL AND interior = ? AND dimension = ?"
                .. " AND POW(x - ?, 2) + POW(y - ?, 2) + POW(z - ?, 2) < 9"
                .. " ORDER BY type_uname LIKE '%Flat', POW(x - ?, 2) + POW(y - ?, 2) + POW(z - ?, 2) LIMIT 1",
            {
                getElementInterior(player),
                getElementDimension(player),
                px,
                py,
                pz,
                px,
                py,
                pz,
            },
            function(rows)
                if not isElement(player) then
                    return
                end
                local row = rows and rows[1]
                if not row then
                    return toast(player, "WHEEL_LAY")
                end
                -- the player may have moved on, started other work or let go of the Wrench meanwhile
                local current = isElement(vehicle) and info[vehicle]
                local heldNow = exports.items:getHeld(player)
                if not current or activeActions[player] or not heldNow or heldNow.id ~= held.id then
                    return
                end
                start(
                    player,
                    vehicle,
                    wheel,
                    removing,
                    held,
                    px,
                    py,
                    pz,
                    tires,
                    { id = row.id, uname = row.type_uname }
                )
            end
        )
    end

    local net = ctx.net
    net.handler("lugnutTurnRequested", function(player, index, delta)
        local action = activeActions[player]
        if not action or action.actionType ~= "wheel" or action.finishing then
            return
        end
        if not stillThere(player, action) then
            return cancel(player)
        end
        index = tonumber(index)
        delta = tonumber(delta)
        if not index or not delta or delta ~= delta then
            return
        end
        index = math.floor(index)
        if index < 1 or index > #action.states then
            return
        end
        if delta > lug.MAX_STEP then
            delta = lug.MAX_STEP
        elseif delta < -lug.MAX_STEP then
            delta = -lug.MAX_STEP
        end
        local progress = lug.apply(action.states[index], delta, action.sign, action.turn)
        action.states[index] = progress
        triggerClientEvent(player, "lugnutTurned", player, index, progress)
        if lug.allDone(action.states, action.sign) then
            finish(player)
        end
    end, { rate = 20 })

    return { begin = begin }
end
