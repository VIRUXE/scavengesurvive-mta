local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=auth/" .. path))()
end
local accountsModule = loadFile("server/accounts.lua")
local access = loadFile("shared/logic/access.lua")
local prompts = loadFile("shared/logic/prompt.lua")
local rules = loadFile("shared/logic/rules.lua")

local session = {} -- player -> account table
local pending = {} -- player -> true while a login/register request is in flight
local changing = {} -- player -> true while a /changepass request is in flight
local checking = {} -- player -> true while the join-time ban lookup is in flight
local wantsPrompt = {} -- player -> true when the client was ready before the ban lookup finished
local blocked = {} -- player -> true once a ban (or the whitelist) kicked them
local promptMode = {} -- player -> "login" | "register" while a dialog is up
local promptLang = {} -- player -> language of the dialog texts (the account's, "en" for a new name)
local whitelistEnabled = false
local whitelistAuto = false
local autoIpLogin = false
local whitelistKickS = access.WHITELIST_KICK_S
local countdown = {} -- player -> { timer, ends } while a player not listed waits for the whitelist kick
local accounts
local finish -- defined after prompt, which calls it for an auto-login
local warnedNoDb = false

local function kickLater(player, reason)
    blocked[player] = true
    setTimer(function(p, r)
        if isElement(p) then
            kickPlayer(p, r)
        end
    end, 1000, 1, player, reason)
end

local function t(player, key, ...)
    return exports.data:t(promptLang[player] or "en", key, ...)
end

-- Whitelist countdown (upstream whitelist.pwn): one timer per player, the client counts the seconds down itself.
local function stopCountdown(player, quiet)
    local cd = countdown[player]
    if not cd then
        return
    end
    countdown[player] = nil
    if isTimer(cd.timer) then
        killTimer(cd.timer)
    end
    if not quiet and isElement(player) then
        triggerClientEvent(player, "whitelistCountdownChanged", player, false)
    end
end

local function startCountdown(player)
    local account = session[player]
    if countdown[player] or not account or account.adminLevel > 0 then
        return
    end
    local timer = setTimer(function()
        countdown[player] = nil
        if not isElement(player) or not whitelistEnabled then
            return
        end
        outputChatBox(t(player, "WHITELISTAC"), player, 255, 255, 0, true)
        outputChatBox(t(player, "WHITELISTNO"), player, 255, 255, 0, true)
        util.log("auth", "info", "%s kicked: not whitelisted after the countdown", account.name)
        kickLater(player, "Not in whitelist")
    end, whitelistKickS * 1000, 1)
    countdown[player] = { timer = timer, ends = getTickCount() + whitelistKickS * 1000 }
    triggerClientEvent(player, "whitelistCountdownChanged", player, whitelistKickS)
end

-- The whitelist just turned on: every logged-in player who is neither staff nor listed starts a countdown.
local function startCountdowns()
    local candidates, names = {}, {}
    for p, account in pairs(session) do
        if account.adminLevel == 0 and not countdown[p] then
            candidates[#candidates + 1] = { key = p, name = account.name, adminLevel = account.adminLevel }
            names[#names + 1] = account.name
        end
    end
    if #names == 0 then
        return
    end
    db.query(access.listedSql(#names), names, function(rows)
        if not whitelistEnabled or rows == false then
            return
        end
        local listed = {}
        for _, r in ipairs(rows) do
            listed[string.lower(r.name)] = true
        end
        local targets = access.countdownTargets(candidates, listed)
        for _, p in ipairs(targets) do
            if isElement(p) then
                startCountdown(p)
            end
        end
        util.log("auth", "info", "whitelist on: %d player(s) not listed get %d s", #targets, whitelistKickS)
    end)
end

local function setWhitelist(flag)
    if flag == whitelistEnabled then
        return
    end
    whitelistEnabled = flag
    if flag then
        return startCountdowns()
    end
    for p in pairs(countdown) do
        stopCountdown(p)
    end
end

-- Whitelist auto mode: recount level 2+ staff in session (minus a leaving player) and flip the switch.
local function applyAutoWhitelist(leaving, announceTo)
    local staffOnline = 0
    for p, account in pairs(session) do
        if p ~= leaving and account.adminLevel >= access.AUTO_WHITELIST_LEVEL then
            staffOnline = staffOnline + 1
        end
    end
    local nextState = access.autoWhitelist(whitelistAuto, whitelistEnabled, staffOnline)
    if nextState == nil then
        return
    end
    setWhitelist(nextState)
    util.log("auth", "info", "auto-whitelist: whitelist %s (%d staff online)", nextState and "on" or "off", staffOnline)
    if not nextState and isElement(announceTo) then
        outputChatBox(" >  Auto-whitelist: Deactivated the whitelist.", announceTo, 255, 255, 0)
    end
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
        present = isElement,
    })
    db.settings(function(map)
        whitelistEnabled = access.whitelistEnabledFromSetting(map["server.whitelist"])
        whitelistAuto = access.whitelistEnabledFromSetting(map["server.whitelist_auto"])
        autoIpLogin = access.whitelistEnabledFromSetting(map["player.auto_ip_login"])
        whitelistKickS = access.whitelistKickSeconds(map["server.whitelist_kick_s"])
        applyAutoWhitelist()
    end)
end)

addEventHandler("onPlayerJoin", root, function()
    checkBan(source)
end)

-- The upstream dialog for the mode: title and body in the player's language, the client adds Accept / Leave.
local function showDialog(player, mode, attempts)
    promptMode[player] = mode
    local d = prompts.dialog(mode, getPlayerName(player), attempts)
    local title = t(player, d.titleKey)
    local body = t(player, d.bodyKey, unpack(d.args))
    triggerClientEvent(player, "authPromptShown", player, mode, title, body)
end

-- Leave button, or the fifth wrong password: everyone reads the grey line, the player is kicked (upstream Kick).
local function leave(player)
    local mode = promptMode[player]
    promptMode[player] = nil
    outputChatBox(prompts.leftMessage(getPlayerName(player), mode), root, 175, 175, 175)
    util.log("auth", "info", "%s left the %s dialog", getPlayerName(player), tostring(mode))
    kickLater(player, mode == "register" and "Left without registering" or "Left without logging in")
end

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
        if not isElement(player) or blocked[player] then
            return
        end
        if row == false then
            return kickLater(player, "Account load failed")
        end
        if row and row.active == 0 then
            util.log("auth", "info", "%s refused: account inactive", getPlayerName(player))
            return kickLater(player, "Account inactive")
        end
        promptLang[player] = row and row.lang or "en"
        if access.autoLoginAllowed(autoIpLogin, row, getPlayerIP(player), getPlayerSerial(player)) then
            pending[player] = true
            return accounts.loginTrusted(player, row, function(ok, code, account)
                util.log("auth", "info", "%s auto-logged in by IP and serial", row.name)
                finish(player, ok, code, account, nil, false)
            end)
        end
        showDialog(player, row and "login" or "register")
    end)
end

-- MTA drops a client event the client has not added yet, so the prompt waits until auth's client
-- scripts run on that player: onPlayerResourceStart fires then, on join and again for every
-- connected player when auth restarts.
addEventHandler("onPlayerResourceStart", root, function(res)
    if res ~= getThisResource() then
        return
    end
    if not session[source] then
        return prompt(source)
    end
    local cd = countdown[source]
    if cd then
        local left = math.ceil((cd.ends - getTickCount()) / 1000)
        triggerClientEvent(source, "whitelistCountdownChanged", source, left)
    end
end)

local function admit(player, account, isNew)
    -- one session per account: a client that renamed itself (/nick) keeps its session, so a second client joining
    -- under the account's name must not load and control the same character
    for other, held in pairs(session) do
        if other ~= player and held.id == account.id then
            util.log("auth", "info", "%s refused: account already online as %s", account.name, getPlayerName(other))
            return kickLater(player, "Account already online")
        end
    end
    session[player] = account
    promptMode[player] = nil
    applyAutoWhitelist(nil, player)
    local sql = "INSERT INTO connection_log (account_id, name, serial, ip) VALUES (?, ?, ?, ?)"
    db.exec(sql, { account.id, account.name, getPlayerSerial(player), getPlayerIP(player) })
    if isNew then
        triggerClientEvent(player, "authWelcomeShown", player)
    end
    triggerEvent("playerAuthenticated", player, account.id)
    util.log("auth", "info", "%s authenticated as account %d", account.name, account.id)
end

local function refused(player, code, attempts)
    local r = prompts.onRefused(code, attempts)
    if r.chatKey then
        outputChatBox(t(player, r.chatKey), player, 255, 255, 0, true)
    end
    if r.action == "reprompt" then
        showDialog(player, r.mode, r.attempts)
    elseif r.action == "lookup" then
        prompt(player)
    elseif r.action == "leave" then
        leave(player)
    elseif r.action == "kick" then
        util.log("auth", "info", "%s refused: %s", getPlayerName(player), code)
        kickLater(player, r.reason)
    end
end

function finish(player, ok, code, account, attempts, isNew)
    pending[player] = nil
    if not isElement(player) or blocked[player] then
        return
    end
    if not ok then
        return refused(player, code, attempts)
    end
    if not whitelistEnabled or account.adminLevel > 0 then
        return admit(player, account, isNew)
    end
    -- whitelist on (upstream player/whitelist.pwn): only listed names and staff may stay
    db.one("SELECT name FROM whitelist WHERE name = ?", { account.name }, function(row, p)
        if not isElement(p) then
            return
        end
        if access.whitelistAllows(true, row ~= nil and row ~= false, account.adminLevel) then
            return admit(p, account, isNew)
        end
        outputChatBox(t(p, "WHITELISTAC"), p, 255, 255, 0, true)
        outputChatBox(t(p, "WHITELISTNO"), p, 255, 255, 0, true)
        util.log("auth", "info", "%s refused: not whitelisted", account.name)
        kickLater(p, "Not whitelisted")
    end, player)
end

net.handler("loginRequested", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.login(player, getPlayerName(player), tostring(password), function(ok, code, account, attempts)
        finish(player, ok, code, account, attempts, false)
    end)
end, { rate = 2 })

net.handler("registrationRequested", function(player, password)
    if session[player] or pending[player] or not accounts then
        return
    end
    pending[player] = true
    accounts.register(player, getPlayerName(player), tostring(password), function(ok, code, account)
        finish(player, ok, code, account, nil, true)
    end)
end, { rate = 2 })

net.handler("authPromptDismissed", function(player)
    if session[player] or pending[player] or blocked[player] or not promptMode[player] then
        return
    end
    leave(player)
end, { rate = 2 })

addEventHandler("onPlayerQuit", root, function(reason)
    local account = session[source]
    if account then
        -- the quit reason travels with the event: character decides whether a leaving player combat-logged
        triggerEvent("playerLoggedOut", source, account.id, reason)
        db.exec("UPDATE connection_log SET left_at = NOW() WHERE account_id = ? AND left_at IS NULL", { account.id })
    end
    if account then
        applyAutoWhitelist(source)
    end
    stopCountdown(source, true)
    session[source] = nil
    pending[source] = nil
    changing[source] = nil
    checking[source] = nil
    wantsPrompt[source] = nil
    blocked[source] = nil
    promptMode[source] = nil
    promptLang[source] = nil
end)

-- /lang <code>: the language every resource reads through getLanguage (data's t()); stored on the account.
addCommandHandler("lang", function(player, _, code)
    if getElementType(player) ~= "player" then
        return
    end
    local account = session[player]
    if not account then
        return outputChatBox(" >  Log in first.", player, 255, 255, 0)
    end
    local codes = exports.data:languages()
    local valid = {}
    for _, c in ipairs(codes) do
        valid[c] = true
    end
    code = type(code) == "string" and code:lower() or nil
    if not code or not valid[code] then
        local list = table.concat(codes, ", ")
        return outputChatBox(string.format(" >  Usage: /lang <%s> (now %s)", list, account.lang), player, 255, 255, 0)
    end
    account.lang = code
    db.exec("UPDATE accounts SET lang = ? WHERE id = ?", { code, account.id })
    outputChatBox(string.format(" >  Language set to %s.", code), player, 255, 255, 0)
    util.log("auth", "info", "%s set language %s", account.name, code)
end)

-- /tooltips (upstream commands.pwn): the pickup and vehicle tips (ui's showTip) on or off; stored on the account.
addCommandHandler("tooltips", function(player)
    local account = getElementType(player) == "player" and session[player]
    if not account then
        return
    end
    account.tooltips = not account.tooltips
    db.exec("UPDATE accounts SET tooltips = ? WHERE id = ?", { account.tooltips and 1 or 0, account.id })
    local key = account.tooltips and "TOOLTIPSON" or "TOOLTIPSOFF"
    outputChatBox(exports.data:t(account.lang, key), player, 255, 255, 0, true)
end)

-- /welcome (upstream commands.pwn): the welcome box again, closable at once
addCommandHandler("welcome", function(player)
    if getElementType(player) == "player" then
        triggerClientEvent(player, "authWelcomeShown", player, 0)
    end
end)

-- /changepass <old> <new> (upstream commands.pwn): verify the old password, store a new bcrypt hash.
addCommandHandler("changepass", function(player, _, oldPw, newPw)
    if getElementType(player) ~= "player" then
        return
    end
    local account = session[player]
    local lang = account and account.lang or "en"
    if not account then
        return outputChatBox(exports.data:t(lang, "LOGGEDINREQ"), player, 255, 255, 0, true)
    end
    if not oldPw or not newPw then
        return outputChatBox(exports.data:t(lang, "CHANGEPASSW"), player, 255, 255, 0, true)
    end
    if changing[player] or not accounts then
        return
    end
    changing[player] = true
    accounts.changePassword(account.id, oldPw, newPw, function(_, code)
        changing[player] = nil
        if not isElement(player) then
            return
        end
        local reply = rules.changePasswordReply(code)
        local r, g, b = unpack(reply.color)
        outputChatBox(exports.data:t(lang, reply.key, newPw), player, r, g, b, true)
        util.log("auth", "info", "%s /changepass: %s", account.name, code)
    end)
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
function tooltipsOn(player)
    return session[player] ~= nil and session[player].tooltips == true
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
    if session[player].adminLevel > 0 then
        stopCountdown(player)
    end
    applyAutoWhitelist()
    return true
end
function setWhitelistEnabled(flag)
    setWhitelist(flag == true)
    return whitelistEnabled
end
-- staff after /whitelist add|remove: a listed player stops counting down, a removed one starts while it is on
function whitelistNameChanged(name, listed)
    name = string.lower(tostring(name))
    for p, account in pairs(session) do
        if string.lower(account.name) == name then
            if listed then
                stopCountdown(p)
            elseif whitelistEnabled then
                startCountdown(p)
            end
        end
    end
end
function setWhitelistAuto(flag)
    whitelistAuto = flag == true
    applyAutoWhitelist()
    return whitelistAuto
end
function isWhitelistAuto()
    return whitelistAuto
end
function isWhitelistEnabled()
    return whitelistEnabled
end
