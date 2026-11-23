-- Events only the recorder knows (a hit with its weapon and damage), buffered and written to replay_event in one
-- call every few seconds. Everything else in replay_event comes from the game log (tools/replay_import_log.py).
return function(ctx)
    local db = ctx.db
    local M = {}

    local FLUSH_MS = 5000
    local MAX_PENDING = 2000
    local pending = {}
    local timer = false
    local seq = 0

    local function number(v)
        v = tonumber(v)
        return v and math.floor(v * 100 + 0.5) / 100 or nil
    end

    -- ev = { kind, char, other, account, x, y, z, int, dim, data = {..} }
    function M.push(ev)
        if #pending >= MAX_PENDING then
            return
        end
        seq = seq + 1
        ev.tick = getTickCount()
        -- a signature no log line can produce: the md5 of the time, a counter and the kind
        ev.sig = md5(string.format("%d|%d|%s|%s", getRealTime().timestamp, seq, ev.kind, tostring(ev.char)))
            :sub(1, 16)
            :lower()
        pending[#pending + 1] = ev
    end

    function M.flush()
        if #pending == 0 or not ctx.ready then
            return
        end
        local now = getTickCount()
        local rows = {}
        for i, ev in ipairs(pending) do
            rows[i] = {
                ago = now - ev.tick,
                kind = ev.kind,
                char = ev.char,
                other = ev.other,
                account = ev.account,
                x = number(ev.x),
                y = number(ev.y),
                z = number(ev.z),
                int = ev.int,
                dim = ev.dim,
                sig = ev.sig,
                data = ev.data,
            }
        end
        pending = {}
        -- toJSON wraps its argument in an outer array; the procedure reads '$[0][*]'
        db.call("replay_event_save", { toJSON(rows, true) }, function(res)
            if not res or not res.ok then
                outputServerLog("[replay] replay_event_save failed: " .. tostring(res and res.code or "db"))
            end
        end)
    end

    function M.start()
        timer = setTimer(M.flush, FLUSH_MS, 0)
    end

    function M.stop()
        if isTimer(timer) then
            killTimer(timer)
        end
        M.flush()
    end

    return M
end
