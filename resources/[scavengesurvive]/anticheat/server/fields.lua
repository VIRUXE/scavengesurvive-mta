-- Small server-side equivalent of upstream detfield*.pwn: staff define four-point 2D polygons
-- with a Z band; entering one writes a log row and does not punish the player.
return function(db)
    local fields, inside = {}, {}
    local M = {}

    local function split(text)
        local out = {}
        for word in tostring(text or ""):gmatch("%S+") do
            out[#out + 1] = word
        end
        return out
    end

    local function insidePolygon(x, y, points)
        local hit = false
        local j = #points
        for i = 1, #points do
            local a, b = points[i], points[j]
            if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
                hit = not hit
            end
            j = i
        end
        return hit
    end

    local function refresh()
        db.query("SELECT id, name, points, min_z, max_z FROM anticheat_fields ORDER BY name", {}, function(rows)
            fields = {}
            for _, row in ipairs(rows or {}) do
                local points = fromJSON(row.points)
                if type(points) == "table" and #points == 4 then
                    row.points = points
                    fields[#fields + 1] = row
                end
            end
        end)
    end

    local function reply(player, message)
        outputChatBox(" >  " .. message, player, 255, 255, 0)
    end

    local function authorize(player)
        if not isElement(player) or getElementType(player) ~= "player" then
            return false
        end
        if (tonumber(exports.auth:getAdminLevel(player)) or 0) < 2 then
            return false
        end
        return true
    end

    function M.command(player, _, ...)
        if not authorize(player) then
            return
        end
        local args = split(table.concat({ ... }, " "))
        local action = args[1]
        if action == "add" then
            if #args ~= 12 or not args[2]:match("^[%w_%-]+$") then
                return reply(player, "Usage: /field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ>")
            end
            local values = {}
            for i = 3, 12 do
                values[#values + 1] = tonumber(args[i])
                if not values[#values] then
                    return reply(player, "All field coordinates must be numbers.")
                end
            end
            local points = {}
            for i = 1, 8, 2 do
                points[#points + 1] = { values[i], values[i + 1] }
            end
            local minZ, maxZ = values[9], values[10]
            if minZ >= maxZ then
                return reply(player, "minZ must be lower than maxZ.")
            end
            db.exec(
                "INSERT INTO anticheat_fields (name, points, min_z, max_z) VALUES (?, ?, ?, ?)",
                { args[2], toJSON(points), minZ, maxZ },
                function(ok)
                    if ok then
                        refresh()
                        reply(player, "Detection field '" .. args[2] .. "' added.")
                    else
                        reply(player, "Could not add that field; the name may already be in use.")
                    end
                end
            )
        elseif action == "remove" and args[2] then
            db.exec("DELETE FROM anticheat_fields WHERE name = ?", { args[2] }, function(ok)
                if ok then
                    inside = {}
                    refresh()
                    reply(player, "Detection field '" .. args[2] .. "' removed.")
                end
            end)
        elseif action == "list" then
            if #fields == 0 then
                return reply(player, "There are no detection fields.")
            end
            for _, field in ipairs(fields) do
                reply(player, string.format("%s (Z %.1f to %.1f)", field.name, field.min_z, field.max_z))
            end
        elseif action == "log" and args[2] then
            db.query(
                "SELECT player_name, x, y, z, logged_at FROM anticheat_field_logs WHERE field_id = "
                    .. "(SELECT id FROM anticheat_fields WHERE name = ?) ORDER BY id DESC LIMIT 10",
                { args[2] },
                function(rows)
                    if not rows or #rows == 0 then
                        return reply(player, "No entries recorded for '" .. args[2] .. "'.")
                    end
                    for _, row in ipairs(rows) do
                        reply(
                            player,
                            string.format(
                                "%s at %.1f, %.1f, %.1f (%s)",
                                row.player_name,
                                row.x,
                                row.y,
                                row.z,
                                row.logged_at
                            )
                        )
                    end
                end
            )
        else
            reply(player, "Usage: /field add|list|log|remove ...")
        end
    end

    function M.load()
        refresh()
    end

    function M.update()
        local present = {}
        for _, player in ipairs(getElementsByType("player")) do
            local x, y, z = getElementPosition(player)
            local active = {}
            for _, field in ipairs(fields) do
                local id = tonumber(field.id)
                if z >= tonumber(field.min_z) and z <= tonumber(field.max_z) and insidePolygon(x, y, field.points) then
                    active[id] = true
                    if not (inside[player] and inside[player][id]) then
                        db.exec(
                            "INSERT INTO anticheat_field_logs (field_id, player_name, x, y, z) VALUES (?, ?, ?, ?, ?)",
                            { id, getPlayerName(player), x, y, z }
                        )
                        outputServerLog(
                            string.format(
                                "[anticheat] field %s entered by %s at %.1f, %.1f, %.1f",
                                field.name,
                                getPlayerName(player),
                                x,
                                y,
                                z
                            )
                        )
                    end
                end
            end
            inside[player] = active
            present[player] = true
        end
        for player in pairs(inside) do
            if not present[player] then
                inside[player] = nil
            end
        end
    end

    return M
end
