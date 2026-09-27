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

local session = {} -- player -> account table
local pending = {} -- player -> true while a login/register request is in flight
local accounts
local warnedNoDb = false

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
    for _, p in ipairs(getElementsByType("player")) do
        prompt(p)
    end
end)

function prompt(player)
    if not accounts then
        if not warnedNoDb then
            warnedNoDb = true
            util.log("auth", "warn", "database unavailable; players cannot authenticate")
        end
        return
    end
    accounts.lookup(getPlayerName(player), function(row)
        if not isElement(player) then
            return
        end
        triggerClientEvent(player, "onClientAuthPrompt", player, row and "login" or "register")
    end)
end

addEventHandler("onPlayerJoin", root, function()
    setTimer(function(p)
        if isElement(p) then
            prompt(p)
        end
    end, 1000, 1, source)
end)

local function finish(player, ok, code, account)
    pending[player] = nil
    if not isElement(player) then
        return
    end
    if not ok then
        triggerClientEvent(player, "onClientAuthResult", player, false, code)
        return
    end
    session[player] = account
    db.exec(
        "INSERT INTO connection_log (account_id, name, serial, ip) VALUES (?, ?, ?, ?)",
        { account.id, account.name, getPlayerSerial(player), getPlayerIP(player) }
    )
    triggerClientEvent(player, "onClientAuthResult", player, true, "OK")
    triggerEvent("onPlayerAuthenticated", player, account.id)
    util.log("auth", "info", "%s authenticated as account %d", account.name, account.id)
end

net.handler("onAuthRequestLogin", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.login(player, getPlayerName(player), tostring(password), function(ok, code, account)
        finish(player, ok, code, account)
    end)
end, { rate = 2 })

net.handler("onAuthRequestRegister", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.register(player, getPlayerName(player), tostring(password), function(ok, code, account)
        finish(player, ok, code, account)
    end)
end, { rate = 2 })

addEventHandler("onPlayerQuit", root, function()
    local account = session[source]
    if account then
        triggerEvent("onPlayerLoggedOut", source, account.id)
        db.exec("UPDATE connection_log SET left_at = NOW() WHERE account_id = ? AND left_at IS NULL", { account.id })
    end
    session[source] = nil
    pending[source] = nil
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
