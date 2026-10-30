-- Server side of the furniture (#148, shared/logic/furniture.lua has the offsets): the interact key with an item in
-- hand puts it on a Desk, Table, Barstool or Small Table, or into an empty Gun Case or Cupboard, which then shows it
-- (furniture_display_put); with empty hands it takes the shown item back (furniture_display_take) or whatever lies
-- on top. Furniture itself is never picked up (hands.pickup asks blocksPickup).
-- ctx = { db, state, type, toast, world, hands, furniture, decodeData, charId } built by server/main.lua.
return function(ctx)
    local db, state, world, hands, furniture = ctx.db, ctx.state, ctx.world, ctx.hands, ctx.furniture
    local toast, decodeData = ctx.toast, ctx.decodeData
    local M = {}

    function M.blocksPickup(uname)
        return furniture.is(uname)
    end

    local function putOnTop(player, row)
        local x, y, z, rz = furniture.onTop(row)
        hands.dropHeld(player, { at = { x = x, y = y, z = z, rz = rz } })
    end

    local function putInCase(player, cid, held, row)
        if held.data then
            hands.queueData(held)
        end
        hands.flushData(held.id)
        db.call("furniture_display_put", { cid, held.id, row.id, furniture.DISPLAY_SIZE }, function(res, c)
            if not isElement(c.player) then
                return
            end
            if res and res.code == "CONTAINER_FULL" then
                local required = res.payload and tonumber(res.payload.required) or 1
                return toast(c.player, string.format(furniture.TEXT.CNTEXTRASLO, required))
            end
            if not res or not res.ok then
                return -- OCCUPIED: upstream does nothing while the case shows an item
            end
            hands.setHeld(c.player, nil)
            triggerEvent("itemMoved", c.player, c.itemId, "held", "container")
            world.resendEverywhere(c.caseId)
            world.syncPlayer(c.player)
        end, { player = player, itemId = held.id, caseId = row.id })
    end

    local function takeFromCase(player, cid, row)
        db.call("furniture_display_take", { cid, row.id }, function(res, c)
            if not res or not res.ok then
                return
            end
            world.resendEverywhere(c.caseId)
            local itemId = res.payload and tonumber(res.payload.item_id)
            local sql = "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?"
            db.one(sql, { itemId }, function(item)
                if not item or not isElement(c.player) then
                    return
                end
                item.data = decodeData(item.data)
                hands.setHeld(c.player, item)
                hands.pickupAnim(c.player, item.uname)
                triggerEvent("itemMoved", c.player, item.id, "container", "held")
                world.syncPlayer(c.player)
            end)
        end, { player = player, caseId = row.id })
    end

    -- empty hands at a desk or table: the highest item lying on it (same x/y as the furniture, so the nearest item
    -- is a tie the furniture can win)
    local function takeFromTop(player, cid, row)
        local f = string.format
        local sql = "SELECT i.id, i.type_uname AS uname, i.hitpoints AS hp, i.data FROM world_items_pos p "
            .. "JOIN items i ON i.id = p.item_id WHERE "
            .. f("ST_Distance(p.pos, POINT(%f, %f)) <= %f", row.x, row.y, furniture.ON_TOP_REACH)
            .. f(" AND i.z > %f AND IFNULL(i.interior, 0) = %d", (row.z or 0) + 0.1, row.interior or 0)
            .. f(" AND IFNULL(i.dimension, 0) = %d", row.dimension or 0)
            .. " AND i.type_uname NOT IN ('"
            .. table.concat(furniture.unames(), "', '")
            .. "') ORDER BY i.z DESC LIMIT 1"
        db.one(sql, {}, function(top)
            if top and isElement(player) and not state.held[player] then
                hands.pickup(player, cid, top)
            end
        end)
    end

    -- The interact key on a world item (hands.lua itemPickupRequested). true = handled here.
    function M.interact(player, cid, held, row)
        if not furniture.is(row.uname) then
            return false
        end
        local display = furniture.isDisplay(row.uname)
        if held then
            if display then
                putInCase(player, cid, held, row)
            else
                putOnTop(player, row)
            end
        elseif display then
            takeFromCase(player, cid, row)
        else
            takeFromTop(player, cid, row)
        end
        return true
    end

    -- an item in hand whose nearest world item was not furniture (an item already lying on a table is a tie with
    -- it, or the item looks for targets of its own): the nearest furniture in reach takes it, else the hands are
    -- full (quiet: say nothing)
    function M.interactNear(player, cid, held, radius, quiet)
        local x, y = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        local sql = world.findNearestSql(x, y, radius, int, dim, furniture.unames())
        db.one(sql, {}, function(row)
            if not isElement(player) or not state.held[player] or state.held[player].id ~= held.id then
                return
            end
            if not row then
                return not quiet and toast(player, "HANDS_FULL")
            end
            M.interact(player, cid, held, row)
        end)
    end

    -- crafting found nothing to build with the tool in hand (exports.crafting:groundCraft's furnitureId): the
    -- furniture the interact key was on takes it after all
    function M.placeOn(player, furnitureId)
        local cid = ctx.charId(player)
        local held = state.held[player]
        if not cid or not held then
            return false
        end
        local sql = "SELECT id, type_uname AS uname, data, x, y, z, rz, interior, dimension FROM items "
            .. "WHERE id = ? AND x IS NOT NULL"
        db.one(sql, { furnitureId }, function(row)
            if row and furniture.is(row.uname) and isElement(player) and state.held[player] == held then
                M.interact(player, cid, held, row)
            end
        end)
        return true
    end

    return M
end
