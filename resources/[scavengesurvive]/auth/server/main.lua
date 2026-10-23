local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local accountsModule
do
    local f = fileOpen("server/accounts.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    accountsModule = assert(loadstring(src, "=auth/accounts.lua"))()
end

local access
do
    local f = fileOpen("shared/logic/access.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    access = assert(loadstring(src, "=auth/access.lua"))()
end

local session = {} -- player -> account table
local pending = {} -- player -> true while a login/register request is in flight
local checking = {} -- player -> true while the join-time ban lookup is in flight
local wantsPrompt = {} -- player -> true when the client was ready before the ban lookup finished
local blocked = {} -- player -> true once a ban (or the whitelist) kicked them
local whitelistEnabled = false
local accounts
local warnedNoDb = false

local function kickLater(player, reason)
    blocked[player] = true
    setTimer(function(p, r)
        if isElement(p) then
            kickPlayer(p, r)
        end
    end, 1000, 1, player, reason)
end

-- Ban check on join (upstream BanCheck in OnPlayerConnect): name, IP or serial; the prompt waits for the answer.
local function checkBan(player)
    if not accounts then
        return
    end
    checking[player] = true
    db.one(access.BAN_SQL, { getPlayerName(player), getPlayerIP(player), getPlayerSerial(player) }, function(row, p)
        checking[p] = nil
        if not isElement(p) then
            return
        end
        if row then
            for _, line in ipairs(access.banLines(row)) do
                outputChatBox(line, p, 255, 80, 80)
            end
            util.log("auth", "info", "%s refused: ban %d (%s)", getPlayerName(p), row.id, tostring(row.reason))
            db.exec("UPDATE bans SET ip = ?, serial = ? WHERE id = ? AND name = ?", {
                getPlayerIP(p),
                getPlayerSerial(p),
                row.id,
                getPlayerName(p),
            })
            return kickLater(p, "Banned: " .. tostring(row.reason))
        end
        if wantsPrompt[p] then
            wantsPrompt[p] = nil
            prompt(p)
        end
    end, player)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("auth") then
        return
    end
    accounts = accountsModule.new({
        db = db,
        hash = function(pw, cb)
            passwordHash(pw, "bcrypt", { cost = 10 }, cb)
        end,
        verify = function(pw, hash, cb)
            passwordVerify(pw, hash, {}, cb)
        end,
        serial = function(p)
            return getPlayerSerial(p)
        end,
        ip = function(p)
            return getPlayerIP(p)
        end,
    })
    db.settings(function(map)
        whitelistEnabled = access.whitelistEnabledFromSetting(map["server.whitelist"])
    end)
end)

addEventHandler("onPlayerJoin", root, function()
    checkBan(source)
end)

function prompt(player)
    if not accounts then
        if not warnedNoDb then
            warnedNoDb = true
            util.log("auth", "warn", "database unavailable; players cannot authenticate")
        end
        return
    end
    if blocked[player] then
        return
    end
    if checking[player] then
        wantsPrompt[player] = true
        return
    end
    accounts.lookup(getPlayerName(player), function(row)
        if not isElement(player) then
            return
        end
        triggerClientEvent(player, "authPromptShown", player, row and "login" or "register")
    end)
end

-- MTA drops a client event the client has not added yet, so the prompt waits until auth's client
-- scripts run on that player: onPlayerResourceStart fires then, on join and again for every
-- connected player when auth restarts.
addEventHandler("onPlayerResourceStart", root, function(res)
    if res == getThisResource() and not session[source] then
        prompt(source)
    end
end)

local function admit(player, account)
    session[player] = account
    local sql = "INSERT INTO connection_log (account_id, name, serial, ip) VALUES (?, ?, ?, ?)"
    db.exec(sql, { account.id, account.name, getPlayerSerial(player), getPlayerIP(player) })
    triggerClientEvent(player, "authResolved", player, true, "OK")
    triggerEvent("playerAuthenticated", player, account.id)
    util.log("auth", "info", "%s authenticated as account %d", account.name, account.id)
end

local function finish(player, ok, code, account)
    pending[player] = nil
    if not isElement(player) or blocked[player] then
        return
    end
    if not ok then
        triggerClientEvent(player, "authResolved", player, false, code)
        return
    end
    if not whitelistEnabled or account.adminLevel > 0 then
        return admit(player, account)
    end
    -- whitelist on (upstream player/whitelist.pwn): only listed names and staff may stay
    db.one("SELECT name FROM whitelist WHERE name = ?", { account.name }, function(row, p)
        if not isElement(p) then
            return
        end
        if access.whitelistAllows(true, row ~= nil and row ~= false, account.adminLevel) then
            return admit(p, account)
        end
        triggerClientEvent(p, "authResolved", p, false, "NOT_WHITELISTED")
        outputChatBox("This server is whitelisted and your name is not on the list.", p, 255, 80, 80)
        util.log("auth", "info", "%s refused: not whitelisted", account.name)
        kickLater(p, "Not whitelisted")
    end, player)
end

net.handler("loginRequested", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.login(player, getPlayerName(player), tostring(password), function(ok, code, account)
        finish(player, ok, code, account)
    end)
end, { rate = 2 })

net.handler("registrationRequested", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.register(player, getPlayerName(player), tostring(password), function(ok, code, account)
        finish(player, ok, code, account)
    end)
end, { rate = 2 })

addEventHandler("onPlayerQuit", root, function(reason)
    local account = session[source]
    if account then
        -- the quit reason travels with the event: character decides whether a leaving player combat-logged
        triggerEvent("playerLoggedOut", source, account.id, reason)
        db.exec("UPDATE connection_log SET left_at = NOW() WHERE account_id = ? AND left_at IS NULL", { account.id })
    end
    session[source] = nil
    pending[source] = nil
    checking[source] = nil
    wantsPrompt[source] = nil
    blocked[source] = nil
    if accounts then
        accounts.forget(source)
    end
end)

function getAccountId(player)
    return session[player] and session[player].id or false
end
function getAdminLevel(player)
    return session[player] and session[player].adminLevel or 0
end
function getLanguage(player)
    return session[player] and session[player].lang or "en"
end
function isAuthenticated(player)
    return session[player] ~= nil
end
-- staff keeps accounts.admin_level in step with the live session after /setadmin
function setSessionAdminLevel(player, level)
    if not session[player] then
        return false
    end
    session[player].adminLevel = tonumber(level) or 0
    return true
end
function setWhitelistEnabled(flag)
    whitelistEnabled = flag == true
    return whitelistEnabled
end
function isWhitelistEnabled()
    return whitelistEnabled
end
