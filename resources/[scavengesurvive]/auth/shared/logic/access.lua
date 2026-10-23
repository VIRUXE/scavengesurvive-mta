-- Join/login gate decisions (pure): bans and the whitelist. Upstream: admin/ban.pwn BanCheck and
-- player/whitelist.pwn. Bans match the name, the IP or the serial (upstream matched name or IP; the serial
-- is the MTA replacement for gpci and closes the "no serial field" gap listed in ADR 0007).
local access = {}

-- The SQL that finds the newest active ban for a joining player; parameters: name, ip, serial.
access.BAN_SQL = "SELECT id, name, reason, by_name, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created,"
    .. " DATE_FORMAT(expires_at, '%Y-%m-%d %H:%i') AS expires FROM bans"
    .. " WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())"
    .. " AND (name = ? OR (ip IS NOT NULL AND ip = ?) OR (serial IS NOT NULL AND serial = ?))"
    .. " ORDER BY created_at DESC LIMIT 1"

-- Lines shown to a banned player (upstream dialog: Date / Reason / Unban).
function access.banLines(row)
    local expires = (row.expires and row.expires ~= false) and tostring(row.expires) or "Never"
    return {
        string.format("You are banned (since %s by %s).", tostring(row.created), tostring(row.by_name or "Server")),
        string.format("Reason: %s", tostring(row.reason or "")),
        string.format("Unban: %s", expires),
    }
end

-- Whitelist: when enabled, only listed names and staff accounts may stay logged in.
function access.whitelistAllows(enabled, listed, adminLevel)
    if not enabled then
        return true
    end
    return listed == true or (tonumber(adminLevel) or 0) > 0
end

function access.whitelistEnabledFromSetting(value)
    return value == "1" or value == "true" or value == "on"
end

return access
