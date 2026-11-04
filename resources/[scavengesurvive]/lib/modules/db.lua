local db = { conn = false, tag = "game" }
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
-- tag=<resource> makes each option string unique, so share=1 never matches: each resource gets its own connection
-- and the ordering comes from queue=game (one FIFO worker thread for all of them)
local OPTIONS = "share=1;batch=0;autoreconnect=1;multi_statements=0;queue=game;log=1;suppress=1062;tag="

local function setting(key)
    local v = get("lib." .. key)
    return v ~= false and tostring(v) or nil
end

function db.options()
    return OPTIONS .. db.tag
end

function db.connect(tag)
    db.tag = tag or "game"
    local host = "dbname="
        .. (setting("db_name") or "scavengesurvive")
        .. ";host="
        .. (setting("db_host") or "127.0.0.1")
        .. ";port="
        .. (setting("db_port") or "3306")
        .. ";charset=utf8mb4"
    db.conn = dbConnect("mysql", host, setting("db_user") or "root", setting("db_pass") or "", db.options())
    if not db.conn then
        log.event("db.connectFailed", { tag = db.tag, msg = "dbConnect failed" }, "error")
        return false
    end
    return true
end

local function poll(qh, sql, started)
    local rows, a, b = dbPoll(qh, 0)
    if rows == false then
        log.event("db.queryFailed", {
            tag = db.tag,
            errno = a,
            error = b,
            sql = sql:sub(1, 200),
            ms = getTickCount() - started,
            msg = "SQL error " .. tostring(a) .. ": " .. tostring(b) .. " in " .. sql,
        }, "error")
        return false
    end
    return rows, a, b
end

-- every stored procedure call: debug normally, info once it took logs.slow_ms or more (queue wait included)
local function logCall(proc, ok, code, ms)
    local level = ms >= log.slowMs() and "info" or "debug"
    if level == "debug" and not log.enabled("debug") then
        return
    end
    log.event("db.callFinished", { tag = db.tag, proc = proc, ok = ok, code = code, ms = ms }, level)
end

-- params.n: Lua 5.1 cannot count a table with trailing nils, so a caller binding NULL in the last placeholder
-- passes n (otherwise the last ? stays unbound and MTA sends it as text)
function db.query(sql, params, cb, ctx)
    params = params or {}
    local started = getTickCount()
    return dbQuery(function(qh)
        local rows = poll(qh, sql, started)
        if cb then
            cb(rows, ctx)
        end
    end, {}, db.conn, sql, unpack(params, 1, params.n or #params))
end

function db.one(sql, params, cb, ctx)
    return db.query(sql, params, function(rows, c)
        if rows == false then
            return cb(false, c)
        end
        cb(rows[1], c)
    end, ctx)
end

function db.exec(sql, params, cb, ctx)
    params = params or {}
    local started = getTickCount()
    return dbQuery(function(qh)
        local rows, affected, insertId = poll(qh, sql, started)
        if cb then
            cb(rows ~= false, ctx, affected, insertId)
        end
    end, {}, db.conn, sql, unpack(params, 1, params.n or #params))
end

function db.call(proc, params, cb, ctx)
    params = params or {}
    local n = params.n or #params -- Lua 5.1 cannot count a table with trailing nils; callers pass n
    local marks = {}
    for i = 1, n do
        marks[i] = "?"
    end
    local sql = "CALL " .. proc .. "(" .. table.concat(marks, ", ") .. ")"
    local started = getTickCount()
    return dbQuery(function(qh)
        local rows = poll(qh, sql, started)
        if rows == false then
            logCall(proc, false, "DB_ERROR", getTickCount() - started)
            return cb(false, ctx)
        end
        local row = rows[1] or {}
        local payload = nil
        if row.payload and row.payload ~= false and row.payload ~= "" then
            payload = type(row.payload) == "table" and row.payload or fromJSON(row.payload)
        end
        local result = { ok = tonumber(row.ok) == 1, code = row.code or "NO_RESULT", payload = payload }
        logCall(proc, result.ok, result.code, getTickCount() - started)
        cb(result, ctx)
    end, {}, db.conn, sql, unpack(params, 1, n))
end

function db.settings(cb)
    db.query("SELECT skey, svalue FROM settings", {}, function(rows)
        local map = {}
        if rows then
            for _, r in ipairs(rows) do
                map[r.skey] = r.svalue
            end
        end
        cb(map)
    end)
end

return db
