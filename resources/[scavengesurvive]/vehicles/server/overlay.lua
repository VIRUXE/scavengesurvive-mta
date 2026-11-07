-- Duty vehicle-spawn overlay: developer-level staff on duty see the vehicle spawn points around them (client/main.lua
-- draws them) with why each one is or is not producing a vehicle. State order mirrors SELECT_COOLED_SPAWNS in
-- main.lua: disabled, a vehicle standing on it, cooldown, else ready (the refill tick picks ready points at random
-- while the fleet is below its cap).
return function(ctx)
    local M = {}
    local RADIUS, LIMIT = 250, 400
    local MOVE, REFRESH_MS = 60, 15000
    local DEV_LEVEL = 5 -- staff.MAX_LEVEL, "Developer"
    local last = {} -- player -> { x, y, at, pending }

    -- on duty and at dev level; the staff resource includes vehicles, so its level comes through the export
    local function onDuty(p)
        return getElementData(p, "staff.duty") == true and (tonumber(exports.staff:getLevel(p)) or 0) >= DEV_LEVEL
    end

    local function build(rows)
        local out = {}
        for _, r in ipairs(rows) do
            local dueIn = tonumber(r.due_in) or 0
            local state = "ready"
            if tonumber(r.enabled) ~= 1 then
                state = "disabled"
            elseif r.occupant_id then
                state = "occupied"
            elseif dueIn > 0 then
                state = "cooldown"
            end
            out[#out + 1] = {
                id = r.id, x = r.x, y = r.y, z = r.z, rz = r.rz,
                what = r.type_name or ("group " .. tostring(r.group_name)),
                cats = r.categories, sizes = r.sizes, state = state, dueIn = dueIn,
                occId = r.occupant_id, occType = r.occupant_type, driven = tonumber(r.driven_off) or 0,
            }
        end
        return out
    end

    local function query(p)
        local x, y = getElementPosition(p)
        local s = { x = x, y = y, at = getTickCount(), pending = true }
        last[p] = s
        local box = string.format(
            "POLYGON((%g %g,%g %g,%g %g,%g %g,%g %g))",
            x - RADIUS, y - RADIUS, x + RADIUS, y - RADIUS, x + RADIUS, y + RADIUS, x - RADIUS, y + RADIUS,
            x - RADIUS, y - RADIUS
        )
        local sql = "SELECT s.id, s.x, s.y, s.z, s.rz, s.group_name, s.type_name, s.categories, s.sizes, s.enabled, "
            .. "TIMESTAMPDIFF(SECOND, NOW(), st.next_roll_at) AS due_in, "
            .. "(SELECT v.id FROM vehicles v WHERE v.spawn_id = s.id AND v.left_spawn = 0 LIMIT 1) AS occupant_id, "
            .. "(SELECT v.type_uname FROM vehicles v WHERE v.spawn_id = s.id AND v.left_spawn = 0 LIMIT 1) AS occupant_type, "
            .. "(SELECT COUNT(*) FROM vehicles v WHERE v.spawn_id = s.id AND v.left_spawn = 1) AS driven_off "
            .. "FROM vehicle_spawns s LEFT JOIN vehicle_spawn_state st ON st.spawn_id = s.id "
            .. "WHERE MBRContains(ST_GeomFromText(?), s.pos) LIMIT "
            .. LIMIT
        ctx.db.query(sql, { box }, function(rows)
            if not (isElement(p) and onDuty(p) and last[p] == s) then
                s.pending = nil
                return
            end
            local list = rows and build(rows) or {}
            ctx.db.query(
                "SELECT cap, (SELECT COUNT(*) FROM vehicles) AS alive FROM world_budget "
                    .. "WHERE category = 'vehicles' AND zone = 'all'",
                {},
                function(b)
                    s.pending = nil
                    if isElement(p) and onDuty(p) and last[p] == s then
                        local row = b and b[1] or {}
                        triggerClientEvent(p, "vehicleSpotsChanged", p, list, tonumber(row.alive), tonumber(row.cap))
                    end
                end
            )
        end)
    end

    local function clear(p)
        last[p] = nil
        if isElement(p) then
            triggerClientEvent(p, "vehicleSpotsChanged", p, {})
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
                        if (x - s.x) ^ 2 + (y - s.y) ^ 2 > MOVE * MOVE or now - s.at > REFRESH_MS then
                            query(p)
                        end
                    end
                end
            end
        end, 5000, 0)
    end

    return M
end
