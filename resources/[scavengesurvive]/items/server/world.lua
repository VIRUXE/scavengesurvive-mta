-- World projection: the world items each client sees (spatial query every 2 s, diffed per player).
-- ctx = { db, state, geometry, diff, charId } built by server/main.lua; state.sent / state.settings are shared.
return function(ctx)
    local db, state, geometry, diff = ctx.db, ctx.state, ctx.geometry, ctx.diff
    local M = {}

    local COLS = "i.id, i.type_uname AS uname, i.hitpoints AS hp, i.data, i.x, i.y, i.z, i.rz,"
        .. " i.ground_nx, i.ground_ny, i.interior, i.dimension"
    local FROM = " FROM world_items_pos p JOIN items i ON i.id = p.item_id WHERE "

    -- Numbers are formatted into the SQL (never `?` literals); positions come from the server, never the client.
    function M.syncSql(x, y, r)
        local minx, miny, maxx, maxy = geometry.box(x, y, r)
        return "SELECT "
            .. COLS
            .. FROM
            .. "MBRContains(ST_GeomFromText('"
            .. geometry.polygonWKT(minx, miny, maxx, maxy)
            .. "'), p.pos)"
    end

    function M.findNearestSql(x, y, r, interior, dimension)
        local point = string.format("POINT(%g, %g)", x, y)
        local where = "ST_Distance(p.pos, " .. point .. ") <= " .. string.format("%g", r)
        if interior and dimension then
            where = where
                .. string.format(" AND IFNULL(i.interior, 0) = %d AND IFNULL(i.dimension, 0) = %d", interior, dimension)
        end
        return "SELECT " .. COLS .. FROM .. where .. " ORDER BY ST_Distance(p.pos, " .. point .. ") ASC LIMIT 1"
    end

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

    return M
end
