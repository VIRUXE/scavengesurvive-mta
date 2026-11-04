-- Detection-field sweep (upstream admin/detfield*.pwn): once a second every player is tested against the fields
-- in anticheat_fields and each entry is logged once (anticheat_field_logs + the server log); fields never punish.
-- Staff draw and remove them with /field in the staff resource, which calls refreshFields() after every change.
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

-- the player's zone name, or nil when maps is not running
local function zoneOf(player)
    local ok, zone = pcall(function()
        return exports.maps:getPlayerZone(player)
    end)
    return ok and zone or nil
end

return function(db, logic)
    local list, inside = {}, {}
    local M = {}

    function M.refresh()
        db.query("SELECT id, name, points, min_z, max_z FROM anticheat_fields ORDER BY name", {}, function(rows)
            list = {}
            for _, row in ipairs(rows or {}) do
                local field = logic.fromRow(row, fromJSON(row.points))
                if field then
                    list[#list + 1] = field
                end
            end
        end)
    end

    function M.update()
        local present = {}
        for _, player in ipairs(getElementsByType("player")) do
            local x, y, z = getElementPosition(player)
            local active, entered = logic.scan(list, inside[player], x, y, z)
            for _, field in ipairs(entered) do
                db.exec(
                    "INSERT INTO anticheat_field_logs (field_id, player_name, x, y, z) VALUES (?, ?, ?, ?, ?)",
                    { field.id, getPlayerName(player), x, y, z }
                )
                log.event("anticheat.fieldEntered", {
                    player = player,
                    field_id = field.id,
                    field_name = field.name,
                    x = x,
                    y = y,
                    z = z,
                    int = getElementInterior(player),
                    dim = getElementDimension(player),
                    zone = zoneOf(player),
                }, "warn")
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
