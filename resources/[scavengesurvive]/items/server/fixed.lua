-- Fixed world items upstream creates on every start (OnGameModeInit). The port's items persist in the database,
-- so each start only puts one back that is missing: an item of the type within RADIUS of the spot, none carried
-- off since, means nothing is created. ctx = { db, world, log } built by server/main.lua.
return function(ctx)
    local db, world = ctx.db, ctx.world
    local RADIUS = 2.0
    -- upstream item/heartshapedbox.pwn: CreateItem(item_HeartShapedBox, 2912.3301, 2910.2800, 29.7780); the loot
    -- boxes get their contents in loot/server/main.lua, this one stays empty
    local FIXED = { { uname = "HeartShapedBox", x = 2912.3301, y = 2910.2800, z = 29.7780 } }
    local M = {}

    local function ensure(spot)
        local sql = world.findNearestSql(spot.x, spot.y, RADIUS, 0, 0, { spot.uname })
        db.query(sql, {}, function(rows)
            if not rows or #rows > 0 then
                return
            end
            local params = { spot.uname, nil, nil, spot.x, spot.y, spot.z, 0, 0, 0, nil, nil, n = 11 }
            db.call("item_create", params, function(res)
                local ok = res and res.ok
                local what = ok and "created" or (res and res.code or "db")
                local at = string.format("%g, %g, %g", spot.x, spot.y, spot.z)
                ctx.log("items", ok and "info" or "warn", "fixed %s at %s: %s", spot.uname, at, what)
            end)
        end)
    end

    function M.start()
        for _, spot in ipairs(FIXED) do
            ensure(spot)
        end
    end

    return M
end
