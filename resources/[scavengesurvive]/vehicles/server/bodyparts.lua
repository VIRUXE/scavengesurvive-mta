-- Removable body parts (doors, bonnet, boot, bumpers): a Wrench takes one off, a held part fits an empty slot, and
-- a part a crash knocked off lands on the ground as a Bad item. The slots per model are shared/logic/bodyparts.lua.
return function(ctx)
    local bp = ctx.bp
    local M, pending = {}, setmetatable({}, { __mode = "k" })
    local HOLD_MS = 4000
    local MAX_MOVE = 0.8
    local MAX_SPEED_SQ = 0.000025

    function M.isPart(uname)
        return bp.partOf(uname) ~= nil
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

    local function snapshotJson(vehicle)
        return toJSON(M.snapshot(vehicle), true):sub(2, -2) -- toJSON wraps its argument in a list
    end

    local function state(vehicle, slot)
        if slot.door then
            return getVehicleDoorState(vehicle, slot.door)
        end
        return getVehiclePanelState(vehicle, slot.panel)
    end

    local function setState(vehicle, slot, value)
        if slot.door then
            setVehicleDoorState(vehicle, slot.door, value, false)
            setVehicleDoorOpenRatio(vehicle, slot.door, 0)
        else
            setVehiclePanelState(vehicle, slot.panel, value)
        end
    end

    -- the vehicle is one a player may work on: a parked, unlocked, engine-off car of a model with slots
    local function workable(player, vehicle)
        if not isElement(player) or not isElement(vehicle) or not ctx.info[vehicle] then
            return false
        end
        if not bp.MODELS[getElementModel(vehicle)] or isVehicleBlown(vehicle) or isPedDead(player) then
            return false
        end
        if getPedOccupiedVehicle(player) or getVehicleEngineState(vehicle) or ctx.info[vehicle].locked > 0 then
            return false
        end
        local sameDim = getElementDimension(player) == getElementDimension(vehicle)
        if not sameDim or getElementInterior(player) ~= getElementInterior(vehicle) then
            return false
        end
        local vx, vy, vz = getElementVelocity(vehicle)
        return vx * vx + vy * vy + vz * vz <= MAX_SPEED_SQ
    end

    -- the player's point in the vehicle's frame; nil when they stand too far above or below it
    local function localPoint(player, vehicle)
        local x, y, z = getElementPosition(player)
        local lx, ly, lz = ctx.toLocal(getElementMatrix(vehicle), x, y, z)
        if math.abs(lz) >= 2 then
            return nil
        end
        return lx, ly
    end

    local function atSlot(player, vehicle, slot)
        local lx, ly = localPoint(player, vehicle)
        return lx ~= nil and (lx - slot.x) ^ 2 + (ly - slot.y) ^ 2 <= bp.REACH ^ 2
    end

    -- A timed hold on one slot: `ready()` is checked again every 100 ms, `commit(cid)` runs once the time is up.
    local function hold(player, vehicle, slot, held, label, ready, commit)
        local cid = exports.character:getCharacterId(player)
        if not cid then
            return
        end
        local startX, startY, startZ = getElementPosition(player)
        local duration = exports.character:skillTimeModifier(player, HOLD_MS, "Repair")
        local start = getTickCount()
        local action = { actionType = "bodypart", vehicle = vehicle, player = player }
        pending[vehicle] = action
        ctx.activeActions[player] = action
        setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
        triggerClientEvent(player, "vehicleHoldStarted", player, label, duration)
        action.timer = setTimer(function()
            if ctx.activeActions[player] ~= action then
                return
            end
            local current = isElement(player) and exports.items:getHeld(player)
            local valid = current and current.id == held.id and current.uname == held.uname
            valid = valid and exports.character:getCharacterId(player) == cid
            valid = valid and workable(player, vehicle) and atSlot(player, vehicle, slot) and ready()
            if valid then
                local x, y, z = getElementPosition(player)
                valid = getDistanceBetweenPoints3D(x, y, z, startX, startY, startZ) <= MAX_MOVE
            end
            if not valid then
                return ctx.cancel(player)
            end
            if getTickCount() - start < duration then
                return
            end
            killTimer(action.timer)
            action.timer = nil
            action.committing = true
            commit(action, cid)
        end, 100, 0)
    end

    -- run when the database call is back: free the vehicle and the player's action
    local function finished(vehicle, player, action)
        pending[vehicle] = nil
        if ctx.activeActions[player] == action then
            ctx.cancel(player)
        end
    end

    local function payloadOf(res)
        local p = res and res.payload
        return type(p) == "string" and fromJSON(p) or p
    end

    -- A held part goes into the empty slot it belongs to.
    function M.install(player, vehicle, held)
        local modelId, slot, good = bp.partOf(held.uname)
        if not modelId or ctx.activeActions[player] or M.busy(vehicle) then
            return
        end
        if
            not workable(player, vehicle)
            or getElementModel(vehicle) ~= modelId
            or not atSlot(player, vehicle, slot)
        then
            return ctx.toast(player, "PART_NOT_HERE")
        end
        if bp.condition(slot, state(vehicle, slot)) ~= "missing" then
            return ctx.toast(player, "PART_SLOT_TAKEN")
        end
        local function ready()
            return bp.condition(slot, state(vehicle, slot)) == "missing"
        end
        local function commit(action, cid)
            local inf = ctx.info[vehicle]
            local value = bp.installState(good)
            local args = { inf.id, held.id, cid, held.uname, modelId, slot.path, slot.missing, value }
            args[#args + 1] = snapshotJson(vehicle)
            ctx.db.call("vehicle_part_install", args, function(res)
                finished(vehicle, player, action)
                if not res or not res.ok then
                    return isElement(player) and ctx.toast(player, "PART_FAILED")
                end
                if isElement(vehicle) and ctx.info[vehicle] == inf then
                    setState(vehicle, slot, tonumber(payloadOf(res).state))
                    inf.damage = M.snapshot(vehicle)
                    inf.partMissing = inf.partMissing or {}
                    inf.partMissing[slot.name] = false
                end
                if isElement(player) then
                    local now = exports.items:getHeld(player)
                    if now and now.id == held.id then
                        exports.items:clearHeld(player)
                    end
                    exports.items:refreshPlayer(player)
                    exports.character:gainSkill(player, "Repair")
                    ctx.toast(player, "PART_INSTALLED")
                end
            end)
        end
        hold(player, vehicle, slot, held, "Installing body part", ready, commit)
    end

    -- The Wrench in hand takes the nearest part off: it lands beside the slot as a Good or a Bad part item.
    function M.remove(player, vehicle)
        local held = exports.items:getHeld(player)
        if not held or held.uname ~= "Wrench" then
            return ctx.toast(player, "PART_WRENCH")
        end
        if ctx.activeActions[player] or M.busy(vehicle) then
            return
        end
        if not workable(player, vehicle) then
            return ctx.toast(player, "PART_NOT_HERE")
        end
        local modelId = getElementModel(vehicle)
        local lx, ly = localPoint(player, vehicle)
        local slot = lx and bp.nearestSlot(modelId, lx, ly)
        if not slot then
            return ctx.toast(player, "PART_NOT_HERE")
        end
        if bp.condition(slot, state(vehicle, slot)) == "missing" then
            return ctx.toast(player, "PART_MISSING")
        end
        local function ready()
            return bp.condition(slot, state(vehicle, slot)) ~= "missing"
        end
        local function commit(action, cid)
            local inf = ctx.info[vehicle]
            local good = bp.condition(slot, state(vehicle, slot)) == "good"
            local uname = bp.uname(modelId, slot, good)
            local dx, dy = bp.dropPoint(slot)
            local x, y = ctx.toWorld(getElementMatrix(vehicle), dx, dy, 0)
            local _, _, vz = getElementPosition(vehicle)
            local _, _, rz = getElementRotation(vehicle)
            local int, dim = getElementInterior(vehicle), getElementDimension(vehicle)
            local z = vz - bp.MODELS[modelId].groundDrop
            local args = { inf.id, cid, modelId, slot.path, slot.missing, uname, snapshotJson(vehicle) }
            for _, v in ipairs({ x, y, z, rz, int, dim }) do
                args[#args + 1] = v
            end
            ctx.db.call("vehicle_part_remove", args, function(res)
                finished(vehicle, player, action)
                if not res or not res.ok then
                    return isElement(player) and ctx.toast(player, "PART_FAILED")
                end
                if isElement(vehicle) and ctx.info[vehicle] == inf then
                    setState(vehicle, slot, slot.missing)
                    inf.damage = M.snapshot(vehicle)
                    inf.partMissing = inf.partMissing or {}
                    inf.partMissing[slot.name] = true
                end
                local id = tonumber(payloadOf(res).id)
                if id then
                    exports.items:resendWorldItem(id)
                end
                if isElement(player) then
                    exports.character:gainSkill(player, "Repair")
                    ctx.toast(player, "PART_REMOVED")
                end
            end)
        end
        hold(player, vehicle, slot, held, "Removing body part", ready, commit)
    end

    -- Once a second: a slot that was there on the last look and is gone now was knocked off. The parts land on the
    -- ground as Bad items, written together with the vehicle's damage.
    function M.scan(vehicle, inf)
        local def = bp.MODELS[getElementModel(vehicle)]
        if not def or isVehicleBlown(vehicle) or M.busy(vehicle) then
            return
        end
        local seen = inf.partMissing
        local lost = {}
        if not seen then
            seen = {}
            inf.partMissing = seen
        end
        for _, slot in ipairs(def.slots) do
            local gone = bp.condition(slot, state(vehicle, slot)) == "missing"
            if gone and seen[slot.name] == false then
                lost[#lost + 1] = slot
            end
            seen[slot.name] = gone
        end
        if #lost == 0 then
            return
        end
        local modelId = getElementModel(vehicle)
        local _, _, vz = getElementPosition(vehicle)
        local _, _, rz = getElementRotation(vehicle)
        local int, dim = getElementInterior(vehicle), getElementDimension(vehicle)
        local m = getElementMatrix(vehicle)
        local rows = {}
        for _, slot in ipairs(lost) do
            local dx, dy = bp.dropPoint(slot)
            local x, y = ctx.toWorld(m, dx, dy, 0)
            local z = vz - def.groundDrop
            rows[#rows + 1] = { u = bp.uname(modelId, slot, false), x = x, y = y, z = z, rz = rz, int = int, dim = dim }
        end
        inf.damage = M.snapshot(vehicle)
        local items = toJSON(rows, true):sub(2, -2)
        ctx.db.call("vehicle_parts_detached", { inf.id, snapshotJson(vehicle), items }, function(res)
            if not res or not res.ok then
                return ctx.util.log("vehicles", "error", "vehicle_parts_detached failed: %s", res and res.code or "db")
            end
            local p = payloadOf(res)
            local first, count = p and tonumber(p.first), p and tonumber(p.count) or 0
            for i = 0, count - 1 do
                if first then
                    exports.items:resendWorldItem(first + i)
                end
            end
        end)
    end

    return M
end
