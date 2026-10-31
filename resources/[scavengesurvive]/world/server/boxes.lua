-- GTA's boxes, crates and bags as items (data/boxes.lua): on start and every world.boxes_respawn_s each spot left
-- without its item and with no player within world.boxes_player_distance gets one again, every new item in one
-- item_create_many call, a bin bag with its rubbish (shared/logic/boxes.lua M.trash) inside.
-- ctx = { db, util, logic = shared/logic/boxes.lua, spots, setting }.
return function(ctx)
    local db, util, logic, spots = ctx.db, ctx.util, ctx.logic, ctx.spots
    local types = logic.types(spots)
    local sql = "SELECT type_uname, x, y, interior FROM items WHERE x IS NOT NULL AND type_uname IN ("
        .. string.rep("?, ", #types - 1)
        .. "?)"
    local M = {}

    local function sizeOf(uname)
        local t = exports.data:itemType(uname)
        return t and t.size
    end

    local function playerPositions()
        local out = {}
        for _, p in ipairs(getElementsByType("player")) do
            local x, y = getElementPosition(p)
            out[#out + 1] = { x = x, y = y }
        end
        return out
    end

    function M.refill()
        db.query(sql, types, function(rows)
            if not rows then
                return util.log("world", "warn", "boxes: could not read the world items")
            end
            local missing = logic.missing(spots, rows)
            local due = logic.unwatched(missing, playerPositions(), ctx.setting("world.boxes_player_distance", 60))
            if #due == 0 then
                return util.log("world", "info", "boxes: %d spots, %d empty, none to fill", #spots, #missing)
            end
            local list = {}
            for _, s in ipairs(due) do
                local e = { u = s[1], x = s[2], y = s[3], z = s[4], rz = s[5], i = s[6] }
                local t = exports.data:itemType(s[1])
                if t and t.category == "safebox" then -- a bin bag comes with its rubbish
                    e.c = logic.trash(t.categoryData.size, sizeOf, math.random)
                end
                list[#list + 1] = e
            end
            db.call("item_create_many", { toJSON(list) }, function(res)
                local made = res and res.ok and res.payload and res.payload.created or 0
                local why = res and res.code or "DB_ERROR"
                util.log(
                    "world",
                    res and res.ok and "info" or "warn",
                    "boxes: %d spots, %d made (%s)",
                    #spots,
                    made,
                    why
                )
            end)
        end)
    end

    function M.start()
        M.refill()
        setTimer(M.refill, ctx.setting("world.boxes_respawn_s", 900) * 1000, 0)
    end

    return M
end
