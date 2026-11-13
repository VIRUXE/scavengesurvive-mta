local spatial = loadstring(exports.lib:getModule("spatial"), "=lib/spatial.lua")()
-- World projection: the world items each client sees (spatial query every 2 s, diffed per player).
-- ctx = { db, state, geometry, diff, charId } built by server/main.lua; state.sent / state.settings are shared.
return function(ctx)
    local db, state, geometry, diff = ctx.db, ctx.state, ctx.geometry, ctx.diff
    local M = {}

    local COLS = "i.id, i.type_uname AS uname, i.hitpoints AS hp, i.data, i.x, i.y, i.z, i.rz,"
        .. " i.ground_nx, i.ground_ny, i.interior, i.dimension"
    local FROM = " FROM world_items_pos p JOIN items i ON i.id = p.item_id WHERE "
    -- the sync also says which rows still lie on an untrusted z (item_ground_snap, the z unchanged since it was
    -- flagged): the client that draws one measures the ground under it (itemGroundMeasured)
    local SYNC_FROM = " FROM world_items_pos p JOIN items i ON i.id = p.item_id"
        .. " LEFT JOIN item_ground_snap s ON s.item_id = i.id AND s.z = i.z WHERE "

    -- Numbers are formatted into the SQL (never `?` literals); positions come from the server, never the client.
    function M.syncSql(x, y, r)
        local minx, miny, maxx, maxy = geometry.box(x, y, r)
        return "SELECT "
            .. COLS
            .. ", s.item_id IS NOT NULL AS snap"
            .. SYNC_FROM
            .. "MBRContains(ST_GeomFromText('"
            .. geometry.polygonWKT(minx, miny, maxx, maxy)
            .. "'), p.pos)"
    end

    -- unames: optional list of type unames (server constants) the nearest item must be one of; exclude: optional list
    -- of item ids to leave out (the client's walled-off items, already cleaned to integers by M.cleanIds)
    function M.findNearestSql(x, y, r, interior, dimension, unames, exclude, targetId)
        local point = string.format("POINT(%g, %g)", x, y)
        -- Match the same rounded centre/radius as the existing exact predicate.
        local qx, qy, qr =
            tonumber(string.format("%g", x)), tonumber(string.format("%g", y)), tonumber(string.format("%g", r))
        local where = spatial.bounds(qx, qy, qr)
            .. " AND ST_Distance(p.pos, "
            .. point
            .. ") <= "
            .. string.format("%g", r)
        if unames then
            where = where .. " AND i.type_uname IN ('" .. table.concat(unames, "', '") .. "')"
        end
        if interior and dimension then
            where = where
                .. string.format(" AND IFNULL(i.interior, 0) = %d AND IFNULL(i.dimension, 0) = %d", interior, dimension)
        end
        if exclude and #exclude > 0 then
            where = where .. " AND i.id NOT IN (" .. table.concat(exclude, ", ") .. ")"
        end
        if targetId then
            where = where .. string.format(" AND i.id = %d", targetId)
        end
        return "SELECT " .. COLS .. FROM .. where .. " ORDER BY ST_Distance(p.pos, " .. point .. ") ASC LIMIT 1"
    end

    -- a client's list of item ids as at most 32 positive integers (anything else is dropped)
    function M.cleanIds(list)
        local ids = {}
        if type(list) ~= "table" then
            return ids
        end
        for _, v in ipairs(list) do
            local n = math.floor(tonumber(v) or 0)
            if n > 0 and #ids < 32 then
                ids[#ids + 1] = n
            end
        end
        return ids
    end

    -- Strip sensitive server-only fields (e.g. defence passcodes) before sending world item data to clients.
    local function sanitizeData(data)
        if type(data) ~= "table" then
            return data
        end
        if data.passcode ~= nil then
            data.passcode = nil
        end
        if type(data[1]) == "table" and data[1].passcode ~= nil then
            data[1].passcode = nil
        end
        local d = data.defence or (type(data[1]) == "table" and data[1].defence)
        if type(d) == "table" then
            if d.passcode ~= nil then
                local p = tostring(d.passcode)
                d.locked = (p ~= "" and p ~= "0" and p ~= "0000")
                d.passcode = nil
            end
        end
        return data
    end
    M.sanitizeData = sanitizeData

    function M.syncPlayer(player)
        local radius = tonumber(state.settings["items.sync_radius"]) or 150
        local x, y = getElementPosition(player)
        db.query(M.syncSql(x, y, radius), {}, function(rows, c)
            if not rows or not isElement(c.player) or not state.sent[c.player] then
                return
            end
            local dim, int = getElementDimension(c.player), getElementInterior(c.player)
            local visible = {}
            for _, r in ipairs(rows) do
                if (r.dimension or 0) == dim and (r.interior or 0) == int then
                    if type(r.data) == "string" and r.data ~= "" then
                        r.data = fromJSON(r.data)
                    elseif r.data == false then
                        r.data = nil
                    end
                    if type(r.data) == "table" then
                        sanitizeData(r.data)
                    end
                    visible[#visible + 1] = r
                end
            end
            local add, remove, sent = diff.compute(state.sent[c.player], visible)
            state.sent[c.player] = sent
            if #add > 0 or #remove > 0 then
                triggerClientEvent(c.player, "inventorySynced", resourceRoot, { add = add, remove = remove })
            end
        end, { player = player })
    end

    setTimer(function()
        for player in pairs(state.sent) do
            if isElement(player) and ctx.charId(player) then
                M.syncPlayer(player)
            end
        end
    end, 2000, 0)

    -- An item left the world: drop it from every client that shows it.
    function M.forgetEverywhere(itemId)
        for player, sent in pairs(state.sent) do
            if sent[itemId] then
                sent[itemId] = nil
                if isElement(player) then
                    triggerClientEvent(player, "inventorySynced", resourceRoot, { add = {}, remove = { itemId } })
                end
            end
        end
    end

    -- An item's row changed in place (a tent pitched or packed): the diff only resends ids a client lacks, so
    -- forgetting the id makes every client's next sync re-add the row and update the object in place.
    function M.resendEverywhere(itemId)
        for _, sent in pairs(state.sent) do
            sent[itemId] = nil
        end
    end

    -- A client measured the ground under a flagged item (sync row `snap`): the item is laid on it, 10 cm up as a
    -- drop lies, tilted to the slope, if the player is near it and the ground is within reach of the stored z.
    local SNAP_SQL = "SELECT i.x, i.y, i.z, i.interior, i.dimension FROM items i"
        .. " JOIN item_ground_snap s ON s.item_id = i.id AND s.z = i.z WHERE i.id = ? AND i.x IS NOT NULL"
    local SNAP_RANGE, SNAP_MAX_DZ = 80, 4
    ctx.net.handler("itemGroundMeasured", function(player, id, gz, nx, ny)
        id, gz, nx, ny = tonumber(id), tonumber(gz), tonumber(nx) or 0, tonumber(ny) or 0
        if not id or not gz or gz ~= gz or math.abs(gz) > 3000 or math.abs(nx) > 1 or math.abs(ny) > 1 then
            return
        end
        db.one(SNAP_SQL, { math.floor(id) }, function(row)
            if not row or not isElement(player) then
                return
            end
            local px, py = getElementPosition(player)
            if
                getElementDimension(player) ~= (row.dimension or 0)
                or getElementInterior(player) ~= (row.interior or 0)
                or getDistanceBetweenPoints2D(px, py, row.x, row.y) > SNAP_RANGE
            then
                return
            end
            local z = gz + 0.1
            if math.abs(z - row.z) > SNAP_MAX_DZ then
                return
            end
            if nx * nx + ny * ny < 0.0025 then -- flat: no tilt (NULL, as a drop on flat ground stores)
                nx, ny = nil, nil
            end
            db.exec(
                "UPDATE items i JOIN item_ground_snap s ON s.item_id = i.id AND s.z = i.z"
                    .. " SET i.z = ?, i.ground_nx = ?, i.ground_ny = ? WHERE i.id = ? AND i.x IS NOT NULL",
                { z, nx, ny, math.floor(id), n = 4 },
                function(ok)
                    db.exec("DELETE FROM item_ground_snap WHERE item_id = ?", { math.floor(id) })
                    if ok then
                        M.resendEverywhere(math.floor(id))
                        ctx.log.event("items.groundSnapped", { id = math.floor(id), from = row.z, to = z })
                    end
                end
            )
        end)
    end, { rate = 10 })

    return M
end
