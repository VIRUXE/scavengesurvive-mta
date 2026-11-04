-- Removable body parts (doors, bonnet, boot, bumpers). A part fitted by hand sits loose and is shaken off by driving;
-- a Wrench secures it, and a Wrench takes a secured one off. A part a crash knocked off lands on the ground as a Bad
-- item. The slots per model are shared/logic/bodyparts.lua.
return function(ctx)
    local bp = ctx.bp
    local log, vehicleLine = ctx.log, ctx.vehicleLine
    local M, pending = {}, setmetatable({}, { __mode = "k" })
    local HOLD_MS = 4000
    local SECURE_MS = 3000
    local MAX_MOVE = 0.8
    local MAX_SPEED_SQ = 0.0001 -- about 1.8 km/h: a parked vehicle still reports a little physics noise
    local THROW_SECONDS = 0.8 -- a part shaken off a moving vehicle lands this far ahead of it, in seconds of travel
    local THROW_MAX = 12

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

    local function looseNames(set)
        local names = {}
        for name, on in pairs(set or {}) do
            if on then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        return names
    end

    -- the loose parts also ride along in the vehicle's element data so a client can tell tighten from remove
    local function publish(vehicle, inf)
        setElementData(vehicle, "vehicles.loose", table.concat(looseNames(inf.loose), ","), "broadcast", "deny")
    end

    -- `loose` overrides the vehicle's own set of loose slot names (the snapshot a change is about to commit)
    function M.snapshot(vehicle, loose)
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
        local inf = ctx.info[vehicle]
        d.loose = looseNames(loose or (inf and inf.loose))
        return d
    end

    local function snapshotJson(vehicle, loose)
        return toJSON(M.snapshot(vehicle, loose), true):sub(2, -2) -- toJSON wraps its argument in a list
    end

    -- a vehicle just built from its row: pick up the loose parts saved with its damage
    function M.restore(vehicle, inf)
        inf.loose = {}
        local saved = type(inf.damage) == "table" and inf.damage.loose
        for _, name in ipairs(type(saved) == "table" and saved or {}) do
            inf.loose[name] = true
        end
        publish(vehicle, inf)
    end

    local function copySet(set)
        local copy = {}
        for k, v in pairs(set or {}) do
            copy[k] = v
        end
        return copy
    end

    local function state(vehicle, slot)
        if slot.door then
            return getVehicleDoorState(vehicle, slot.door)
        end
        return getVehiclePanelState(vehicle, slot.panel)
    end

    local function setState(vehicle, slot, value, fly)
        if slot.door then
            setVehicleDoorState(vehicle, slot.door, value, fly == true)
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

    -- the worker turns to face the slot they work on
    local function faceSlot(player, vehicle, slot)
        local x, y = ctx.toWorld(getElementMatrix(vehicle), slot.x, slot.y, 0)
        local px, py = getElementPosition(player)
        setPedRotation(player, math.deg(math.atan2(px - x, y - py)))
    end

    -- A timed hold on one slot: `ready()` is checked again every 100 ms, `commit(action, cid)` runs once the time is
    -- up. `anim` nil keeps the pose the player already has (a part in both hands stays carried).
    local function hold(player, vehicle, slot, held, label, ms, anim, ready, commit)
        local cid = exports.character:getCharacterId(player)
        if not cid then
            return
        end
        local startX, startY, startZ = getElementPosition(player)
        local duration = exports.character:skillTimeModifier(player, ms, "Repair")
        local start = getTickCount()
        local action = { actionType = "bodypart", vehicle = vehicle, player = player }
        pending[vehicle] = action
        ctx.activeActions[player] = action
        faceSlot(player, vehicle, slot)
        if anim then
            setPedAnimation(player, anim[1], anim[2], -1, true, false, false, false)
        end
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

    local WRENCH_ANIM = { "BOMBER", "BOM_Plant_Loop" }

    -- A held part goes into the empty slot it belongs to, loose: a Wrench has to secure it.
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
            local loose = copySet(inf.loose)
            loose[slot.name] = true
            local args = { inf.id, held.id, cid, held.uname, modelId, slot.path, slot.missing, value }
            args[#args + 1] = snapshotJson(vehicle, loose)
            ctx.db.call("vehicle_part_install", args, function(res)
                finished(vehicle, player, action)
                local line = { player = player, part = slot.name, item_id = held.id }
                if not res or not res.ok then
                    line.ok, line.code = false, res and res.code or "DB_ERROR"
                    log.event("vehicle.partInstalled", vehicleLine(vehicle, line), "warn")
                    return isElement(player) and ctx.toast(player, "PART_FAILED")
                end
                log.event("vehicle.partInstalled", vehicleLine(vehicle, line))
                if isElement(vehicle) and ctx.info[vehicle] == inf then
                    setState(vehicle, slot, tonumber(payloadOf(res).state))
                    inf.loose[slot.name] = true
                    inf.partMissing = inf.partMissing or {}
                    inf.partMissing[slot.name] = false
                    inf.damage = M.snapshot(vehicle)
                    publish(vehicle, inf)
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
        hold(player, vehicle, slot, held, "Fitting body part", HOLD_MS, nil, ready, commit)
    end

    -- Wrench on a loose part: tighten it, it no longer shakes off.
    local function secure(player, vehicle, slot, held)
        local function ready()
            local inf = ctx.info[vehicle]
            return inf.loose[slot.name] == true and bp.condition(slot, state(vehicle, slot)) ~= "missing"
        end
        local function commit(action)
            local inf = ctx.info[vehicle]
            local loose = copySet(inf.loose)
            loose[slot.name] = nil
            local json = snapshotJson(vehicle, loose)
            ctx.db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { json, inf.id })
            finished(vehicle, player, action)
            inf.loose[slot.name] = nil
            inf.damage = M.snapshot(vehicle)
            publish(vehicle, inf)
            exports.character:gainSkill(player, "Repair")
            ctx.toast(player, "PART_SECURED")
        end
        hold(player, vehicle, slot, held, "Tightening body part", SECURE_MS, WRENCH_ANIM, ready, commit)
    end

    -- Wrench on a secured part: unbolt it, it lands beside the slot as a Good or a Bad part item.
    local function unbolt(player, vehicle, slot, held, modelId)
        local function ready()
            local inf = ctx.info[vehicle]
            return not inf.loose[slot.name] and bp.condition(slot, state(vehicle, slot)) ~= "missing"
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
                local line = { player = player, part = slot.name }
                if not res or not res.ok then
                    line.ok, line.code = false, res and res.code or "DB_ERROR"
                    log.event("vehicle.partRemoved", vehicleLine(vehicle, line), "warn")
                    return isElement(player) and ctx.toast(player, "PART_FAILED")
                end
                if isElement(vehicle) and ctx.info[vehicle] == inf then
                    setState(vehicle, slot, slot.missing)
                    inf.damage = M.snapshot(vehicle)
                    inf.partMissing = inf.partMissing or {}
                    inf.partMissing[slot.name] = true
                end
                local id = tonumber(payloadOf(res).id)
                line.item_id = id
                log.event("vehicle.partRemoved", vehicleLine(vehicle, line))
                if id then
                    exports.items:resendWorldItem(id)
                end
                if isElement(player) then
                    exports.character:gainSkill(player, "Repair")
                    ctx.toast(player, "PART_REMOVED")
                end
            end)
        end
        hold(player, vehicle, slot, held, "Removing body part", HOLD_MS, WRENCH_ANIM, ready, commit)
    end

    -- Hold F with a Wrench at a part: a loose one is tightened, a secured one is taken off.
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
        if ctx.info[vehicle].loose[slot.name] then
            return secure(player, vehicle, slot, held)
        end
        return unbolt(player, vehicle, slot, held, modelId)
    end

    local function speedKmh(vehicle)
        local vx, vy, vz = getElementVelocity(vehicle)
        return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    end

    -- where a part lands: its slot's drop point, carried ahead by the vehicle's momentum
    local function landing(vehicle, def, slot)
        local dx, dy = bp.dropPoint(slot)
        local x, y = ctx.toWorld(getElementMatrix(vehicle), dx, dy, 0)
        local vx, vy = getElementVelocity(vehicle)
        local ox, oy = vx * 50 * THROW_SECONDS, vy * 50 * THROW_SECONDS
        local far = math.sqrt(ox * ox + oy * oy)
        if far > THROW_MAX then
            ox, oy = ox * THROW_MAX / far, oy * THROW_MAX / far
        end
        local _, _, vz = getElementPosition(vehicle)
        return x + ox, y + oy, vz - def.groundDrop
    end

    -- Once a second. A slot gone since the last look was knocked off by a crash and drops a Bad item; a loose part is
    -- shaken off by driving and drops as it was, flung ahead; both are written with the vehicle's damage.
    function M.scan(vehicle, inf)
        local def = bp.MODELS[getElementModel(vehicle)]
        if not def or isVehicleBlown(vehicle) or M.busy(vehicle) then
            return
        end
        inf.loose = inf.loose or {}
        local seen = inf.partMissing
        local lost = {}
        if not seen then
            seen = {}
            inf.partMissing = seen
        end
        for _, slot in ipairs(def.slots) do
            local gone = bp.condition(slot, state(vehicle, slot)) == "missing"
            if gone and seen[slot.name] == false then
                lost[#lost + 1] = { slot = slot, good = false }
                inf.loose[slot.name] = nil
            end
            seen[slot.name] = gone
        end
        local kmh = speedKmh(vehicle)
        local last = inf.lastKmh
        inf.lastKmh = kmh
        local shaken = next(inf.loose) and bp.comesOff(kmh, last, math.random()) or nil
        if shaken then
            local present = {}
            for _, slot in ipairs(def.slots) do
                local value = state(vehicle, slot)
                if inf.loose[slot.name] and bp.condition(slot, value) ~= "missing" then
                    present[#present + 1] = { slot = slot, good = bp.condition(slot, value) == "good" }
                end
            end
            if shaken == "one" and #present > 1 then
                present = { present[math.random(#present)] }
            end
            for _, entry in ipairs(present) do
                setState(vehicle, entry.slot, entry.slot.missing, true)
                inf.loose[entry.slot.name] = nil
                seen[entry.slot.name] = true
                lost[#lost + 1] = entry
            end
        end
        if #lost == 0 then
            return
        end
        local modelId = getElementModel(vehicle)
        local _, _, rz = getElementRotation(vehicle)
        local int, dim = getElementInterior(vehicle), getElementDimension(vehicle)
        local rows = {}
        for _, entry in ipairs(lost) do
            local x, y, z = landing(vehicle, def, entry.slot)
            local u = bp.uname(modelId, entry.slot, entry.good)
            rows[#rows + 1] = { u = u, x = x, y = y, z = z, rz = rz, int = int, dim = dim }
        end
        inf.damage = M.snapshot(vehicle)
        publish(vehicle, inf)
        local items = toJSON(rows, true):sub(2, -2)
        local parts = {}
        for _, entry in ipairs(lost) do
            parts[#parts + 1] = entry.slot.name
        end
        ctx.db.call("vehicle_parts_detached", { inf.id, snapshotJson(vehicle), items }, function(res)
            if not res or not res.ok then
                return ctx.util.log("vehicles", "error", "vehicle_parts_detached failed: %s", res and res.code or "db")
            end
            local p = payloadOf(res)
            local first, count = p and tonumber(p.first), p and tonumber(p.count) or 0
            local line = { reason = "detached", parts = parts, count = count }
            log.event("vehicle.partRemoved", vehicleLine(vehicle, line))
            for i = 0, count - 1 do
                if first then
                    exports.items:resendWorldItem(first + i)
                end
            end
        end)
    end

    return M
end
