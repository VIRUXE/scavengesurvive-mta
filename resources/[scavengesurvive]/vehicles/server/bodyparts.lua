-- Native Bobcat components: held salvage is consumed atomically with its persisted damage state.
return function(ctx)
    local M, pending = {}, setmetatable({}, { __mode = "k" })
    local slots = {
        Tailgate = { door = 1, x = 0, y = -2.2 },
        LeftDoor = { door = 2, x = -1.05, y = 0.25 },
        RightDoor = { door = 3, x = 1.05, y = 0.25 },
        Hood = { door = 0, x = 0, y = 1.4 },
        FrontBumper = { panel = 5, x = 0, y = 2.25 },
        RearBumper = { panel = 6, x = 0, y = -2.35 },
    }
    local parts = {}
    for name, slot in pairs(slots) do
        parts["Bobcat" .. name .. "Good"] = { slot = slot, name = name, good = true }
        parts["Bobcat" .. name .. "Bad"] = { slot = slot, name = name, good = false }
    end

    function M.isPart(uname)
        return parts[uname] ~= nil
    end

    function M.busy(vehicle)
        local action = pending[vehicle]
        if action and not action.committing and ctx.activeActions[action.player] ~= action then
            pending[vehicle] = nil
        end
        return pending[vehicle] ~= nil
    end

    function M.snapshot(vehicle)
        local d = { panels = {}, doors = {}, lights = {}, tires = { getVehicleWheelStates(vehicle) } }
        for i = 0, 6 do
            d.panels[i + 1] = getVehiclePanelState(vehicle, i)
        end
        for i = 2, 5 do
            d.doors[i - 1] = getVehicleDoorState(vehicle, i)
        end
        for i = 0, 3 do
            d.lights[i + 1] = getVehicleLightState(vehicle, i)
        end
        d.hood, d.tailgate = getVehicleDoorState(vehicle, 0), getVehicleDoorState(vehicle, 1)
        return d
    end

    local function state(vehicle, part)
        local slot = part.slot
        if slot.door then
            return getVehicleDoorState(vehicle, slot.door)
        end
        return getVehiclePanelState(vehicle, slot.panel)
    end

    local function improves(vehicle, part)
        local current = state(vehicle, part)
        if part.good then
            return current ~= false and current >= (part.slot.door and 2 or 1)
        end
        return current == (part.slot.door and 4 or 3)
    end

    local function canFit(player, vehicle, part)
        if not isElement(player) or not isElement(vehicle) or not ctx.info[vehicle] then
            return false
        end
        if
            getElementModel(vehicle) ~= 422
            or isVehicleBlown(vehicle)
            or isPedDead(player)
            or getPedOccupiedVehicle(player)
            or getVehicleEngineState(vehicle)
            or ctx.info[vehicle].locked > 0
        then
            return false
        end
        if
            getElementDimension(player) ~= getElementDimension(vehicle)
            or getElementInterior(player) ~= getElementInterior(vehicle)
        then
            return false
        end
        local vx, vy, vz = getElementVelocity(vehicle)
        if vx * vx + vy * vy + vz * vz > 0.000025 then
            return false
        end
        local x, y, z = getElementPosition(player)
        local lx, ly, lz = ctx.toLocal(getElementMatrix(vehicle), x, y, z)
        local slot = part.slot
        return (lx - slot.x) ^ 2 + (ly - slot.y) ^ 2 <= 1.8 ^ 2 and math.abs(lz) < 2
    end

    function M.install(player, vehicle, held)
        local part = parts[held.uname]
        if not part or ctx.activeActions[player] or M.busy(vehicle) then
            return
        end
        if not canFit(player, vehicle, part) then
            return ctx.toast(player, "Stand by the matching part of an unlocked, parked Bobcat with its engine off.")
        end
        if not improves(vehicle, part) then
            return ctx.toast(
                player,
                part.good and "That body part is already intact." or "A bad part can only replace a missing body part."
            )
        end
        local cid = exports.character:getCharacterId(player)
        if not cid then
            return
        end
        local startX, startY, startZ = getElementPosition(player)
        local duration = exports.character:skillTimeModifier(player, 4000, "Repair")
        local start = getTickCount()
        local action = { actionType = "bodypart", vehicle = vehicle, player = player }
        pending[vehicle] = action
        ctx.activeActions[player] = action
        setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
        triggerClientEvent(player, "vehicleHoldStarted", player, "Installing body part", duration)
        action.timer = setTimer(function()
            if ctx.activeActions[player] ~= action then
                return
            end
            local current = isElement(player) and exports.items:getHeld(player)
            local valid = current
                and current.id == held.id
                and current.uname == held.uname
                and exports.character:getCharacterId(player) == cid
                and canFit(player, vehicle, part)
            if valid then
                local x, y, z = getElementPosition(player)
                valid = getDistanceBetweenPoints3D(x, y, z, startX, startY, startZ) <= 0.8
            end
            if not valid or not improves(vehicle, part) then
                return ctx.cancel(player)
            end
            if getTickCount() - start < duration then
                return
            end
            killTimer(action.timer)
            action.timer = nil
            action.committing = true
            local inf = ctx.info[vehicle]
            local args =
                { inf.id, held.id, cid, held.uname, state(vehicle, part), toJSON(M.snapshot(vehicle), true):sub(2, -2) }
            ctx.db.call("bobcat_part_install", args, function(res)
                pending[vehicle] = nil
                if ctx.activeActions[player] == action then
                    ctx.cancel(player)
                end
                if not res or not res.ok then
                    if isElement(player) then
                        ctx.toast(player, "Could not install the body part; your item was kept.")
                    end
                    return
                end
                if isElement(vehicle) and ctx.info[vehicle] == inf then
                    local value = tonumber(res.payload.state)
                    if part.slot.door then
                        setVehicleDoorState(vehicle, part.slot.door, value, false)
                        setVehicleDoorOpenRatio(vehicle, part.slot.door, 0)
                    else
                        setVehiclePanelState(vehicle, part.slot.panel, value)
                    end
                    inf.damage = M.snapshot(vehicle)
                end
                if isElement(player) then
                    local now = exports.items:getHeld(player)
                    if now and now.id == held.id then
                        exports.items:clearHeld(player)
                    end
                    exports.items:refreshPlayer(player)
                    exports.character:gainSkill(player, "Repair")
                    ctx.toast(player, "Bobcat body part installed.")
                end
            end)
        end, 100, 0)
    end
    return M
end
