local spatial = loadstring(exports.lib:getModule("spatial"), "=lib/spatial.lua")()
-- World projection: the world items each client sees (spatial query every 2 s, diffed per player).
-- ctx = { db, state, geometry, diff, charId, clientData } built by server/main.lua; state.sent / state.settings
-- are shared.
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

    -- Pickup queries also constrain height and membership in the client's reachable candidates.
    function M.findNearestSql(x, y, r, interior, dimension, unames, pickup)
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
        if pickup then
            where = where
                .. string.format(
                    " AND POWER(i.x - %.9f, 2) + POWER(i.y - %.9f, 2) + POWER(i.z - %.9f, 2) <= %.9f",
                    x,
                    y,
                    pickup.z,
                    r * r
                )
                .. " AND i.id IN ("
                .. table.concat(pickup.ids, ", ")
                .. ")"
            if pickup.targetId then
                where = where .. string.format(" AND i.id = %d", pickup.targetId)
            end
        end
        return "SELECT " .. COLS .. FROM .. where .. " ORDER BY ST_Distance(p.pos, " .. point .. ") ASC LIMIT 1"
    end

    -- A client's candidates are a bounded list of database item IDs.
    function M.cleanIds(list)
        local ids = {}
        if type(list) == "table" then
            for i = 1, math.min(#list, 64) do
                local id = tonumber(list[i])
                if id and id >= 1 and id <= 2147483647 and id % 1 == 0 then
                    ids[#ids + 1] = id
                end
            end
        end
        return ids
    end

    -- an item's data with its secrets (keypad passcodes, padlock combos and dials, key codes) taken out before a
    -- client gets it: smallitems.clientData, the one place that decides what a client may see
    local sanitizeData = ctx.clientData
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
                        r.data = sanitizeData(r.data)
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

    -- Flagged items (item_ground_snap: z untrusted since it was flagged) are laid on the ground under them, 10 cm up as
    -- a drop lies, tilted to the slope, if that ground is within reach of the stored z. In the main world the server's
    -- own world measures them (every SNAP_SCAN_MS, lib geom.lua); elsewhere the client that draws one reports it
    -- (itemGroundMeasured), if the player is near it.
    local geom = assert(loadstring(exports.lib:getModule("geom"), "=lib/geom.lua"))()

    -- Recheck the player's current position after the query. Map collision supplies an independent
    -- wall check where available. Built defences and visible edges of large models use the client geometry.
    -- A surface within SINK_ALLOW of the origin is the ground the item is clipped into; a higher surface is a floor.
    local SINK_ALLOW = 0.25
    function M.inPickupReach(player, row, radius, itemType, recessed)
        local int, dim = getElementInterior(player), getElementDimension(player)
        if int ~= (row.interior or 0) or dim ~= (row.dimension or 0) then
            return false
        end
        local px, py, pz = getElementPosition(player)
        if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > radius then
            return false
        end
        if recessed or int ~= 0 or dim ~= 0 or not geom.ready() then
            return true
        end
        local x, y, low, high = row.x, row.y, row.z + 0.05, row.z + 0.6
        local chest = pz + 0.5
        if geom.clear(px, py, chest, x, y, low) then
            return true
        end
        local verticalClear = geom.clear(x, y, low, x, y, high)
        local skin = false
        if not verticalClear then
            local _, _, hz = geom.ray(x, y, low, x, y, high)
            skin = hz ~= nil and hz <= row.z + SINK_ALLOW
        end
        if not verticalClear and not skin then
            return false
        end
        if itemType and (itemType.size or 0) >= 9 then
            return true
        end
        return geom.clear(px, py, chest, x, y, high) == true
    end

    local SNAP_SQL = "SELECT i.x, i.y, i.z, i.interior, i.dimension FROM items i"
        .. " JOIN item_ground_snap s ON s.item_id = i.id AND s.z = i.z WHERE i.id = ? AND i.x IS NOT NULL"
    local SNAP_MAIN_SQL = "SELECT i.id, i.x, i.y, i.z FROM items i JOIN item_ground_snap s ON s.item_id = i.id"
        .. " AND s.z = i.z WHERE i.x IS NOT NULL AND i.interior = 0 AND i.dimension = 0 LIMIT 100"
    local SNAP_RANGE, SNAP_MAX_DZ, SNAP_SCAN_MS = 80, 4, 30000
    local SNAP_ABOVE, SNAP_DEPTH = 1.5, 6 -- as the client: from 1.5 m over the stored z to 6 m under it

    local function snap(id, fromZ, gz, nx, ny, by)
        local z = gz + 0.1
        if math.abs(z - fromZ) > SNAP_MAX_DZ then
            return
        end
        if nx * nx + ny * ny < 0.0025 then -- flat: no tilt (NULL, as a drop on flat ground stores)
            nx, ny = nil, nil
        end
        db.exec(
            "UPDATE items i JOIN item_ground_snap s ON s.item_id = i.id AND s.z = i.z"
                .. " SET i.z = ?, i.ground_nx = ?, i.ground_ny = ? WHERE i.id = ? AND i.x IS NOT NULL",
            { z, nx, ny, id, n = 4 },
            function(ok)
                db.exec("DELETE FROM item_ground_snap WHERE item_id = ?", { id })
                if ok then
                    M.resendEverywhere(id)
                    ctx.log.event("items.groundSnapped", { id = id, from = fromZ, to = z, by = by })
                end
            end
        )
    end

    local function snapMainWorld()
        if not geom.ready() then
            return
        end
        db.query(SNAP_MAIN_SQL, {}, function(rows)
            for _, r in ipairs(rows or {}) do
                local id, x, y, z = math.floor(tonumber(r.id)), tonumber(r.x), tonumber(r.y), tonumber(r.z)
                local gz, nx, ny = geom.below(x, y, z, SNAP_ABOVE, SNAP_ABOVE + SNAP_DEPTH)
                if gz then
                    snap(id, z, gz, nx, ny, "server")
                end
            end
        end)
    end
    setTimer(snapMainWorld, SNAP_SCAN_MS, 0)
    setTimer(snapMainWorld, 5000, 1)

    ctx.net.handler("itemGroundMeasured", function(player, id, gz, nx, ny)
        id, gz, nx, ny = tonumber(id), tonumber(gz), tonumber(nx) or 0, tonumber(ny) or 0
        if not id or not gz or gz ~= gz or math.abs(gz) > 3000 or math.abs(nx) > 1 or math.abs(ny) > 1 then
            return
        end
        id = math.floor(id)
        db.one(SNAP_SQL, { id }, function(row)
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
            snap(id, row.z, gz, nx, ny, "client")
        end)
    end, { rate = 10 })

    return M
end
