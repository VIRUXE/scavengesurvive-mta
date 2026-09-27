local geometry, diff
do
    local function loadFile(path)
        local f = fileOpen(path, true)
        local src = fileRead(f, fileGetSize(f))
        fileClose(f)
        return assert(loadstring(src, "=items/" .. path))()
    end
    geometry = loadFile("shared/logic/geometry.lua")
    diff = loadFile("shared/logic/diff.lua")
end
Items.geometry = geometry

local COLS = "i.id, i.type_uname AS uname, i.hitpoints AS hp, i.x, i.y, i.z, i.rz, i.interior, i.dimension"
local FROM = " FROM world_items_pos p JOIN items i ON i.id = p.item_id WHERE "

-- Numbers are formatted into the SQL (never `?` literals); positions come from the server, never the client.
function Items.syncSql(x, y, r)
    local minx, miny, maxx, maxy = geometry.box(x, y, r)
    return "SELECT "
        .. COLS
        .. FROM
        .. "MBRContains(ST_GeomFromText('"
        .. geometry.polygonWKT(minx, miny, maxx, maxy)
        .. "'), p.pos)"
end

function Items.findNearestSql(x, y, r, interior, dimension)
    local point = string.format("POINT(%g, %g)", x, y)
    local where = "ST_Distance(p.pos, " .. point .. ") <= " .. string.format("%g", r)
    if interior and dimension then
        where = where
            .. string.format(" AND IFNULL(i.interior, 0) = %d AND IFNULL(i.dimension, 0) = %d", interior, dimension)
    end
    return "SELECT "
        .. COLS
        .. ", i.data"
        .. FROM
        .. where
        .. " ORDER BY ST_Distance(p.pos, "
        .. point
        .. ") ASC LIMIT 1"
end

function Items.syncPlayer(player)
    local radius = tonumber(Items.settings["items.sync_radius"]) or 150
    local x, y = getElementPosition(player)
    Items.db.query(Items.syncSql(x, y, radius), {}, function(rows, ctx)
        if not rows or not isElement(ctx.player) or not Items.sent[ctx.player] then
            return
        end
        local dim, int = getElementDimension(ctx.player), getElementInterior(ctx.player)
        local visible = {}
        for _, r in ipairs(rows) do
            if (r.dimension or 0) == dim and (r.interior or 0) == int then
                visible[#visible + 1] = r
            end
        end
        local add, remove, sent = diff.compute(Items.sent[ctx.player], visible)
        Items.sent[ctx.player] = sent
        if #add > 0 or #remove > 0 then
            triggerClientEvent(ctx.player, "onClientItemsSync", resourceRoot, { add = add, remove = remove })
        end
    end, { player = player })
end

setTimer(function()
    for player in pairs(Items.sent) do
        if isElement(player) and Items.charId(player) then
            Items.syncPlayer(player)
        end
    end
end, 2000, 0)

-- An item left the world: drop it from every client that shows it.
function Items.forgetEverywhere(itemId)
    for player, sent in pairs(Items.sent) do
        if sent[itemId] then
            sent[itemId] = nil
            if isElement(player) then
                triggerClientEvent(player, "onClientItemsSync", resourceRoot, { add = {}, remove = { itemId } })
            end
        end
    end
end
