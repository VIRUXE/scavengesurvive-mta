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

