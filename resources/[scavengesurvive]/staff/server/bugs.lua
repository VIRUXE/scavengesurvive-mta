-- Bug reports (#153, upstream admin/bug-report.pwn): /bug for everyone asks for a description (128 characters) and
-- stores it in bug_reports, telling staff; /issues, also for everyone, lists the oldest 32 and opens one, and from
-- level 2 the open report can be deleted. Every "Back" or "Delete" returns to the list, as upstream.
return function(ctx)
    local db, logic = ctx.db, ctx.logic
    local M = {}

    local function file(p, reason)
        local sql = "INSERT INTO bug_reports (name, account_id, reason) VALUES (?, ?, ?)"
        local params = { ctx.name(p), ctx.accountId(p), reason:sub(1, logic.BUG_REASON_MAX), n = 3 }
        db.exec(sql, params, function(ok, r)
            if not ok then
                return ctx.say(r, " >  Your bug report could not be saved; try again later.")
            end
            ctx.sayLang(r, "BUGREPORTSU")
            ctx.msgStaff(1, " >  %s#FFFF00 reported bug %s", ctx.name(r), reason)
        end, p)
    end

    local showList

    local function showReport(p, bugId)
        local sql = "SELECT id, name, reason, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created"
            .. " FROM bug_reports WHERE id = ?"
        db.one(sql, { bugId }, function(b, actor)
            if not b then
                return showList(actor)
            end
            local canDelete = ctx.level(actor) >= logic.BUG_DELETE_LEVEL
            local buttons = canDelete and { "Delete", "Back" } or { "Back" }
            ctx.openDialog(actor, "bug_report", "msgbox", "Issues", logic.bugText(b), buttons, function(ok)
                if not (ok and canDelete) then
                    return showList(actor)
                end
                db.exec("DELETE FROM bug_reports WHERE id = ?", { b.id }, function()
                    ctx.log(actor, "bug_delete", b.name, nil, b.reason)
                    showList(actor)
                end)
            end)
        end, p)
    end

    showList = function(p)
        local sql = "SELECT id, name, reason FROM bug_reports ORDER BY id LIMIT " .. logic.BUG_LIST_MAX
        db.query(sql, {}, function(rows, actor)
            if not rows then
                return ctx.say(actor, " >  An error occurred.")
            end
            if #rows == 0 then
                return ctx.say(actor, " >  There are no bug reports to show.")
            end
            ctx.openList(actor, "issues", "Issues", logic.bugRows(rows), { "Open", "Close" }, function(rowId)
                showReport(actor, tonumber(rowId))
            end)
        end, p)
    end

    ctx.command({
        name = "bug",
        level = 0,
        playerOnly = true,
        usage = "/bug [description]",
        help = "Report a bug to the staff",
        fn = function(p, args)
            local text = logic.trim(table.concat(args, " "))
            if text ~= "" then
                return file(p, text) -- port addition: the description on the command line skips the dialog
            end
            local body = exports.data:t(ctx.lang(p), "BUGREPORTDI")
            ctx.openDialog(p, "bug", "input", "Bug report", body, { "Submit", "Cancel" }, function(ok, answer)
                local reason = logic.trim(answer)
                if ok and reason ~= "" then
                    file(p, reason)
                end
            end)
        end,
    })

    ctx.command({
        name = "issues",
        level = 0,
        playerOnly = true,
        usage = "/issues",
        help = "List the bug reports",
        fn = showList,
    })

    return M
end
