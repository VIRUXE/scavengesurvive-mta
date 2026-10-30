-- Server side of the machines (shared/logic/machines.lua; upstream itemtype/machine.pwn): a tap of F on one opens
-- its 12-slot container (or says how long the cook has left), a hold opens the Start dialog, or refuels it while a
-- Petrol Can is in hand; a cook is a timer resumed from the item data on a restart and finished by the
-- machine_finish procedure, which swaps the container's contents in one call.
-- ctx = { db, net, state, type, toast, world, hands, containers, machines, liquids, decodeData, charId }
-- built by server/main.lua.
return function(ctx)
    local db, net, state, world, hands = ctx.db, ctx.net, ctx.state, ctx.world, ctx.hands
    local machines, liquids, itemType, toast, decodeData =
        ctx.machines, ctx.liquids, ctx.type, ctx.toast, ctx.decodeData
    local M = {}
    local cookTimers = {} -- item id -> timer
    local refuels = {} -- player -> { row, held, fuel, amount, timer }
    local ROW = "SELECT id, type_uname AS uname, hitpoints AS hp, data, x, y, z, rz, interior, dimension FROM items "
        .. "WHERE id = ? AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local COOKING = "SELECT id, data FROM items WHERE type_uname IN ('ScrapMachine', 'RefineMachine', 'WaterMachine') "
        .. "AND x IS NOT NULL AND JSON_VALUE(data, '$.machine.cooking.at') IS NOT NULL"

    local function now()
        return getRealTime().timestamp
    end

    local function raw(row)
        return (row.data and row.data ~= false) and row.data or ""
    end

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    local function text(player, key, ...)
        toast(player, string.format(machines.TEXT[key] or key, ...))
    end

    -- the machine's next state, written only if nobody changed the row since it was read; cb(ok)
    local function write(row, st, cb)
        local sql = "UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL AND IFNULL(data, '') = ?"
        local next_ = encode(machines.encode(decodeData(row.data), st))
        db.exec(sql, { next_, row.id, raw(row) }, function(ok, _, affected)
            local done = ok and tonumber(affected) == 1
            if done then
                row.data = next_
                world.resendEverywhere(row.id) -- the smoke (client/world.lua)
            end
            if cb then
                cb(done)
            end
        end)
    end

    local function inReach(player, row)
        if not isElement(player) then
            return false
        end
        if (row.interior or 0) ~= getElementInterior(player) or (row.dimension or 0) ~= getElementDimension(player) then
            return false
        end
        local px, py, pz = getElementPosition(player)
        return getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) <= machines.REFUEL_REACH
    end

    -- The cook ------------------------------------------------------------------------------------------------

    local finish

    local function schedule(itemId, ms)
        if isTimer(cookTimers[itemId]) then
            killTimer(cookTimers[itemId])
        end
        cookTimers[itemId] = setTimer(finish, math.max(50, ms), 1, itemId)
    end

    finish = function(itemId)
        cookTimers[itemId] = nil
        db.one(ROW, { itemId }, function(row)
            local kind = row and machines.kind(row.uname)
            if not kind then
                return -- taken down while it cooked
            end
            local st = machines.state(decodeData(row.data))
            if not st.cooking then
                return
            end
            db.one("SELECT id FROM containers WHERE owner_item_id = ?", { row.id }, function(cRow)
                if not cRow then
                    return write(row, { fuel = st.fuel, cooking = nil })
                end
                local sql = "SELECT type_uname AS uname, data FROM items WHERE container_id = ? ORDER BY slot"
                db.query(sql, { cRow.id }, function(rows)
                    local items = {}
                    for i, r in ipairs(rows or {}) do
                        items[i] = { uname = r.uname, data = decodeData(r.data) }
                    end
                    local nextSt, results = machines.finish(kind, st, items, liquids, itemType)
                    for _, res in ipairs(results) do
                        res.data = res.data and encode(res.data) or "" -- a plain string for the procedure
                    end
                    local params = { row.id, raw(row), encode(machines.encode(decodeData(row.data), nextSt)), cRow.id }
                    params[5] = #results > 0 and toJSON(results) or "[]"
                    db.call("machine_finish", params, function(res)
                        if res and res.ok then
                            world.resendEverywhere(row.id)
                            outputServerLog(
                                string.format(
                                    "[MACHINE] %s %d finished: %d items in, %d out",
                                    row.uname,
                                    row.id,
                                    res.payload and res.payload.removed or #items,
                                    res.payload and res.payload.created or #results
                                )
                            )
                        elseif res and res.code == "BUSY" then
                            schedule(row.id, 2000) -- someone wrote the row meanwhile (a refuel): read it again
                        end
                    end)
                end)
            end)
        end)
    end

    -- machines that were cooking when the resource stopped pick their timers back up; server/main.lua calls it
    -- once the database is connected
    function M.start()
        db.query(COOKING, {}, function(rows)
            local t = now()
            for _, r in ipairs(rows or {}) do
                local st = machines.state(decodeData(r.data))
                if st.cooking then
                    schedule(r.id, machines.remainingMs(st, t))
                end
            end
        end)
    end

    -- The interact key -----------------------------------------------------------------------------------------

    -- hands.lua itemPickupRequested: a tap on a machine. true when the row is a machine.
    function M.interact(player, _, _, row)
        if not machines.isMachine(row.uname) then
            return false
        end
        local st = machines.state(decodeData(row.data))
        if st.cooking then
            text(player, "MACHPROCESS", machines.timeText(machines.remainingMs(st, now())))
            return true
        end
        local t = itemType(row.uname)
        ctx.containers.openWorldContainer(player, row, {
            kind = "safebox",
            size = machines.CONTAINER_SIZE,
            title = t and t.name or row.uname,
            machine = machines.kind(row.uname),
        })
        return true
    end

    -- the machine a player is at, re-read and checked for reach; cb(row, st)
    local function withMachine(player, itemId, cb)
        itemId = tonumber(itemId)
        if not itemId or not ctx.charId(player) then
            return
        end
        db.one(ROW, { itemId }, function(row, c)
            if not row or not machines.isMachine(row.uname) or not inReach(c.player, row) then
                return
            end
            cb(c.player, row, machines.state(decodeData(row.data)))
        end, { player = player })
    end

    -- Refuelling: the Petrol Can in hand empties into the tank 1.1 a tick while the key is held --------------------

    local function stopRefuel(player, keep)
        local r = refuels[player]
        if not r then
            return
        end
        refuels[player] = nil
        if isTimer(r.timer) then
            killTimer(r.timer)
        end
        if isElement(player) then
            triggerClientEvent(player, "machineRefuelStopped", player)
        end
        if not keep or not r.moved then
            return
        end
        local cur = state.held[player]
        if cur and cur.id == r.held.id then
            hands.syncHeldData(player, cur, { amount = r.amount, liquid = machines.PETROL })
        end
        write(r.row, { fuel = r.fuel, cooking = nil })
    end

    local function refuelTick(player)
        local r = refuels[player]
        if not r then
            return
        end
        local cur = state.held[player]
        if not isElement(player) or not cur or cur.id ~= r.held.id or not inReach(player, r.row) then
            return stopRefuel(player, true)
        end
        local done
        r.fuel, r.amount, done = machines.refuelStep(r.fuel, r.amount)
        r.moved = true
        if done then
            stopRefuel(player, true)
        end
    end

    local function startRefuel(player, row, st, held, amount)
        stopRefuel(player, true)
        refuels[player] = { row = row, held = held, fuel = st.fuel, amount = amount, moved = false }
        refuels[player].timer = setTimer(refuelTick, machines.REFUEL_TICK_MS, 0, player)
        triggerClientEvent(player, "machineRefuelStarted", player, machines.refuelMs(st.fuel))
        text(player, "REFUELLING")
    end

    -- the hold on F (hud): the Start dialog, or a refuel with a can of petrol in hand
    net.handler("machineMenuRequested", function(player, itemId)
        withMachine(player, itemId, function(p, row, st)
            if st.cooking then
                return text(p, "MACHPROCESS", machines.timeText(machines.remainingMs(st, now())))
            end
            local held = state.held[p]
            local amount = held and machines.petrolIn(itemType(held.uname), held.data, liquids)
            if amount then
                return startRefuel(p, row, st, held, amount)
            end
            triggerClientEvent(p, "machineMenuShown", p, row.id, machines.kind(row.uname), st.fuel)
        end)
    end, { rate = 5 })

    net.handler("machineHoldReleased", function(player)
        stopRefuel(player, true)
    end)

    -- Start pressed in the dialog
    net.handler("machineStartRequested", function(player, itemId)
        withMachine(player, itemId, function(p, row, st)
            db.one("SELECT id FROM containers WHERE owner_item_id = ?", { row.id }, function(cRow)
                local function go(count)
                    if not isElement(p) then
                        return
                    end
                    local ok, nextSt = machines.start(st, count, now(), math.random)
                    if not ok then
                        if nextSt == "MACHPROCESS" then
                            return text(p, nextSt, machines.timeText(machines.remainingMs(st, now())))
                        end
                        return text(p, nextSt, machines.FUEL_PER_ITEM)
                    end
                    write(row, nextSt, function(done)
                        if not done then
                            return toast(p, "BUSY")
                        end
                        schedule(row.id, nextSt.cooking.ms)
                        outputServerLog(
                            string.format(
                                "[MACHINE] %s %d started by %s: %d items, %d s",
                                row.uname,
                                row.id,
                                getPlayerName(p),
                                count,
                                nextSt.cooking.ms / 1000
                            )
                        )
                        text(p, "MACHCOOKTIM", machines.timeText(nextSt.cooking.ms))
                    end)
                end
                if not cRow then
                    return go(0)
                end
                db.one("SELECT COUNT(*) AS cnt FROM items WHERE container_id = ?", { cRow.id }, function(cnt)
                    go(cnt and tonumber(cnt.cnt) or 0)
                end)
            end)
        end)
    end, { rate = 5 })

    addEventHandler("onPlayerQuit", root, function()
        stopRefuel(source, true)
    end)

    addEventHandler("onResourceStop", resourceRoot, function()
        for player in pairs(refuels) do
            stopRefuel(player, true)
        end
    end)

    return M
end
