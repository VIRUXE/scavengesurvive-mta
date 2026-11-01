-- Upstream ReportPlayer for the automatic checks: one `reports` row filed by the server (type codes of
-- admin/report.pwn: TELE, FLY, VHP, VTP, TRAP) and a line to staff on duty or online at level 1+.
return function(ctx)
    local sql = "INSERT INTO reports (name, reason, type, x, y, z, interior, dimension, info)"
        .. " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"

    return function(player, kind, reason, info)
        if not isElement(player) then
            return
        end
        local name = getPlayerName(player)
        local x, y, z = getElementPosition(player)
        local interior, dimension = getElementInterior(player), getElementDimension(player)
        local text = reason:sub(1, 128)
        local params = { name, text, kind, x, y, z, interior, dimension, info and info:sub(1, 128), n = 9 }
        ctx.db.exec(sql, params)
        exports.staff:notifyStaff(1, string.format(" >  Server reported %s (%s): %s", name, kind, text))
        ctx.log(player, kind, reason)
    end
end
