-- GTA's snack machines as items (data/vending.lua, tools/make_vending.py): on start every spot without its SnackMachine
-- gets one again (item_create_many, the container comes with it), and every world.vending_restock_s each machine no
-- player is within world.vending_player_distance of and that has room asks the loot budget for snacks
-- (exports.loot:stockContainer, table vending_snacks): the zone's scarcity decides how much comes back. items
-- (server/vending.lua) mends the glass and shows the snacks once they are in.
-- ctx = { db, util, log, logic = shared/logic/boxes.lua, spots, setting }.
return function(ctx)
    local db, util, log, logic = ctx.db, ctx.util, ctx.log, ctx.logic
    local UNAME, TABLE = "SnackMachine", "vending_snacks"
    local spots = {}
    for i, s in ipairs(ctx.spots) do -- in shared/logic/boxes.lua's shape: { uname, x, y, z, rz, interior }
        spots[i] = { UNAME, s[1], s[2], s[3], s[4], s[5] }
    end
    local MACHINES = "SELECT i.id, i.x, i.y, i.interior, c.id AS cid, c.size, "
        .. "(SELECT COUNT(*) FROM items x WHERE x.container_id = c.id) AS n "
        .. "FROM items i LEFT JOIN containers c ON c.owner_item_id = i.id "
        .. "WHERE i.type_uname = ? AND i.x IS NOT NULL"
    local M = {}

    local function watched(x, y, distance)
        for _, p in ipairs(getElementsByType("player")) do
            local px, py = getElementPosition(p)
            if getDistanceBetweenPoints2D(px, py, x, y) <= distance then
                return true
            end
        end
        return false
    end

    function M.ensure()
        db.query(
            "SELECT type_uname, x, y, interior FROM items WHERE x IS NOT NULL AND type_uname = ?",
            { UNAME },
            function(rows)
                if not rows then
                    return util.log("world", "warn", "vending: could not read the machines")
                end
                local missing = logic.missing(spots, rows)
                if #missing == 0 then
                    return
                end
                local list = {}
                for _, s in ipairs(missing) do
                    list[#list + 1] = { u = UNAME, x = s[2], y = s[3], z = s[4], rz = s[5], i = s[6] }
                end
                db.call("item_create_many", { toJSON(list) }, function(res)
                    local made = res and res.ok and res.payload and tonumber(res.payload.created) or 0
                    local line = { spots = #spots, missing = #missing, made = made }
                    if not (res and res.ok) then
                        line.ok, line.code = false, res and res.code or "DB_ERROR"
                    end
                    log.event("world.vendingPlaced", line, line.ok == false and "warn" or nil)
                end)
            end
        )
    end

    function M.restock()
        local lootRes = getResourceFromName("loot")
        if not lootRes or getResourceState(lootRes) ~= "running" then
            return
        end
        db.query(MACHINES, { UNAME }, function(rows)
            if not rows then
                return util.log("world", "warn", "vending: could not read the machines")
            end
            local distance = ctx.setting("world.vending_player_distance", 60)
            local asked = 0
            for _, r in ipairs(rows) do
                local free = (tonumber(r.size) or 0) - (tonumber(r.n) or 0)
                if r.cid and free > 0 and not watched(r.x, r.y, distance) then
                    if exports.loot:stockContainer(r.cid, r.x, r.y, TABLE, free) then
                        asked = asked + 1
                    end
                end
            end
            util.log("world", "info", "vending: %d machines, %d asked for stock", #rows, asked)
        end)
    end

    function M.start()
        M.ensure()
        setTimer(M.restock, 60000, 1)
        setTimer(M.restock, ctx.setting("world.vending_restock_s", 1800) * 1000, 0)
    end

    return M
end
