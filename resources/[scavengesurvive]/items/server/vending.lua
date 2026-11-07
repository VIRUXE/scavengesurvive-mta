-- The snack machine (shared/logic/vending.lua): the interact key on one whose glass holds says so, on a broken one
-- opens it as a take-only container; hits on the glass come from the clients that saw them (vendingGlassHit) and
-- are checked here (reach, the weapon in hand, the pace); every change to what it holds re-files its snacks onto
-- their coils in data.ids / data.shelf, which the clients draw. A restock from the loot budget
-- (lootContainerStocked) mends the glass.
-- ctx = { db, net, toast, world, containers, vending, decodeData, log }
return function(ctx)
    local db, toast, world, logic, decodeData = ctx.db, ctx.toast, ctx.world, ctx.vending, ctx.decodeData
    local log = ctx.log
    local M = {}
    local lastHit = {}

    local MACHINE_SQL = "SELECT i.id, i.type_uname AS uname, i.data, i.x, i.y, i.z, i.rz, i.interior, i.dimension "
        .. "FROM items i WHERE i.id = ? AND i.type_uname = ? AND i.x IS NOT NULL"
    local CONTENTS_SQL = "SELECT x.id, x.type_uname AS uname FROM containers c JOIN items x ON x.container_id = c.id "
        .. "WHERE c.owner_item_id = ? ORDER BY x.slot"

    function M.is(uname)
        return logic.is(uname)
    end

    -- data JSON with `glass` set to g (nil: mended, the key dropped)
    local function setGlass(id, g, cb)
        local sql = g
                and "UPDATE items SET data = JSON_SET(IFNULL(data, '{}'), '$.glass', ?) WHERE id = ? AND type_uname = ?"
            or "UPDATE items SET data = JSON_REMOVE(IFNULL(data, '{}'), '$.glass') WHERE id = ? AND type_uname = ?"
        local params = g and { g, id, logic.UNAME } or { id, logic.UNAME }
        db.exec(sql, params, function(ok)
            if ok then
                world.resendEverywhere(id)
            end
            if cb then
                cb(ok)
            end
        end)
    end

    -- re-files the machine's contents onto its coils (data.ids, data.shelf) and shows them to everyone near
    function M.refresh(machineId, mend)
        machineId = tonumber(machineId)
        if not machineId then
            return
        end
        db.one("SELECT data FROM items WHERE id = ? AND type_uname = ?", { machineId, logic.UNAME }, function(row)
            if not row then
                return
            end
            local data = decodeData(row.data)
            data = type(data) == "table" and data or {}
            db.query(CONTENTS_SQL, { machineId }, function(items)
                if not items then
                    return
                end
                local ids, shelf = logic.assign(data.ids, items)
                local sql = "UPDATE items SET data = JSON_SET(IFNULL(data, '{}'), '$.ids', JSON_EXTRACT(?, '$[0]'), "
                    .. "'$.shelf', JSON_EXTRACT(?, '$[0]')) WHERE id = ?"
                if mend then
                    sql = "UPDATE items SET data = JSON_REMOVE(JSON_SET(IFNULL(data, '{}'), '$.ids', "
                        .. "JSON_EXTRACT(?, '$[0]'), '$.shelf', JSON_EXTRACT(?, '$[0]')), '$.glass') WHERE id = ?"
                end
                db.exec(sql, { toJSON(ids), toJSON(shelf), machineId }, function(ok)
                    if ok then
                        world.resendEverywhere(machineId)
                    end
                end)
            end)
        end)
    end

    -- on start every machine's coils are filed again from what its container holds, so nothing stale is drawn
    function M.start()
        db.query("SELECT id FROM items WHERE type_uname = ? AND x IS NOT NULL", { logic.UNAME }, function(rows)
            for _, r in ipairs(rows or {}) do
                M.refresh(r.id)
            end
        end)
    end

    -- itemPickupRequested on a machine: true when it was one (handled)
    function M.interact(player, _, _, row)
        if not row or not logic.is(row.uname) then
            return false
        end
        if not logic.isBroken(decodeData(row.data)) then
            toast(player, "GLASS_INTACT")
            return true
        end
        ctx.containers.openWorldContainer(player, row, {
            takeOnly = true,
            onChange = function()
                M.refresh(row.id)
            end,
        })
        return true
    end

    -- a client saw its player hit the pane (a swing within reach, or a shot through it)
    ctx.net.handler("vendingGlassHit", function(player, machineId, weapon)
        machineId, weapon = tonumber(machineId), tonumber(weapon) or 0
        if not machineId or isPedDead(player) or getPedOccupiedVehicle(player) then
            return
        end
        local now = getTickCount()
        if lastHit[player] and now - lastHit[player] < 350 then
            return
        end
        lastHit[player] = now
        if weapon ~= getPedWeapon(player) then -- the hit must come from what the player holds
            return
        end
        db.one(MACHINE_SQL, { machineId, logic.UNAME }, function(row)
            if not row or not isElement(player) then
                return
            end
            if
                (row.interior or 0) ~= getElementInterior(player)
                or (row.dimension or 0) ~= getElementDimension(player)
            then
                return
            end
            local px, py, pz = getElementPosition(player)
            local _, _, prz = getElementRotation(player)
            local melee = weapon < 16 -- fists and melee weapons swing at it; the rest shoot it from afar
            if melee and not logic.inSwingReach(row.x, row.y, row.z, row.rz, px, py, pz, prz) then
                return
            end
            if not melee and getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > 120 then
                return
            end
            local data = decodeData(row.data)
            local left = logic.glass(data)
            if left <= 0 then
                return
            end
            left = math.max(0, left - logic.hitDamage(weapon))
            setGlass(row.id, left, function(ok)
                if not ok or left > 0 then
                    return
                end
                log.event("item.vendingGlassBroken", { player = player, item_id = row.id, weapon = weapon })
                local around = getElementsWithinRange(row.x, row.y, row.z, 80, "player")
                triggerClientEvent(around, "vendingGlassBroken", resourceRoot, row.id)
                M.refresh(row.id) -- the coils show what it holds from now on
            end)
        end)
    end, { rate = 6 })

    addEventHandler("onPlayerQuit", root, function()
        lastHit[source] = nil
    end)

    -- the loot budget restocked a container: a machine's glass is mended and its new snacks filed onto coils
    addEventHandler("lootContainerStocked", root, function(containerId, created)
        if (tonumber(created) or 0) <= 0 then
            return
        end
        db.one(
            "SELECT i.id FROM containers c JOIN items i ON i.id = c.owner_item_id WHERE c.id = ? AND i.type_uname = ?",
            { tonumber(containerId), logic.UNAME },
            function(row)
                if row then
                    M.refresh(row.id, true)
                end
            end
        )
    end)

    return M
end
