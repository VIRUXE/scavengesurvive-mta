-- Survival ranking rules: how a life's online seconds read (days, hours, minutes), the order of the online players
-- and the merge of the stored longest lives with the lives running right now.
local M = {}
M.tr = function(s)
    return s
end

M.TOP = 10 -- rows of the longest lives
M.ONLINE_MAX = 24 -- online rows the panel has room for

-- 0 -> "0m", 3720 -> "1h 2m", 90061 -> "1d 1h 1m": the larger units only once they are reached
function M.duration(s)
    local tr = M.tr
    s = math.max(0, math.floor(tonumber(s) or 0))
    local d = math.floor(s / 86400)
    local h = math.floor((s % 86400) / 3600)
    local m = math.floor((s % 3600) / 60)
    local parts = {}
    if d > 0 then
        parts[#parts + 1] = string.format(tr("%dd"), d)
    end
    if d > 0 or h > 0 then
        parts[#parts + 1] = string.format(tr("%dh"), h)
    end
    parts[#parts + 1] = string.format(tr("%dm"), m)
    return table.concat(parts, " ")
end

local STATE_ORDER = { alive = 1, dead = 2, none = 3 }

-- online rows { name, s, state = "alive"|"dead"|"none" }: living characters by time alive, then the dead, then
-- players still logging in; ties by name
function M.sortOnline(rows)
    table.sort(rows, function(a, b)
        local oa, ob = STATE_ORDER[a.state] or 3, STATE_ORDER[b.state] or 3
        if oa ~= ob then
            return oa < ob
        end
        if a.s ~= b.s then
            return a.s > b.s
        end
        return a.name < b.name
    end)
    return rows
end

-- stored: each account's longest life from the database { account, name, s, alive }; live: the lives running now
-- { account, name, s, run } (online, alive; run = its clock is ticking, false on staff duty). The longer of the two
-- stands for the account and takes the live one's run. Best first, at most `limit`.
function M.merge(stored, live, limit)
    local byAccount, out = {}, {}
    for _, r in ipairs(stored) do
        local e = { account = r.account, name = r.name, s = r.s, alive = r.alive, run = false }
        byAccount[r.account] = e
        out[#out + 1] = e
    end
    for _, r in ipairs(live) do
        local e = byAccount[r.account]
        if not e then
            e = { account = r.account, name = r.name, s = 0, alive = true, run = false }
            byAccount[r.account] = e
            out[#out + 1] = e
        end
        -- an account has one living character, so a stored best that is still alive is this running life
        if r.s >= e.s or e.alive then
            e.s, e.alive, e.run = math.max(e.s, r.s), true, r.run ~= false
        end
    end
    table.sort(out, function(a, b)
        if a.s ~= b.s then
            return a.s > b.s
        end
        return a.name < b.name
    end)
    for i = #out, (limit or M.TOP) + 1, -1 do
        out[i] = nil
    end
    return out
end

-- a row's seconds `elapsedMs` after the snapshot arrived: only a running clock moves
function M.secondsAt(row, elapsedMs)
    if row.run then
        return row.s + math.floor(elapsedMs / 1000)
    end
    return row.s
end

return M
