-- Pure helpers of the Loki push: nanosecond timestamps, the push request body, request options and what a response
-- means. No MTA calls; server/main.lua owns the buffer and the HTTP call.
local M = {}

M.BATCH_SIZE = 500
M.BACKOFF_START_S = 2
M.BACKOFF_MAX_S = 60

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escape(s)
    return (s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end))
end

local function quote(s)
    return '"' .. escape(tostring(s)) .. '"'
end

-- Unix nanoseconds as a decimal STRING: a Lua double cannot hold 1.7e18 exactly. `seq` fills the last six digits, so
-- two lines of the same millisecond stay distinct and keep their order.
function M.timestamp(ms, seq)
    ms = math.floor(ms)
    local sec = math.floor(ms / 1000)
    return string.format("%.0f%03d%06d", sec, ms - sec * 1000, seq % 1000000)
end

-- entries: { ns, line, level, resource, kind, meta }; cfg: { host, env }. One stream per label set, lines in order.
function M.body(entries, cfg)
    local groups, order = {}, {}
    for _, e in ipairs(entries) do
        local key = e.level .. "|" .. e.resource .. "|" .. e.kind
        local g = groups[key]
        if not g then
            g = { entry = e, values = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        local value = "[" .. quote(e.ns) .. "," .. quote(e.line)
        if e.meta and next(e.meta) then
            local m = {}
            for k, v in pairs(e.meta) do
                m[#m + 1] = quote(k) .. ":" .. quote(v)
            end
            value = value .. ",{" .. table.concat(m, ",") .. "}"
        end
        g.values[#g.values + 1] = value .. "]"
    end
    local streams = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        local labels = { '"job":"ss-game"' }
        if cfg.host and cfg.host ~= "" then
            labels[#labels + 1] = '"host":' .. quote(cfg.host)
        end
        if cfg.env and cfg.env ~= "" then
            labels[#labels + 1] = '"env":' .. quote(cfg.env)
        end
        labels[#labels + 1] = '"level":' .. quote(g.entry.level)
        labels[#labels + 1] = '"resource":' .. quote(g.entry.resource)
        labels[#labels + 1] = '"kind":' .. quote(g.entry.kind)
        streams[#streams + 1] = '{"stream":{'
            .. table.concat(labels, ",")
            .. '},"values":['
            .. table.concat(g.values, ",")
            .. "]}"
    end
    return '{"streams":[' .. table.concat(streams, ",") .. "]}"
end

-- fetchRemote options. Credentials are optional: basic auth only when user and password are both set (and no bearer
-- token), a bearer header only when set, the tenant header only when set. A local Loki needs none of them.
function M.pushOptions(cfg, body)
    local headers = { ["Content-Type"] = "application/json" }
    if cfg.tenant ~= "" then
        headers["X-Scope-OrgID"] = cfg.tenant
    end
    if cfg.bearer ~= "" then
        headers["Authorization"] = "Bearer " .. cfg.bearer
    end
    local options = {
        method = "POST",
        headers = headers,
        postData = body,
        queueName = "loki",
        connectionAttempts = 1,
        connectTimeout = 5000,
    }
    if cfg.bearer == "" and cfg.user ~= "" and cfg.pass ~= "" then
        options.username = cfg.user
        options.password = cfg.pass
    end
    return options
end

-- which auth the settings select, for the one console line at start (never the secret)
function M.describeAuth(cfg)
    local auth = "no auth"
    if cfg.bearer ~= "" then
        auth = "bearer token"
    elseif cfg.user ~= "" and cfg.pass ~= "" then
        auth = "basic auth as " .. cfg.user
    end
    if cfg.tenant ~= "" then
        auth = auth .. ", tenant " .. cfg.tenant
    end
    return auth
end

-- "ok" (2xx), "drop" (Loki refuses this very batch: 400 malformed or too old, 413 too large), "config" (401, 403, 404:
-- keep the batch, retry slowly, the settings are wrong) or "retry" (no connection, 408, 429, 5xx)
function M.classify(info)
    if type(info) ~= "table" then
        return "retry"
    end
    local code = tonumber(info.statusCode) or 0
    if code >= 200 and code < 300 then
        return "ok"
    end
    if code == 400 or code == 413 then
        return "drop"
    end
    if code == 401 or code == 403 or code == 404 then
        return "config"
    end
    return "retry"
end

-- 2 s, 4 s, 8 s ... capped at 60 s
function M.nextBackoff(previous)
    if not previous or previous <= 0 then
        return M.BACKOFF_START_S
    end
    return math.min(M.BACKOFF_MAX_S, previous * 2)
end

return M
