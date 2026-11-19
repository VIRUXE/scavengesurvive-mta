-- Survival ranking: answers a client's Tab with every online player's current life and the longest lives ever, both
-- counted in seconds alive while online (characters.alive_s plus the running session, kept by character).
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=ranking/" .. path))()
end
local logic = loadFile("shared/logic/ranking.lua")

local REFRESH_MS = 60000
-- each account's longest life: more rows than shown, since a live life may push stored ones down
local TOP_SQL = "SELECT t.account_id, a.name, t.alive_s, t.alive FROM ("
    .. " SELECT account_id, alive_s, alive,"
    .. " ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY alive_s DESC, alive DESC) AS rn"
    .. " FROM characters WHERE alive_s > 0) t"
    .. " JOIN accounts a ON a.id = t.account_id WHERE t.rn = 1 ORDER BY t.alive_s DESC LIMIT ?"

local stored = {} -- { account, name, s, alive } from the last TOP_SQL
local refreshTimer = nil

local function refresh()
    db.query(TOP_SQL, { logic.TOP * 3 }, function(rows)
        if not rows then
            return util.log("ranking", "error", "top lives query failed")
        end
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = {
                account = r.account_id,
                name = r.name,
                s = tonumber(r.alive_s) or 0,
                alive = tonumber(r.alive) == 1,
            }
        end
        stored = out
    end)
end

-- a death settles a life: read the table again once its alive_s is written
local function refreshSoon()
    if refreshTimer and isTimer(refreshTimer) then
        return
    end
    refreshTimer = setTimer(function()
        refreshTimer = nil
        refresh()
    end, 2000, 1)
end

local function snapshot(requester)
    local online, live = {}, {}
    for _, p in ipairs(getElementsByType("player")) do
        local account = exports.auth:getAccountId(p)
        local s, dead, paused = exports.character:getAliveSeconds(p)
        local row = { name = getPlayerName(p), s = 0, state = "none", run = false, me = p == requester or nil }
        if account and s then
            row.s = s
            if dead then
                row.state = "dead"
            else
                -- on staff duty the clock is paused: shown, but not ticking
                row.state, row.run = "alive", not paused
                local name = exports.auth:getAccountName(p) or row.name
                live[#live + 1] = { account = account, name = name, s = s, run = not paused }
            end
        end
        online[#online + 1] = row
    end
    logic.sortOnline(online)
    for i = #online, logic.ONLINE_MAX + 1, -1 do
        online[i] = nil
    end
    local mine = exports.auth:getAccountId(requester)
    local top = logic.merge(stored, live, logic.TOP)
    for _, r in ipairs(top) do
        r.me = r.account == mine or nil
        r.account = nil
    end
    return { online = online, top = top, players = #getElementsByType("player"), max = getMaxPlayers() }
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("ranking") then
        return
    end
    refresh()
    setTimer(refresh, REFRESH_MS, 0)
end)

addEventHandler("characterDied", root, refreshSoon)

net.handler("rankingRequested", function(player)
    if not exports.auth:getAccountId(player) then
        return
    end
    triggerClientEvent(player, "rankingSynced", resourceRoot, snapshot(player))
end, { rate = 2 })
