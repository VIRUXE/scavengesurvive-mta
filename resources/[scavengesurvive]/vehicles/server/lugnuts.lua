-- Server side of the lug-nut minigame. The client reports wrench radians; the wheel comes off, or
-- a wheel laid beside the vehicle goes on, only once every nut has reached the end of its thread.
return function(ctx)
    local lug = ctx.lug
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
            or getVehicleEngineState(vehicle)
            or info[vehicle].locked > 0
            or getElementDimension(player) ~= getElementDimension(vehicle)
            or getElementInterior(player) ~= getElementInterior(vehicle)
        then
            return false
        end
        local x, y, z = getElementPosition(player)
        local vx, vy, vz = getElementVelocity(vehicle)
        if getDistanceBetweenPoints3D(x, y, z, action.x, action.y, action.z) > 0.8 then
            return false
        end
        if vx * vx + vy * vy + vz * vz > 0.0001 then
            return false
        end
        return true
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
            current[wheel] = removing and 2 or 0
            setVehicleWheelStates(vehicle, unpack(current))
            if not removing then
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
            db.exec(
                "INSERT INTO items (type_uname, x, y, z, rz, interior, dimension) VALUES ('Wheel', ?, ?, ?, 0, ?, ?)",
                { x, y, z - 0.8, getElementInterior(player), getElementDimension(player) },
                function(ok, _, _, id)
                    if ok and isElement(vehicle) then
                        fitted()
                        exports.items:resendWorldItem(tonumber(id))
                    end
                end
            )
        else
            db.query(
                "SELECT id FROM items WHERE type_uname = 'Wheel' AND interior = ? AND dimension = ? AND POW(x - ?, 2) + POW(y - ?, 2) + POW(z - ?, 2) < 9 LIMIT 1",
                { getElementInterior(player), getElementDimension(player), x, y, z },
                function(rows)
                    if rows and rows[1] and isElement(vehicle) then
                        db.exec(
                            "DELETE FROM items WHERE id = ? AND holder_char_id IS NULL AND container_id IS NULL",
                            { rows[1].id },
                            function(ok, _, affected)
                                if ok and tonumber(affected) == 1 then
                                    exports.items:forgetWorldItem(tonumber(rows[1].id))
                                    if isElement(vehicle) then
                                        fitted()
                                    end
                                end
                            end
                        )
                    elseif isElement(player) then
                        toast(player, "WHEEL_LAY")
                    end
                end
            )
        end
    end

    local function begin(player, vehicle, wheel, removing, held, px, py, pz, tires)
        local count = ctx.lugCount(getElementModel(vehicle))
        local states = {}
        for _ = 1, count do
            states[#states + 1] = removing and 1 or 0
        end
        local scaled = exports.character:skillTimeModifier(player, 1000, "Repair")
        local turn = lug.TURN * (scaled / 1000)
        local sign = removing and -1 or 1
        local title = removing and lang.formatFor(player, "Removing wheel: %d lug nuts", count)
            or lang.formatFor(player, "Installing wheel: %d lug nuts", count)
        local action = {
            actionType = "wheel",
            vehicle = vehicle,
            wheel = wheel,
            removing = removing,
            tires = tires,
            heldId = held.id,
            states = states,
            sign = sign,
            turn = turn,
            x = px,
            y = py,
            z = pz,
        }
        activeActions[player] = action
        setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
        triggerClientEvent(player, "lugnutsStarted", vehicle, count, sign, turn, wheel, title, states)
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
        local blocked = lug.blocked(action.states, index, action.sign)
        local progress, seized = lug.apply(action.states[index], delta, action.sign, action.turn, blocked)
        action.states[index] = progress
        triggerClientEvent(player, "lugnutTurned", player, index, progress, seized)
        if lug.allDone(action.states, action.sign) then
            finish(player)
        end
    end, { rate = 20 })

    return { begin = begin }
end
