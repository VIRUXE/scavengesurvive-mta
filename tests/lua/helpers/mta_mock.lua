local M = {}
M.calls = {}
M.tick = 0
M.queued = {}

local function record(name)
    return function(...)
        M.calls[#M.calls + 1] = { name, ... }
        return true
    end
end

function M.install()
    M.calls, M.queued, M.elements = {}, {}, {}
    _G.getTickCount = function() return M.tick end
    _G.outputDebugString = record("outputDebugString")
    _G.outputServerLog = record("outputServerLog")
    _G.outputChatBox = record("outputChatBox")
    _G.addEvent = record("addEvent")
    _G.addEventHandler = function(name, element, fn) M.handlers = M.handlers or {}; M.handlers[name] = fn; return true end
    _G.triggerEvent = record("triggerEvent")
    _G.triggerClientEvent = record("triggerClientEvent")
    _G.cancelEvent = record("cancelEvent")
    _G.isElement = function(e) return M.elements[e] == true end
    _G.getElementType = function(e) return M.elements[e] and "player" or false end
    _G.getResourceName = function() return "test" end
    _G.getThisResource = function() return "res:test" end
    _G.getResourceFromName = function(name) return M.resources and M.resources[name] or false end
    _G.getResourceState = function(res) return res and "running" or "loaded" end
    _G.call = function(res, fn, ...) return M.exports[fn](...) end
    _G.get = function(key) return M.settings and M.settings[key] or false end
    _G.setTimer = function(fn, ms, times, ...) M.queued[#M.queued + 1] = { fn = fn, ms = ms, args = { ... } }; return "timer" end
    _G.killTimer = record("killTimer")
    _G.root, _G.resourceRoot = "root", "resourceRoot"
    _G.toJSON = function(t) return M.json.encode(t) end
    _G.fromJSON = function(s) return M.json.decode(s) end
    -- fake dbConnect/dbQuery: queries are recorded; tests call mock.answer(index, rows) to fire callbacks
    M.queries = {}
    _G.dbConnect = function() return "conn" end
    _G.dbQuery = function(cb, args, conn, sql, ...)
        local q = { cb = cb, args = args, sql = sql, params = { ... }, conn = conn }
        M.queries[#M.queries + 1] = q
        return q
    end
    _G.dbPoll = function(q, timeout)
        if q.result == nil then return nil end
        if q.result == false then return false, q.errCode or 1, q.errMsg or "mock error" end
        return q.result, q.affected or #q.result, q.insertId or 0
    end
    _G.dbFree = record("dbFree")
end

function M.addElement(e) M.elements[e] = true end
function M.removeElement(e) M.elements[e] = nil end
function M.answer(index, rows, affected, insertId)
    local q = M.queries[index]
    q.result, q.affected, q.insertId = rows, affected, insertId
    q.cb(q, unpack(q.args))
end
function M.fail(index, code, msg)
    local q = M.queries[index]
    q.result, q.errCode, q.errMsg = false, code, msg
    q.cb(q, unpack(q.args))
end
function M.fire(name, ...)
    return M.handlers[name](...)
end
function M.runTimers()
    local queued = M.queued
    M.queued = {}
    for _, t in ipairs(queued) do t.fn(unpack(t.args)) end
end

-- minimal JSON (enough for tests): use dkjson if available, else a tiny encoder/decoder for flat tables
local ok, dkjson = pcall(require, "dkjson")
if ok then
    M.json = dkjson
else
    M.json = {
        encode = function(t)
            local parts = {}
            for k, v in pairs(t) do
                parts[#parts + 1] = string.format("%q:%s", tostring(k), type(v) == "string" and string.format("%q", v) or tostring(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
        decode = function(s)
            local t = {}
            for k, v in s:gmatch('"([^"]+)":("?[^,}"]*"?)') do
                if v:sub(1, 1) == '"' then t[k] = v:sub(2, -2)
                elseif v == "true" then t[k] = true elseif v == "false" then t[k] = false
                elseif v == "null" then t[k] = nil else t[k] = tonumber(v) end
            end
            return t
        end,
    }
end
return M
