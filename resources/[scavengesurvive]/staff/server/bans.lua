-- Bans, whitelist and account administration. Upstream: admin/ban.pwn, ban-command.pwn, ban-list.pwn,
-- level2.pwn (ban/unban/banlist/banned), level3.pwn (whitelist/ip/setactive/resetpassword), player/whitelist.pwn.
-- Bans live in MariaDB (sql/migrations/0006_staff_m7.sql) and are enforced by auth on join; MTA's own ban list
-- is not used, so a ban follows the name, IP and serial recorded here.
return function(ctx)
    local db, logic, state = ctx.db, ctx.logic, ctx.state
    local M = {}

    local function banNow(actor, name, account, ip, serial, reason, seconds, online)
        db.call("staff_ban", {
            name,
            account and account.id or nil,
            ip,
            serial,
            reason:sub(1, 128),
            ctx.accountId(actor),
            ctx.name(actor),
            seconds,
            n = 8,
        }, function(res, c)
            if not res or not res.ok then
                return ctx.say(c.actor, " >  Ban failed: %s", res and res.code or "db error")
            end
            local until_ = seconds > 0 and ("until " .. tostring(res.payload.expires_at)) or "forever"
            ctx.msgStaff(1, " >  %s banned #33CCFF%s#FFFF00 (%s): %s", ctx.name(c.actor), c.name, until_, c.reason)
            if isElement(c.online) then
                ctx.sayLang(c.online, "BANNEDMESSG", c.reason)
                ctx.kick(c.online, c.actor, "Banned: " .. c.reason)
            end
        end, { actor = actor, name = name, reason = reason, online = online })
    end

    ctx.command({
        name = "ban",
        level = 2,
        usage = "/ban <player|name> <duration|forever> <reason>",
        help = "Ban an account by name, IP and serial (duration: 30m, 12h, 3d, 2w, 1mo, forever)",
        fn = function(p, args, lvl)
            local seconds = logic.parseDuration(args[2] or "")
            local reason = logic.tail(args, 3)
            if not args[1] or not seconds or not reason then
                if args[2] and not seconds then
                    return ctx.say(p, " >  '%s' is not a duration (30m, 12h, 3d, 2w, 1mo or forever).", args[2])
                end
                return ctx.say(p, " >  Usage: /ban <player|name> <duration|forever> <reason>")
            end
            local entry = logic.findPlayer(args[1], ctx.onlinePlayers())
            if entry then
                local target = entry.player
                if target == p then
                    return ctx.say(p, " >  You cannot ban yourself.")
                end
                if ctx.level(target) > 0 and not logic.outranks(lvl, ctx.level(target), false) then
                    return ctx.say(p, " >  %s is staff of your level or higher.", entry.name)
                end
                local accountId = ctx.accountId(target)
                return banNow(
                    p,
                    entry.name,
                    accountId and { id = accountId } or nil,
                    getPlayerIP(target),
                    getPlayerSerial(target),
                    reason,
                    seconds,
                    target
                )
            end
            -- offline: the account supplies the last IP and serial
            ctx.lookupAccount(args[1], function(row, actor)
                if not row then
                    return ctx.say(actor, " >  The account '%s' does not exist.", args[1])
                end
                if
                    (tonumber(row.admin_level) or 0) > 0 and not logic.outranks(lvl, tonumber(row.admin_level), false)
                then
                    return ctx.say(actor, " >  %s is staff of your level or higher.", row.name)
                end
                banNow(actor, row.name, row, row.last_ip or nil, row.last_serial or nil, reason, seconds, nil)
            end, p)
        end,
    })

    ctx.command({
        name = "unban",
        level = 2,
        usage = "/unban <name>",
        help = "Lift every active ban on a name",
        fn = function(p, args)
            if not args[1] then
                return ctx.say(p, " >  Usage: /unban <name>")
            end
            db.call("staff_unban", { args[1], ctx.accountId(p), ctx.name(p), n = 3 }, function(res, actor)
                if not res then
                    return ctx.say(actor, " >  An error occurred.")
                end
                if not res.ok then
                    return ctx.say(actor, " >  Player '%s' is not banned.", args[1])
                end
                ctx.msgStaff(1, " >  %s unbanned #33CCFF%s", ctx.name(actor), args[1])
            end, p)
        end,
    })

    local BAN_SELECT = "SELECT name, reason, by_name, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created,"
        .. " DATE_FORMAT(expires_at, '%Y-%m-%d %H:%i') AS expires_at FROM bans"
        .. " WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())"

    local function showBanList(p)
        db.query(BAN_SELECT .. " ORDER BY created_at DESC LIMIT 100", {}, function(rows, actor)
            if not rows then
                return ctx.say(actor, " >  An error occurred while reading the ban list.")
            end
            if #rows == 0 then
                return ctx.say(actor, " >  No bans to list.")
            end
            ctx.openList(actor, "bans", "Bans (" .. #rows .. ")", logic.banRows(rows), nil, function(rowId, actionId)
                if actionId == "unban" and rowId ~= "none" then
                    executeCommandHandler("unban", actor, tostring(rowId))
                    showBanList(actor)
                end
            end)
        end, p)
    end

    ctx.command({ name = "banlist", level = 2, usage = "/banlist", help = "List active bans", fn = showBanList })

    ctx.command({
        name = "banned",
        level = 2,
        usage = "/banned <name>",
        help = "Show whether and why a name is banned",
        fn = function(p, args)
            if not args[1] then
                return ctx.say(p, " >  Usage: /banned <name>")
            end
            db.one(BAN_SELECT .. " AND name = ? ORDER BY created_at DESC", { args[1] }, function(row, actor)
                if row == false then
                    return ctx.say(actor, " >  An error occurred.")
                end
                if not row then
                    return ctx.say(actor, " >  Player '%s' #33CCFFisn't #FFFF00banned.", args[1])
                end
                ctx.say(
                    actor,
                    " >  %s: banned %s by %s, %s. Reason: #33CCFF%s",
                    row.name,
                    row.created,
                    row.by_name,
                    row.expires_at and row.expires_at ~= false and ("until " .. row.expires_at) or "forever",
                    row.reason
                )
            end, p)
        end,
    })

    -- Whitelist: rows in `whitelist`, the switch in settings server.whitelist; auth enforces it at login.
    local function setWhitelistEnabled(p, flag)
        state.settings["server.whitelist"] = flag and "1" or "0"
        db.exec(
            "INSERT INTO settings (skey, svalue) VALUES ('server.whitelist', ?)"
                .. " ON DUPLICATE KEY UPDATE svalue = VALUES(svalue)",
            {
                flag and "1" or "0",
            }
        )
        pcall(function()
            exports.auth:setWhitelistEnabled(flag)
        end)
        ctx.msgStaff(
            1,
            flag and " >  Whitelist activated, only whitelisted players may join."
                or " >  Whitelist deactivated, anyone may join."
        )
        ctx.log(p, flag and "whitelist_on" or "whitelist_off")
    end

    ctx.command({
        name = "whitelist",
        level = 3,
        usage = "/whitelist add|remove|?|list|on|off [name]",
        help = "Manage the join whitelist",
        fn = function(p, args)
            local verb, name = (args[1] or ""):lower(), args[2]
            local enabled = state.settings["server.whitelist"] == "1"
            if verb == "on" or verb == "off" then
                return setWhitelistEnabled(p, verb == "on")
            elseif verb == "add" and name then
                db.exec(
                    "INSERT IGNORE INTO whitelist (name, added_by) VALUES (?, ?)",
                    { name, ctx.name(p) },
                    function(ok, actor, affected)
                        if not ok then
                            return ctx.say(actor, " >  An error occurred.")
                        end
                        if affected == 0 then
                            return ctx.say(actor, " >  That name #FFAA00is already #FFFF00in the whitelist.")
                        end
                        ctx.say(actor, " >  Added #33CCFF%s #FFFF00to the whitelist.", name)
                        ctx.log(actor, "whitelist_add", name)
                    end,
                    p
                )
            elseif verb == "remove" and name then
                db.exec("DELETE FROM whitelist WHERE name = ?", { name }, function(ok, actor, affected)
                    if not ok then
                        return ctx.say(actor, " >  An error occurred.")
                    end
                    if affected == 0 then
                        return ctx.say(actor, " >  That name #FFAA00is not #FFFF00in the whitelist.")
                    end
                    ctx.say(actor, " >  Removed #33CCFF%s #FFFF00from the whitelist.", name)
                    ctx.log(actor, "whitelist_remove", name)
                end, p)
            elseif verb == "?" and name then
                db.one("SELECT name FROM whitelist WHERE name = ?", { name }, function(row, actor)
                    ctx.say(
                        actor,
                        row and " >  %s #33CCFFis #FFFF00in the whitelist."
                            or " >  %s #FFAA00is not #FFFF00in the whitelist.",
                        name
                    )
                end, p)
            elseif verb == "list" then
                db.query("SELECT name, added_by FROM whitelist ORDER BY name LIMIT 200", {}, function(rows, actor)
                    local out = {}
                    for _, r in ipairs(rows or {}) do
                        out[#out + 1] = { id = r.name, label = r.name .. "  (by " .. tostring(r.added_by) .. ")" }
                    end
                    if #out == 0 then
                        out[1] = { id = "none", label = "Nobody is whitelisted", empty = true }
                    end
                    ctx.openList(
                        actor,
                        "whitelist",
                        "Whitelist (" .. #(rows or {}) .. ")",
                        out,
                        { "Close", "Close" },
                        function()
                            ctx.closeList(actor)
                        end
                    )
                end, p)
            else
                ctx.say(
                    p,
                    " >  Usage: /whitelist add|remove|?|list|on|off [name] - the whitelist is currently %s",
                    enabled and "on" or "off"
                )
            end
        end,
    })

    ctx.command({
        name = "ip",
        level = 3,
        usage = "/ip <player|name>",
        help = "Show a player's IP and serial",
        fn = function(p, args)
            if not args[1] then
                return ctx.say(p, " >  Usage: /ip <player|name>")
            end
            local entry = logic.findPlayer(args[1], ctx.onlinePlayers())
            if entry then
                ctx.log(p, "ip", entry.name, ctx.accountId(entry.player))
                return ctx.say(
                    p,
                    " >  %s: #33CCFF%s#FFFF00 serial #33CCFF%s",
                    entry.name,
                    getPlayerIP(entry.player),
                    getPlayerSerial(entry.player)
                )
            end
            ctx.lookupAccount(args[1], function(row, actor)
                if not row then
                    return ctx.say(actor, " >  The account '%s' does not exist.", args[1])
                end
                ctx.log(actor, "ip", row.name, row.id)
                ctx.say(
                    actor,
                    " >  %s (offline): #33CCFF%s#FFFF00 serial #33CCFF%s",
                    row.name,
                    tostring(row.last_ip or "-"),
                    tostring(row.last_serial or "-")
                )
            end, p)
        end,
    })

    ctx.command({
        name = "setactive",
        level = 3,
        usage = "/setactive <name> <0|1>",
        help = "Deactivate (0) or reactivate (1) an account; inactive accounts cannot log in",
        fn = function(p, args)
            local flag = tonumber(args[2])
            if not args[1] or (flag ~= 0 and flag ~= 1) then
                return ctx.say(p, " >  Usage: /setactive <name> <0|1>")
            end
            db.exec(
                "UPDATE accounts SET active = ? WHERE name = ? AND admin_level < ?",
                { flag, args[1], ctx.level(p) },
                function(ok, actor, affected)
                    if not ok then
                        return ctx.say(actor, " >  An error occurred.")
                    end
                    if affected == 0 then
                        return ctx.say(actor, " >  No such account, or it is staff of your level or higher.")
                    end
                    ctx.say(actor, " >  %s is now %s.", args[1], flag == 1 and "active" or "inactive")
                    ctx.log(actor, flag == 1 and "activate" or "deactivate", args[1])
                    if flag == 0 then
                        local entry = logic.findPlayer(args[1], ctx.onlinePlayers())
                        if entry and entry.name:lower() == args[1]:lower() then
                            ctx.kick(entry.player, actor, "Account deactivated")
                        end
                    end
                end,
                p
            )
        end,
    })

    ctx.command({
        name = "resetpassword",
        level = 3,
        usage = "/resetpassword <name> <new password>",
        help = "Set a new password on an account",
        fn = function(p, args)
            local name, pw = args[1], logic.tail(args, 2)
            if not name or not pw or #pw < 4 or #pw > 32 then
                return ctx.say(p, " >  Usage: /resetpassword <name> <new password> (4-32 characters)")
            end
            passwordHash(pw, "bcrypt", { cost = 10 }, function(hash)
                if not hash then
                    return ctx.say(p, " >  Hashing failed.")
                end
                db.exec(
                    "UPDATE accounts SET password_hash = ? WHERE name = ? AND admin_level < ?",
                    { hash, name, ctx.level(p) },
                    function(ok, actor, affected)
                        if not ok then
                            return ctx.say(actor, " >  An error occurred.")
                        end
                        if affected == 0 then
                            return ctx.say(actor, " >  No such account, or it is staff of your level or higher.")
                        end
                        ctx.say(actor, " >  Password of %s reset.", name)
                        ctx.log(actor, "resetpassword", name)
                    end,
                    p
                )
            end)
        end,
    })

    return M
end
