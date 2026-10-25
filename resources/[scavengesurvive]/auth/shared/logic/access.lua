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

-- Whitelist auto mode (upstream whitelist.pwn wl_Auto, setting server.whitelist_auto): off while any level 2+
-- staff member is logged in, on again when the last one leaves. Returns the new state, or nil for no change.
access.AUTO_WHITELIST_LEVEL = 2
function access.autoWhitelist(auto, enabled, staffOnline)
    if not auto then
        return nil
    end
    if enabled and staffOnline > 0 then
        return false
    end
    if not enabled and staffOnline == 0 then
        return true
    end
    return nil
end

-- Auto-login (upstream player/auto-ip-login, setting player.auto_ip_login, off by default): skip the password
-- dialog when the account's last login came from this address. Upstream matched the IP alone; the port also
-- needs the serial, so a shared or NATed IP is not enough.
function access.autoLoginAllowed(enabled, row, ip, serial)
    if not enabled or not row then
        return false
    end
    local lastIp, lastSerial = row.last_ip, row.last_serial
    if type(lastIp) ~= "string" or type(lastSerial) ~= "string" or lastIp == "" or lastSerial == "" then
        return false
    end
    return lastIp == ip and lastSerial == serial
end

return access
