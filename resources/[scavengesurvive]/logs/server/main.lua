-- Pushes the structured game log to Loki (docs/superpowers/specs/2026-11-04-logging-loki-design.md). Other resources
-- call the `write` export through lib's log module; this resource buffers the lines in memory, groups them per label
-- set and POSTs them to <url>/loki/api/v1/push every flush_ms. A failed push keeps the batch and retries with backoff;
-- the buffer is bounded, the oldest lines go first and the loss is reported once Loki answers again.
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=logs/" .. path))()
end

local batch = loadFile("shared/logic/batch.lua")
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

local HEARTBEAT_MS = 60000
local CLOCK_SYNC_MS = 3600000
local REPORT_EVERY_MS = 60000
local SCRIPT_ERRORS_PER_S = 20

local cfg = { push = false }
local clock = { base = 0, tick = 0 }
local seq = 0

-- the ring buffer: buf[head .. tail]
local buf, head, tail = {}, 1, 0
local dropped = 0
local inflight = false
local backoffS = 0
local retryAt = 0
local outageSince = nil
local lastReport = -math.huge
local started = getTickCount()
local flushTimer = false

local function setting(key, default)
    local v = get(key)
    if v == nil or v == false then
        return default
    end
    return tostring(v)
end

local function readConfig()
    cfg = {
        url = setting("url", ""):gsub("/+$", ""),
        tenant = setting("tenant", ""),
        user = setting("user", ""),
        pass = setting("pass", ""),
        bearer = setting("bearer", ""),
        host = setting("host", "mta"),
        env = setting("env", "dev"),
        flushMs = math.max(200, tonumber(setting("flush_ms", "1000")) or 1000),
        maxLines = math.max(500, tonumber(setting("max_lines", "20000")) or 20000),
    }
    cfg.push = cfg.url:find("^https?://") ~= nil
end

local function syncClock()
    clock.base = getRealTime().timestamp * 1000
    clock.tick = getTickCount()
end

local function nowMs()
    return clock.base + (getTickCount() - clock.tick)
end

local function count()
    return tail - head + 1
end

local function enqueue(level, resource, kind, line, meta)
    seq = seq + 1
    tail = tail + 1
    buf[tail] = {
        ns = batch.timestamp(nowMs(), seq),
        line = line,
        level = level,
        resource = resource,
        kind = kind,
        meta = meta,
    }
    local over = count() - cfg.maxLines
    if over > 0 then
        for _ = 1, over do
            buf[head] = nil
            head = head + 1
        end
        dropped = dropped + over
    end
end

local function requeue(entries)
    for i = #entries, 1, -1 do
        head = head - 1
        buf[head] = entries[i]
    end
end

-- the console only: a failing push must never feed back into the buffer
local function console(fmt, ...)
    outputServerLog("[logs] " .. string.format(fmt, ...))
end

-- the resource's own lines (heartbeat, restarts, script errors) go through the same buffer
local function emit(level, kind, fields, resource)
    local line, meta = log.build(level, resource or "logs", kind, fields)
    if cfg.push then
        enqueue(level, resource or "logs", kind, line, meta)
    end
    if level == "warn" or level == "error" then
        console("%s %s", kind, fields and fields.msg or line)
    end
end

local flush

local function onResult(entries, info)
    local verdict = batch.classify(info)
    if verdict == "ok" then
        local wasDown = outageSince ~= nil
        local outageS = wasDown and math.floor((getTickCount() - outageSince) / 1000) or 0
        backoffS, retryAt, outageSince = 0, 0, nil
        if wasDown then
            console("push recovered after %d s", outageS)
        end
        if dropped > 0 then
            emit("warn", "system.logDropped", { dropped = dropped, outage_s = outageS })
            dropped = 0
        end
        if count() >= batch.BATCH_SIZE then
            flush()
        end
        return
    end
    local status = type(info) == "table" and tonumber(info.statusCode) or 0
    if verdict == "drop" then
        console("Loki refused a batch of %d lines (HTTP %d), dropped", #entries, status)
        return
    end
    requeue(entries)
    outageSince = outageSince or getTickCount()
    backoffS = verdict == "config" and batch.BACKOFF_MAX_S or batch.nextBackoff(backoffS)
    retryAt = getTickCount() + backoffS * 1000
    if getTickCount() - lastReport >= REPORT_EVERY_MS then
        lastReport = getTickCount()
        console(
            "push to %s failed (%s), %d lines queued, retry in %d s",
            cfg.url,
            status > 0 and ("HTTP " .. status) or "no connection",
            count(),
            backoffS
        )
    end
end

-- force: the final flush on stop, which ignores a request in flight and the backoff
function flush(force)
    if not cfg.push or count() == 0 then
        return
    end
    if not force and (inflight or getTickCount() < retryAt) then
        return
    end
    local n = math.min(count(), batch.BATCH_SIZE)
    local entries = {}
    for i = 1, n do
        entries[i] = buf[head]
        buf[head] = nil
        head = head + 1
    end
    local options = batch.pushOptions(cfg, batch.body(entries, cfg))
    inflight = true
    local sent = fetchRemote(cfg.url .. "/loki/api/v1/push", options, function(_, info)
        inflight = false
        onResult(entries, info)
    end)
    if not sent then
        inflight = false
        onResult(entries, nil)
    end
end

-- exported: called through lib's log module as call(logsResource, "write", ...)
function write(level, resource, kind, line, meta)
    if not cfg.push or type(line) ~= "string" then
        return
    end
    enqueue(tostring(level), tostring(resource), tostring(kind), line, type(meta) == "table" and meta or nil)
    if count() >= batch.BATCH_SIZE then
        flush()
    end
end

-- MTA's own script errors and warnings (the lines of scripts.log), under the resource named by the file path
local inDebug = false
local errorWindow = { at = 0, n = 0, suppressed = 0 }

local function captureDebug(message, level, file, line)
    local now = getTickCount()
    if now - errorWindow.at >= 1000 then
        if errorWindow.suppressed > 0 then
            emit("warn", "script.suppressed", { count = errorWindow.suppressed })
        end
        errorWindow = { at = now, n = 0, suppressed = 0 }
    end
    errorWindow.n = errorWindow.n + 1
    if errorWindow.n > SCRIPT_ERRORS_PER_S then
        errorWindow.suppressed = errorWindow.suppressed + 1
        return
    end
    local resource = type(file) == "string" and file:match("^([^/]+)/") or "logs"
    emit(
        level == 1 and "error" or "warn",
        level == 1 and "script.error" or "script.warning",
        { msg = message, file = file or "", line = line or 0 },
        resource
    )
end

-- inDebug and the pcall keep an error inside the capture itself from raising another debug message, forever
addEventHandler("onDebugMessage", root, function(message, level, file, line)
    if inDebug or (level ~= 1 and level ~= 2) then
        return
    end
    inDebug = true
    pcall(captureDebug, message, level, file, line)
    inDebug = false
end)

addEventHandler("onResourceStart", root, function(resource)
    emit("info", "system.resourceStarted", { name = getResourceName(resource) })
end)

addEventHandler("onResourceStop", root, function(resource)
    emit("info", "system.resourceStopped", { name = getResourceName(resource) })
    if resource == getThisResource() then
        flush(true)
    end
end)

local function heartbeat()
    emit("info", "system.heartbeat", {
        players = #getElementsByType("player"),
        uptime_s = math.floor((getTickCount() - started) / 1000),
        queued = count(),
        dropped = dropped,
    })
end

addEventHandler("onResourceStart", resourceRoot, function()
    readConfig()
    syncClock()
    if cfg.push then
        console("pushing to %s (%s), host %s, env %s", cfg.url, batch.describeAuth(cfg), cfg.host, cfg.env)
        flushTimer = setTimer(flush, cfg.flushMs, 0)
    elseif cfg.url ~= "" then
        console("url %q is not an http(s) URL: nothing is pushed", cfg.url)
    else
        console("no url set: nothing is pushed (set *logs.url in local.settings.xml)")
    end
    setTimer(syncClock, CLOCK_SYNC_MS, 0)
    setTimer(heartbeat, HEARTBEAT_MS, 0)
    heartbeat()
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(flushTimer) then
        killTimer(flushTimer)
    end
end)
