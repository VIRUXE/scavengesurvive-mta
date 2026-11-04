-- Structured game log (docs/superpowers/specs/2026-11-04-logging-loki-design.md).
--   local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
--   log.event("item.pickedUp", { player = player, item_id = id, uname = uname })
--   log.warn("loot", "no spawn rows for zone %s", zone)   -- free text, util.log delegates here
-- Builds one flat JSON line per event and hands it to the `logs` resource, which batches it to Loki. Without a running
-- `logs` resource every line goes to the server console instead, so a dev box that has not started it loses nothing.
local log = {}

local LEVELS = { debug = 0, info = 1, warn = 2, error = 3 }
local PLAYER_KEYS = { "player", "attacker", "victim", "killer", "to", "actor", "target" }
-- fields that are also sent as Loki structured metadata (searchable without being indexed labels)
local META_KEYS = {
    player = true,
    account_id = true,
    character_id = true,
    item_id = true,
    vehicle_id = true,
    attacker = true,
    victim = true,
    killer = true,
    to = true,
    actor = true,
    target = true,
}
local MAX_STRING = 512
local MAX_ARRAY = 24
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local resourceName = getResourceName(getThisResource())
local sink = nil

local function sinkRunning()
    if not sink or not isElement(sink) then
        sink = getResourceFromName("logs")
    end
    return sink and getResourceState(sink) == "running"
end

-- the level threshold and slow-call limit are `logs` settings, re-read every few seconds
local cache = { at = -math.huge, level = LEVELS.info, slowMs = 50 }

local function refresh()
    local now = getTickCount()
    if now - cache.at < 5000 then
        return
    end
    cache.at = now
    cache.level = LEVELS[tostring(get("logs.level") or "info")] or LEVELS.info
    cache.slowMs = tonumber(get("logs.slow_ms")) or 50
end

function log.enabled(level)
    refresh()
    return (LEVELS[level] or LEVELS.info) >= cache.level
end

function log.slowMs()
    refresh()
    return cache.slowMs
end

local function escape(s)
    return (s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end))
end

-- Loki rejects or mangles invalid UTF-8: keep every well-formed sequence, replace any other byte by "?"
local function cleanUtf8(s)
    if not s:find("[\128-\255]") then
        return s
    end
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = 0
        if b < 0x80 then
            len = 1
        elseif b >= 0xC2 and b < 0xE0 then
            len = 2
        elseif b >= 0xE0 and b < 0xF0 then
            len = 3
        elseif b >= 0xF0 and b < 0xF5 then
            len = 4
        end
        local ok = len > 0 and i + len - 1 <= n
        if ok then
            for k = i + 1, i + len - 1 do
                local c = s:byte(k)
                if c < 0x80 or c >= 0xC0 then
                    ok = false
                    break
                end
            end
        end
        if ok then
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        else
            out[#out + 1] = "?"
            i = i + 1
        end
    end
    return table.concat(out)
end

-- cut at a character boundary
local function truncate(s, max)
    if #s <= max then
        return s
    end
    local cut = max
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b < 0x80 or b >= 0xC0 then
            break
        end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "..."
end

local function encodeString(s, max)
    return '"' .. escape(cleanUtf8(truncate(s, max or MAX_STRING))) .. '"'
end

local function encodeScalar(v)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "null"
        end
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return string.format("%d", v)
        end
        return tostring(tonumber(string.format("%.2f", v)))
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return encodeString(v)
    end
    return encodeString(tostring(v))
end

-- a field is a scalar, or an array of scalars (names, item unames, ids)
local function encodeValue(v)
    if type(v) ~= "table" then
        return encodeScalar(v)
    end
    local parts = {}
    for i = 1, math.min(#v, MAX_ARRAY) do
        parts[i] = encodeScalar(v[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- another resource's exported getter; nil when that resource is not running or has no answer
local function ask(resource, fn, ...)
    local res = getResourceFromName(resource)
    if not res or getResourceState(res) ~= "running" then
        return nil
    end
    local ok, value = pcall(call, res, fn, ...)
    if ok and value ~= false then
        return value
    end
    return nil
end

local function isPlayer(v)
    return type(v) == "userdata" and isElement(v) and getElementType(v) == "player"
end

-- level, resource, kind and the fields as one JSON object line, plus the structured metadata (strings only).
-- A player element in player/attacker/victim/killer/to/actor/target becomes its name plus <key>_account_id and
-- <key>_character_id ("player" gives plain account_id / character_id).
function log.build(level, resource, kind, fields)
    local parts = {
        '"level":"' .. level .. '"',
        '"resource":' .. encodeString(resource, 64),
        '"kind":' .. encodeString(kind, 64),
    }
    local meta = {}
    local function put(key, value)
        if value == nil then
            return
        end
        parts[#parts + 1] = encodeString(key, 64) .. ":" .. encodeValue(value)
        if META_KEYS[key] or key:find("_account_id$") or key:find("_character_id$") then
            meta[key] = tostring(value)
        end
    end
    fields = fields or {}
    for key, value in pairs(fields) do
        if type(value) ~= "userdata" and type(value) ~= "function" then
            put(key, value)
        end
    end
    for _, key in ipairs(PLAYER_KEYS) do
        local p = fields[key]
        if isPlayer(p) then
            put(key, getPlayerName(p))
            local prefix = key == "player" and "" or key .. "_"
            if fields[prefix .. "account_id"] == nil then
                put(prefix .. "account_id", ask("auth", "getAccountId", p))
            end
            if fields[prefix .. "character_id"] == nil then
                put(prefix .. "character_id", ask("character", "getCharacterId", p))
            end
        end
    end
    return "{" .. table.concat(parts, ",") .. "}", meta
end

local function emit(kind, fields, level, quiet)
    level = LEVELS[level] and level or "info"
    local rank = LEVELS[level]
    refresh()
    if rank < cache.level then
        return
    end
    -- a logging fault must never reach gameplay: build and send under pcall, the console gets the fault instead
    local built, line, meta = pcall(log.build, level, resourceName, kind, fields)
    if not built then
        outputServerLog(string.format("[%s] log.build failed for %s: %s", resourceName, tostring(kind), tostring(line)))
        return
    end
    local running = sinkRunning()
    if not quiet and (rank >= LEVELS.warn or not running) then
        outputServerLog(string.format("[%s] %s %s", resourceName, kind, fields and fields.msg or line))
    end
    if running then
        pcall(call, sink, "write", level, resourceName, kind, line, meta)
    end
end

-- log.event("item.pickedUp", { player = p, item_id = 7 }, "info"): kind is <domain>.<pastTenseVerb>, level defaults
-- to info; warn and error are echoed to the server console as well
function log.event(kind, fields, level)
    emit(kind, fields, level, false)
end

-- free-text diagnostic (util.log): always echoed to the console as "[tag] message", sent as kind log.message
function log.message(tag, level, fmt, ...)
    local msg = string.format(fmt, ...)
    outputServerLog("[" .. tag .. "] " .. msg)
    emit("log.message", { tag = tag, msg = msg }, level, true)
end

function log.info(tag, fmt, ...)
    log.message(tag, "info", fmt, ...)
end

function log.warn(tag, fmt, ...)
    log.message(tag, "warn", fmt, ...)
end

function log.error(tag, fmt, ...)
    log.message(tag, "error", fmt, ...)
end

return log
