-- Duty loot overlay: developer-level staff on duty see the loot points around them (client/main.lua draws them) with why each one
-- is or is not rolling. The state order mirrors what rollNear checks: disabled, items still out, cooldown, zone budget.
return function(ctx)
    local M = {}
    local RADIUS, LIMIT = 150, 400
    local MOVE, REFRESH_MS = 40, 15000
    local last = {} -- player -> { x, y, int, dim, at, pending }

    local DEV_LEVEL = 5 -- staff.MAX_LEVEL, "Developer"

    -- on duty and at dev level; the staff resource includes loot, so its level comes through the export at call time
    local function onDuty(p)
        return getElementData(p, "staff.duty") == true and (tonumber(exports.staff:getLevel(p)) or 0) >= DEV_LEVEL
    end

    local function sizeText(size)
        size = tonumber(size) or -1
        return size == -1 and "3-5" or tostring(math.min(size, ctx.roll.MAX_PER_SPAWN))
    end

    local function build(rows)
        local mult = ctx.setting("loot.spawn_multiplier", 1.0)
        local allowance = ctx.allowance()
        local out = {}
        for _, r in ipairs(rows) do
            local left = allowance[r.zone] or 0
            local dueIn, outTotal = tonumber(r.due_in) or 0, tonumber(r.out_total) or 0
            local state = "ready"
            if tonumber(r.enabled) ~= 1 then
                state = "disabled"
            elseif outTotal > 0 then
                state = "blocked"
            elseif dueIn > 0 then
                state = "cooldown"
            elseif left <= 0 then
                state = "nobudget"
            end
            out[#out + 1] = {
                id = r.id, x = r.x, y = r.y, z = r.z, tbl = r.table_name, zone = r.zone,
                chance = math.min(100, math.floor((tonumber(r.weight) or 0) * mult + 0.5)),
                size = sizeText(r.size), state = state, dueIn = dueIn, outTotal = outTotal,
                lying = r.lying, left = left,
            }
        end
        return out
    end

    local function query(p)
        local x, y = getElementPosition(p)
        local int, dim = getElementInterior(p), getElementDimension(p)
        local s = { x = x, y = y, int = int, dim = dim, at = getTickCount(), pending = true }
        last[p] = s
        local box = string.format(
            "POLYGON((%g %g,%g %g,%g %g,%g %g,%g %g))",
            x - RADIUS, y - RADIUS, x + RADIUS, y - RADIUS, x + RADIUS, y + RADIUS, x - RADIUS, y + RADIUS,
            x - RADIUS, y - RADIUS
        )
        local sql = "SELECT s.id, s.x, s.y, s.z, s.table_name, s.weight, s.size, s.zone, s.enabled, "
            .. "TIMESTAMPDIFF(SECOND, NOW(), st.next_roll_at) AS due_in, "
            .. "(SELECT COUNT(*) FROM items i WHERE i.loot_spawn_id = s.id) AS out_total, "
            .. "(SELECT GROUP_CONCAT(i.type_uname SEPARATOR ', ') FROM items i WHERE i.loot_spawn_id = s.id "
            .. "AND i.holder_char_id IS NULL AND i.container_id IS NULL) AS lying "
            .. "FROM loot_spawns s LEFT JOIN loot_spawn_state st ON st.spawn_id = s.id "
            .. "WHERE MBRContains(ST_GeomFromText(?), s.pos) AND s.interior = ? AND s.dimension = ? LIMIT "
            .. LIMIT
        ctx.db.query(sql, { box, int, dim }, function(rows)
            s.pending = nil
            if isElement(p) and onDuty(p) and last[p] == s then
                triggerClientEvent(p, "lootSpotsChanged", p, rows and build(rows) or {})
            end
        end)
    end

    local function clear(p)
        last[p] = nil
        if isElement(p) then
            triggerClientEvent(p, "lootSpotsChanged", p, {})
        end
    end

    addEventHandler("onElementDataChange", root, function(key, _, new)
        if key == "staff.duty" and getElementType(source) == "player" then
            if new == true then
                last[source] = nil
                query(source)
            else
                clear(source)
            end
        end
    end)

    addEventHandler("onPlayerQuit", root, function()
        last[source] = nil
    end)

    function M.start()
        setTimer(function()
            local now = getTickCount()
            for _, p in ipairs(getElementsByType("player")) do
                if onDuty(p) then
                    local s = last[p]
                    if not s then
                        query(p)
                    elseif not s.pending then
                        local x, y = getElementPosition(p)
                        local moved = (x - s.x) ^ 2 + (y - s.y) ^ 2 > MOVE * MOVE
                        local changed = getElementInterior(p) ~= s.int or getElementDimension(p) ~= s.dim
                        if moved or changed or now - s.at > REFRESH_MS then
                            query(p)
                        end
                    end
                end
            end
        end, 5000, 0)
    end

    return M
end
