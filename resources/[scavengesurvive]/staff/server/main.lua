-- Staff resource: commands gated by accounts.admin_level (1 Game Master, 2 Moderator, 3 Administrator, 4 Lead,
-- 5 Developer), the staff action log, mutes, the MOTD and the list-dialog plumbing shared by the command modules
-- (server/moderation.lua, bans.lua, reports.lua, duty.lua). Upstream: gamemodes/sss/core/admin/*.pwn.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=staff/" .. path))()
end
local logic = loadFile("shared/logic/staff.lua")

local state = {
    ready = false,
    settings = {},
    muted = {}, -- player -> { untilTick = n | nil (permanent), timer }
    frozen = {}, -- player -> timer | true
    duty = {}, -- player -> { skin = previous skin }
    spectating = {}, -- player -> { target, x, y, z, interior, dimension }
    nametags = {}, -- player -> true
    lists = {}, -- player -> { key, handler }
    lastKiller = {}, -- player -> name of the last player who killed them (for /report killer)
    kicked = {}, -- player -> true while a delayed kick is pending
}
local ctx = { db = db, net = net, util = util, logic = logic, reg = logic.newRegistry(), state = state }

local function isConsole(p)
    return getElementType(p) == "console"
end

function ctx.level(p)
    if isConsole(p) then
        return logic.MAX_LEVEL
    end
    return tonumber(exports.auth:getAdminLevel(p)) or 0
end

function ctx.accountId(p)
    if isConsole(p) then
        return nil
    end
    return exports.auth:getAccountId(p) or nil
end

function ctx.name(p)
    if isConsole(p) then
        return "Console"
    end
    return getPlayerName(p)
end

function ctx.lang(p)
    if isConsole(p) then
        return "en"
    end
    return exports.auth:getLanguage(p) or "en"
end

-- Chat lines use the upstream " >  " prefix and yellow; #RRGGBB codes inside are honoured.
function ctx.say(p, fmt, ...)
    local msg = string.format(fmt, ...)
    if isConsole(p) or not isElement(p) then
        return outputServerLog("[staff] " .. msg:gsub("#%x%x%x%x%x%x", ""))
    end
    outputChatBox(msg, p, 255, 255, 0, true)
end

function ctx.sayLang(p, key, ...)
    if not isElement(p) or isConsole(p) then
        return
    end
    outputChatBox(exports.data:t(ctx.lang(p), key, ...), p, 255, 255, 0, true)
end

function ctx.msgAll(fmt, ...)
    outputChatBox(string.format(fmt, ...), root, 255, 255, 0, true)
end

-- Staff-only broadcast (upstream ChatMsgAdmins): every online player at or above minLevel.
function ctx.msgStaff(minLevel, fmt, ...)
    local msg = string.format(fmt, ...)
    for _, p in ipairs(getElementsByType("player")) do
        if ctx.level(p) >= minLevel then
            outputChatBox(msg, p, 255, 255, 0, true)
        end
    end
    outputServerLog("[staff] " .. msg:gsub("#%x%x%x%x%x%x", ""))
end

-- One row per staff action; the ban/warn procedures write theirs inside their own transaction.
function ctx.log(actor, action, targetName, targetAccountId, details)
    if not state.ready then
        return
    end
    local sql = "INSERT INTO staff_actions (actor_account_id, actor_name, action, target_name, target_account_id,"
        .. " details) VALUES (?, ?, ?, ?, ?, ?)"
    db.exec(sql, { ctx.accountId(actor), ctx.name(actor), action, targetName, targetAccountId, details, n = 6 })
    local suffix = details and (" (" .. tostring(details) .. ")") or ""
    util.log("staff", "info", "%s %s %s%s", ctx.name(actor), action, tostring(targetName or ""), suffix)
end

function ctx.onlinePlayers()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        out[#out + 1] = { name = getPlayerName(p), player = p }
    end
    return out
end

function ctx.highestLevelOnline()
    local best = 0
    for _, p in ipairs(getElementsByType("player")) do
        best = math.max(best, ctx.level(p))
    end
    return best
end

-- Resolves a player by (partial) name for the actor, explaining failures in chat.
function ctx.findPlayer(actor, query)
    local entry, code = logic.findPlayer(query, ctx.onlinePlayers())
    if entry then
        return entry.player
    end
    if code == "AMBIGUOUS" then
        ctx.say(actor, " >  '%s' matches more than one player; type more of the name.", tostring(query))
    elseif code == "NOT_FOUND" then
        ctx.say(actor, " >  No player named '%s' is online.", tostring(query))
    else
        ctx.say(actor, " >  Missing player name.")
    end
    return nil
end

-- A player the actor may act on: online, and of a lower staff level (or themselves when allowSelf).
function ctx.target(actor, query, allowSelf)
    local target = ctx.findPlayer(actor, query)
    if not target then
        return nil
    end
    local isSelf = target == actor
    if isSelf and not allowSelf then
        ctx.say(actor, " >  You cannot do that to yourself.")
        return nil
    end
    if not logic.outranks(ctx.level(actor), ctx.level(target), isSelf) then
        ctx.say(actor, " >  %s is staff of your level or higher.", getPlayerName(target))
        return nil
    end
    return target
end

function ctx.lookupAccount(name, cb, actor)
    local sql = "SELECT id, name, admin_level, active, warnings, muted, last_ip, last_serial, registered_at,"
        .. " last_login_at FROM accounts WHERE name = ?"
    db.one(sql, { name }, cb, actor)
end

-- Kick after a short delay so the reason line reaches the client first (upstream KickPlayerDelay, 1 s).
function ctx.kick(target, actor, reason, delayMs)
    if not isElement(target) or state.kicked[target] then
        return false
    end
    state.kicked[target] = true
    setTimer(function(t, a, r)
        if isElement(t) then
            kickPlayer(t, isElement(a) and getElementType(a) == "player" and a or nil, r or "")
        end
    end, delayMs or 1000, 1, target, actor, reason)
    return true
end

-- List dialogs: the server owns the rows and the meaning of each action; the client only draws (ui:listOpen)
-- and echoes uiListActionSelected back as staffListActionSelected.
function ctx.openList(p, key, title, rows, buttons, handler)
    if not isElement(p) or isConsole(p) then
        return ctx.say(p, " >  (dialogs need a connected player)")
    end
    state.lists[p] = { key = key, handler = handler }
    triggerClientEvent(p, "staffListOpened", p, key, title, rows, buttons)
end

function ctx.closeList(p)
    state.lists[p] = nil
    if isElement(p) and not isConsole(p) then
        triggerClientEvent(p, "staffListDismissed", p)
    end
end

net.handler("staffListActionSelected", function(player, key, rowId, actionId)
    local open = state.lists[player]
    if not open or open.key ~= key then
        return
    end
    open.handler(rowId, actionId)
end, { rate = 5 })

net.handler("staffListClosed", function(player, key)
    local open = state.lists[player]
    if open and open.key == key then
        state.lists[player] = nil
    end
end)

-- Runs a registered command for a player or the console: level gate (silent below the level, as upstream's
-- ACMD was), player-only and database checks. Returns whether the command's fn ran.
local function dispatch(p, def, argsText)
    local lvl = ctx.level(p)
    if not logic.canUse(lvl, def.level) then
        return false
    end
    if def.playerOnly and isConsole(p) then
        ctx.say(p, " >  /%s needs a connected player.", def.name)
        return false
    end
    if def.needsDb ~= false and not state.ready then
        ctx.say(p, " >  The database is unavailable; try again shortly.")
        return false
    end
    def.fn(p, logic.words(argsText), lvl)
    return true
end

-- Registers a command. args is the word list; fn(actor, args, actorLevel).
-- Names in logic.CHAT_BRIDGED (kick, ban, mute, unmute, restart) are MTA console commands too: a player typing
-- them hits the server's hardcoded handler first, the stock Default ACL denies it ("ACL: Access denied") and the
-- script handler below never runs. client/main.lua forwards those through staffCommandIssued instead, and the
-- onPlayerCommand handler cancels the hardcoded path so MTA neither acts on them nor prints the denial.
function ctx.command(def)
    logic.register(ctx.reg, def)
    addCommandHandler(def.name, function(p, _, ...)
        dispatch(p, def, table.concat({ ... }, " "))
    end)
end

addEventHandler("onPlayerCommand", root, function(command)
    if logic.CHAT_BRIDGED[command] then
        cancelEvent()
    end
end)

net.handler("staffCommandIssued", function(player, name, argsText)
    local def = logic.CHAT_BRIDGED[name] and ctx.reg.byName[name]
    if def then
        dispatch(player, def, tostring(argsText or ""))
    end
end, { rate = 5 })

-- ---------------------------------------------------------------------------------------------------------
-- Mutes (upstream admin/mute.pwn + player/chat.pwn), persisted on the account so they survive a relog.

local function persistMute(p, muted, untilTick)
    local id = ctx.accountId(p)
    if not id or not state.ready then
        return
    end
    local secs = untilTick and math.max(1, math.ceil((untilTick - getTickCount()) / 1000)) or nil
    local sql =
        "UPDATE accounts SET muted = ?, mute_until = IF(? IS NULL, NULL, NOW() + INTERVAL ? SECOND) WHERE id = ?"
    db.exec(sql, { muted and 1 or 0, secs, secs, id, n = 4 })
end

function ctx.setMuted(p, muted, seconds, persist)
    local cur = state.muted[p]
    if cur and isTimer(cur.timer) then
        killTimer(cur.timer)
    end
    if not muted then
        state.muted[p] = nil
        if persist ~= false then
            persistMute(p, false)
        end
        return
    end
    local m = { untilTick = seconds and seconds > 0 and (getTickCount() + seconds * 1000) or nil }
    if m.untilTick then
        m.timer = setTimer(function(pl)
            if isElement(pl) then
                ctx.setMuted(pl, false)
                ctx.sayLang(pl, "MUTEDUNMUTE")
            end
        end, seconds * 1000, 1, p)
    end
    state.muted[p] = m
    if persist ~= false then
        persistMute(p, true, m.untilTick)
    end
end

addEventHandler("onPlayerChat", root, function()
    local remaining = logic.muteRemaining(state.muted[source], getTickCount())
    if remaining == nil then
        return
    end
    cancelEvent()
    if remaining == 0 then
        ctx.sayLang(source, "MUTEDPERMAN")
    else
        ctx.sayLang(source, "MUTEDTIMERM", logic.formatDuration(remaining))
    end
end)

-- ---------------------------------------------------------------------------------------------------------
-- Lifecycle

-- Persisted mute of a freshly authenticated (or already connected, after a restart) player.
local function loadMute(p)
    local sql = "SELECT muted, IF(mute_until IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), mute_until)))"
        .. " AS remaining FROM accounts WHERE id = ?"
    db.one(sql, { ctx.accountId(p) }, function(row, pl)
        if not row or not isElement(pl) or tonumber(row.muted) ~= 1 then
            return
        end
        local remaining = tonumber(row.remaining)
        if remaining == nil or remaining == false then
            ctx.setMuted(pl, true, nil, false)
        elseif remaining > 0 then
            ctx.setMuted(pl, true, remaining, false)
        else
            persistMute(pl, false)
        end
    end, p)
end

addEventHandler("playerAuthenticated", root, function()
    if not state.ready then
        return
    end
    local motd = state.settings["server.motd"]
    if motd and motd ~= "" then
        ctx.say(source, " >  #33CCFF%s", motd)
    end
    loadMute(source)
end)

addEventHandler("characterDied", root, function(_, _, killer)
    if isElement(killer) and getElementType(killer) == "player" and killer ~= source then
        state.lastKiller[source] = getPlayerName(killer)
    end
end)

local modules = {}
for _, name in ipairs({ "moderation", "bans", "reports", "duty" }) do
    modules[name] = loadFile("server/" .. name .. ".lua")(ctx)
end

local function forget(p)
    local m = state.muted[p]
    if m and isTimer(m.timer) then
        killTimer(m.timer)
    end
    state.muted[p] = nil
    state.lists[p] = nil
    state.lastKiller[p] = nil
    state.kicked[p] = nil
    modules.moderation.forget(p)
    modules.duty.forget(p)
end

addEventHandler("onPlayerQuit", root, function()
    forget(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    state.ready = db.connect("staff")
    if not state.ready then
        return
    end
    db.settings(function(map)
        state.settings = map
    end)
    for _, p in ipairs(getElementsByType("player")) do
        if ctx.accountId(p) then
            loadMute(p) -- mutes survive a staff restart; never re-raise playerAuthenticated (character would respawn)
        end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do
        modules.moderation.forget(p)
        modules.duty.forget(p)
    end
end)

-- Exports
function getLevel(player)
    return ctx.level(player)
end

-- dev's rcon "cmd" verb: executeCommandHandler applies the Default ACL too, so the bridged names come through here
function runCommand(player, name, argsText)
    local def = ctx.reg.byName[tostring(name)]
    if not def or not isElement(player) then
        return false
    end
    return dispatch(player, def, tostring(argsText or ""))
end

function isOnDuty(player)
    return state.duty[player] ~= nil
end

function isMuted(player)
    return logic.muteRemaining(state.muted[player], getTickCount()) ~= nil
end

-- chat's flood guard mutes through here so the mute shows in /profile and survives a relog
function mutePlayer(player, seconds, reason)
    if not isElement(player) then
        return false
    end
    ctx.setMuted(player, true, tonumber(seconds) or 0)
    ctx.log(player, "mute_auto", getPlayerName(player), ctx.accountId(player), tostring(reason or ""))
    return true
end

function getLevelColour(player)
    return logic.levelColour(ctx.level(player))
end

function logAction(actorName, action, targetName, details)
    if not state.ready then
        return false
    end
    local sql = "INSERT INTO staff_actions (actor_name, action, target_name, details) VALUES (?, ?, ?, ?)"
    db.exec(sql, { tostring(actorName or "Server"), tostring(action), targetName, details, n = 4 })
    return true
end
