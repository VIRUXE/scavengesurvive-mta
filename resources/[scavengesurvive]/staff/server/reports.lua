-- Player reports: /report for everyone, /reports and /deletereports for staff.
-- Upstream: admin/report.pwn (storage) and report-cmds.pwn (the four filing modes and the staff list).
-- Deviation: the dx UI kit has no text-input dialog, so the reason is typed on the command line.
return function(ctx)
    local db, logic, state = ctx.db, ctx.logic, ctx.state
    local M = {}

    local function file(reporter, name, reason, kind, x, y, z, interior, dimension)
        db.exec(
            "INSERT INTO reports (name, reason, type, x, y, z, interior, dimension, by_name, by_account_id)"
                .. " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            {
                name,
                reason:sub(1, 128),
                kind,
                x,
                y,
                z,
                interior,
                dimension,
                ctx.name(reporter),
                ctx.accountId(reporter),
                n = 10,
            },
            function(ok, r)
                if not ok then
                    return ctx.say(r, " >  Your report could not be saved; try again later.")
                end
                ctx.say(r, " >  Report filed. Thank you.")
                ctx.msgStaff(1, " >  %s reported %s, reason: %s", ctx.name(r), name, reason)
            end,
            reporter
        )
    end

    local function nearestPlayer(p, maxDist)
        local px, py, pz = getElementPosition(p)
        local best, bestDist = nil, maxDist
        for _, o in ipairs(getElementsByType("player")) do
            if o ~= p and not state.duty[o] and getElementDimension(o) == getElementDimension(p) then
                local ox, oy, oz = getElementPosition(o)
                local d = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
                if d < bestDist then
                    best, bestDist = o, d
                end
            end
        end
        return best
    end

    ctx.command({
        name = "report",
        level = 0,
        playerOnly = true,
        usage = "/report <name|near|killer> <reason>",
        help = "Report a player by name, the nearest player, or whoever last killed you",
        fn = function(p, args)
            local who, reason = args[1], logic.tail(args, 2)
            if not who or not reason then
                return ctx.say(p, " >  Usage: /report <name|near|killer> <reason>")
            end
            local x, y, z = getElementPosition(p)
            local interior, dimension = getElementInterior(p), getElementDimension(p)
            if who:lower() == "near" then
                local target = nearestPlayer(p, 100)
                if not target then
                    return ctx.sayLang(p, "REPNOPF100M")
                end
                x, y, z = getElementPosition(target)
                return file(
                    p,
                    getPlayerName(target),
                    reason,
                    logic.REPORT_TYPES.near,
                    x,
                    y,
                    z,
                    getElementInterior(target),
                    getElementDimension(target)
                )
            end
            if who:lower() == "killer" then
                local name = state.lastKiller[p]
                if not name then
                    return ctx.sayLang(p, "REPNOPFOUND")
                end
                return file(p, name, reason, logic.REPORT_TYPES.killer, x, y, z, interior, dimension)
            end
            local entry = logic.findPlayer(who, ctx.onlinePlayers())
            if entry then
                if entry.player == p then
                    return ctx.say(p, " >  You cannot report yourself.")
                end
                return file(p, entry.name, reason, logic.REPORT_TYPES.online, x, y, z, interior, dimension)
            end
            -- offline name: stored as typed (upstream "Specific Player Name (Who isn't online now)")
            file(p, who:sub(1, 24), reason, logic.REPORT_TYPES.name, nil, nil, nil, nil, nil)
        end,
    })

    local function showReports(p)
        db.query(
            "SELECT r.id, r.name, r.type, r.read_at, EXISTS(SELECT 1 FROM bans b WHERE b.name = r.name AND b.active = 1"
                .. " AND (b.expires_at IS NULL OR b.expires_at > NOW())) AS banned"
                .. " FROM reports r WHERE r.active = 1 ORDER BY r.created_at DESC LIMIT 32",
            {},
            function(rows, actor)
                if not rows then
                    return ctx.say(actor, " >  An error occurred.")
                end
                if #rows == 0 then
                    return ctx.say(actor, " >  There are no reports to show.")
                end
                local bannedNames = {}
                for _, r in ipairs(rows) do
                    if tonumber(r.banned) == 1 then
                        bannedNames[r.name] = true
                    end
                end
                local rowsUi = logic.reportRows(rows, function(name)
                    return bannedNames[name] == true
                end)
                ctx.openList(
                    actor,
                    "reports",
                    "Reports (" .. #rows .. ")",
                    rowsUi,
                    { "Options", "Close" },
                    function(rowId, actionId)
                        M.action(actor, tonumber(rowId), actionId)
                    end
                )
            end,
            p
        )
    end

    function M.action(actor, reportId, actionId)
        if not reportId then
            return
        end
        if actionId == "view" then
            db.one(
                "SELECT name, reason, type, x, y, z, by_name, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created"
                    .. " FROM reports WHERE id = ?",
                { reportId },
                function(r, a)
                    if not r then
                        return
                    end
                    db.exec("UPDATE reports SET read_at = COALESCE(read_at, NOW()) WHERE id = ?", { reportId })
                    ctx.say(a, " >  #33CCFF%s#FFFF00 (%s) reported by %s on %s", r.name, r.type, r.by_name, r.created)
                    ctx.say(a, " >  Reason: #33CCFF%s", r.reason)
                    if r.x and r.x ~= false then
                        ctx.say(a, " >  Position: %.1f, %.1f, %.1f", r.x, r.y, r.z)
                    end
                    showReports(a)
                end,
                actor
            )
        elseif actionId == "goto" then
            if not state.duty[actor] and ctx.level(actor) < logic.MAX_LEVEL then
                ctx.say(actor, " >  Go on duty (/duty) to teleport to a report.")
                return showReports(actor)
            end
            db.one("SELECT x, y, z, interior, dimension FROM reports WHERE id = ?", { reportId }, function(r, a)
                if not r or not r.x or r.x == false then
                    ctx.say(a, " >  That report has no position.")
                    return showReports(a)
                end
                ctx.closeList(a)
                setElementInterior(a, tonumber(r.interior) or 0)
                setElementDimension(a, tonumber(r.dimension) or 0)
                setElementPosition(a, r.x, r.y, r.z + 1)
                ctx.log(a, "report_goto", nil, nil, "report " .. reportId)
            end, actor)
        elseif actionId == "delete" then
            db.exec(
                "UPDATE reports SET active = 0, read_at = COALESCE(read_at, NOW()) WHERE id = ?",
                { reportId },
                function(_, a)
                    ctx.log(a, "report_delete", nil, nil, "report " .. reportId)
                    showReports(a)
                end,
                actor
            )
        elseif actionId == "deleteall" then
            db.exec(
                "UPDATE reports SET active = 0, read_at = COALESCE(read_at, NOW())"
                    .. " WHERE name = (SELECT name FROM (SELECT name FROM reports WHERE id = ?) AS t)",
                { reportId },
                function(_, a)
                    ctx.log(a, "report_delete_all", nil, nil, "report " .. reportId)
                    showReports(a)
                end,
                actor
            )
        elseif actionId == "unread" then
            db.exec("UPDATE reports SET read_at = NULL WHERE id = ?", { reportId }, function(_, a)
                showReports(a)
            end, actor)
        end
    end

    ctx.command({
        name = "reports",
        level = 1,
        usage = "/reports",
        help = "Open the report list",
        playerOnly = true,
        fn = showReports,
    })

    ctx.command({
        name = "deletereports",
        level = 2,
        usage = "/deletereports",
        help = "Delete every report that has been read",
        fn = function(p)
            db.exec(
                "UPDATE reports SET active = 0 WHERE active = 1 AND read_at IS NOT NULL",
                {},
                function(ok, actor, affected)
                    if not ok then
                        return ctx.say(actor, " >  An error occurred.")
                    end
                    ctx.say(actor, " >  All read reports deleted (%d).", affected or 0)
                    ctx.log(actor, "report_delete_read", nil, nil, tostring(affected or 0))
                end,
                p
            )
        end,
    })

    return M
end
