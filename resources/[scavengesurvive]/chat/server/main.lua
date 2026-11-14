-- Chat delivery by mode (upstream core/player/chat.pwn): every chat line is cancelled and re-sent by this
-- resource to the right audience; /g /l /r /me /quiet /freq /radio; the radio frequency persists on the
-- character (characters.radio_freq in sql/schema.sql), every spawn starts in global chat. Mutes themselves live in
-- staff (exports.staff:isMuted / mutePlayer). Built-in voice follows the same audiences (Voice section below).
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local logic
do
    local f = fileOpen("shared/logic/chat.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    logic = assert(loadstring(src, "=chat/chat.lua"))()
end
local MODE = logic.MODE
local tr
do
    local f = fileOpen("shared/logic/translate.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    tr = assert(loadstring(src, "=chat/translate.lua"))()
end
local getSetting = get -- MTA's get(); `get` below is this file's state lookup

local ready = false
local state = {} -- player -> { mode, oldMode, freq, quiet, streak, lastTick, charId, voiceWarned }

local function get(p)
    local st = state[p]
    if not st then
        st = {
            mode = MODE.GLOBAL,
            oldMode = MODE.RADIO,
            freq = logic.FREQ_DEFAULT,
            quiet = false,
            streak = 0,
            lastTick = 0,
        }
        state[p] = st
    end
    return st
end

local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
-- a window's labels in p's language (chat.lua's tr argument)
local function trFor(p)
    return function(s)
        return lang.textFor(p, s)
    end
end

local function langOf(p)
    return exports.auth:getLanguage(p) or "en"
end

local function sayLang(p, key, ...)
    outputChatBox(exports.data:t(langOf(p), key, ...), p, 255, 255, 255, true)
end

local function staffLevel(p)
    return tonumber(exports.staff:getLevel(p)) or 0
end

local function isMuted(p)
    return exports.staff:isMuted(p) == true
end

local function sync(p)
    local st = get(p)
    triggerClientEvent(p, "chatRadioChanged", p, st.freq, st.mode)
end

local function persist(p)
    local st = state[p]
    if not ready or not st or not st.charId then
        return
    end
    db.exec("UPDATE characters SET radio_freq = ?, chat_mode = ? WHERE id = ?", { st.freq, st.mode, st.charId })
end

local function setMode(p, mode, announce)
    local st = get(p)
    if mode == MODE.ADMIN and staffLevel(p) < 1 then
        return false
    end
    if st.mode ~= MODE.LOCAL and mode == MODE.LOCAL then
        st.oldMode = st.mode
    end
    st.mode = mode
    persist(p)
    sync(p)
    if announce then
        local key = ({ [0] = "RADIOLOCAL", [1] = "RADIOGLOBAL", [2] = "RADIOFREQUN", [3] = "RADIOADMINC" })[mode]
        sayLang(p, key, st.freq)
    end
    return true
end

local function setFrequency(p, freq)
    local st = get(p)
    st.freq = logic.clampFreq(freq)
    persist(p)
    sync(p)
    return st.freq
end

local function send(line, players, rgb)
    local l1, l2 = logic.split(line)
    for _, pl in ipairs(players) do
        outputChatBox(l1, pl, rgb[1], rgb[2], rgb[3], true)
        if l2 then
            outputChatBox(l2, pl, rgb[1], rgb[2], rgb[3], true)
        end
    end
end

local function nearby(p, range)
    local x, y, z = getElementPosition(p)
    local dim = getElementDimension(p)
    local out = {}
    for _, o in ipairs(getElementsByType("player")) do
        if getElementDimension(o) == dim then
            local ox, oy, oz = getElementPosition(o)
            if getDistanceBetweenPoints3D(x, y, z, ox, oy, oz) <= range then
                out[#out + 1] = o
            end
        end
    end
    return out
end

-- Who a line in this mode reaches: local and /me within 40 m in the same dimension, global everyone not /quiet,
-- admin every staff member, anything else the speaker's radio frequency.
local function audience(p, mode)
    if mode == MODE.LOCAL or mode == "me" then
        return nearby(p, logic.LOCAL_RANGE)
    end
    local out = {}
    for _, o in ipairs(getElementsByType("player")) do
        local os = state[o]
        local hit
        if mode == MODE.GLOBAL then
            hit = not (os and os.quiet)
        elseif mode == MODE.ADMIN then
            hit = staffLevel(o) > 0
        else
            hit = os and logic.sameFrequency(os.freq, get(p).freq)
        end
        if hit then
            out[#out + 1] = o
        end
    end
    return out
end

local LOG_TEXT_MAX = 256

-- the first max bytes of s, backed off to a whole UTF-8 character
local function cut(s, max)
    if #s <= max then
        return s
    end
    local n = max
    while n > 0 do
        local b = s:byte(n + 1)
        if b < 0x80 or b >= 0xC0 then
            break
        end
        n = n - 1
    end
    return s:sub(1, n)
end

-- chat.messageSent: the moderation record of one line (text cut to 256 characters, where the sender stood)
local function logMessage(p, text, mode, freq)
    local x, y, z = getElementPosition(p)
    local line = { player = p, mode = logic.MODE_NAMES[mode] or tostring(mode), text = cut(text, LOG_TEXT_MAX) }
    line.x, line.y, line.z = x, y, z
    line.int, line.dim = getElementInterior(p), getElementDimension(p)
    if mode == MODE.RADIO then
        line.frequency = freq
    end
    local ok, zone = pcall(function()
        return exports.maps:getZoneAt(x, y)
    end)
    line.zone = ok and zone or nil
    log.event("chat.messageSent", line)
end

-- ---------------------------------------------------------------------------------------------------------
-- Translation: after a line goes out, every reader whose language differs from the one it was written in gets
-- a grey line under it in their own language (Google Cloud Translation v2, key `*chat.translate_key` in the
-- server's settings.xml; no key, no translation). One call per reader language, cached; each language has its
-- own fetchRemote queue so translations arrive in the order the lines were said.
local trCache = tr.newCache()
local trPausedUntil = 0

local function showTranslation(res, target, name, readers, rgb)
    if not res or tr.sameLanguage(res.source, target) then
        return
    end
    local l1, l2 = logic.split(tr.line(name, res.text))
    for _, pl in ipairs(readers) do
        if isElement(pl) then
            outputChatBox(l1, pl, rgb[1], rgb[2], rgb[3], true)
            if l2 then
                outputChatBox(l2, pl, rgb[1], rgb[2], rgb[3], true)
            end
        end
    end
end

local function translationFailed(target, code)
    trPausedUntil = getTickCount() + tr.BACKOFF_MS
    log.event("chat.translationFailed", { ok = false, target = target, code = tostring(code) }, "warn")
end

-- relay is called once with the English text for Discord (the original when it is English already, nothing to
-- translate, or the call failed); English is then requested even when no English reader is in the audience.
local function translateFor(speaker, name, text, players, rgb, relay)
    local key = getSetting("translate_key")
    local plain = tr.stripColours(text)
    if type(key) ~= "string" or key == "" or getTickCount() < trPausedUntil or not tr.worthTranslating(plain) then
        if relay then
            relay(text)
        end
        return
    end
    local byTarget = {}
    for _, pl in ipairs(players) do
        if pl ~= speaker and isElement(pl) then
            local target = tr.TARGETS[langOf(pl)] or "en"
            byTarget[target] = byTarget[target] or {}
            table.insert(byTarget[target], pl)
        end
    end
    if relay then
        byTarget.en = byTarget.en or {}
    end
    local function done(target, res)
        showTranslation(res, target, name, byTarget[target], rgb)
        if relay and target == "en" then
            relay(tr.relayText(text, res))
        end
    end
    for target in pairs(byTarget) do
        local cached = tr.cacheGet(trCache, target, plain)
        if cached then
            done(target, cached)
        else
            local options = {
                method = "POST",
                queueName = "chat-tr-" .. target,
                connectionAttempts = 1,
                connectTimeout = 5000,
                headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
                postData = tr.body(plain, target),
            }
            local sent = fetchRemote(tr.URL .. "?key=" .. key, options, function(body, info)
                local status = info and info.statusCode
                if not (info and info.success) or status ~= 200 then
                    translationFailed(target, status or "network")
                    return done(target, nil)
                end
                local data = fromJSON("[" .. tostring(body) .. "]")
                local t = type(data) == "table" and data.data and data.data.translations and data.data.translations[1]
                if type(t) ~= "table" or type(t.translatedText) ~= "string" then
                    translationFailed(target, "parse")
                    return done(target, nil)
                end
                local res = {
                    text = tr.stripColours(tr.decodeEntities(t.translatedText)),
                    source = t.detectedSourceLanguage,
                }
                tr.cachePut(trCache, target, plain, res)
                done(target, res)
            end)
            if not sent then
                translationFailed(target, "fetchRemote")
                done(target, nil)
            end
        end
    end
end

-- Delivers one message in a mode (0-3, or "me" for /me). Logged like upstream's [CHAT] lines.
local function deliver(p, text, mode)
    local name = getPlayerName(p)
    local st = get(p)
    local rgb, tag = logic.COLOURS[2], string.format("RADIO %.2f", st.freq)
    if mode == MODE.LOCAL or mode == "me" then
        rgb, tag = logic.COLOURS[0], mode == "me" and "LOCALME" or "LOCAL"
    elseif mode == MODE.GLOBAL then
        rgb, tag = logic.COLOURS[1], "GLOBAL"
    elseif mode == MODE.ADMIN then
        rgb, tag = logic.COLOURS[3], "ADMIN"
    end
    local colourHex = nil
    if mode == MODE.ADMIN then
        local c = exports.staff:getLevelColour(p)
        if type(c) == "table" then
            colourHex = string.format("#%02X%02X%02X", c[1], c[2], c[3])
        end
    end
    local players = audience(p, mode)
    send(logic.format(mode, name, text, st.freq, colourHex), players, rgb)
    local relay = nil
    if mode == MODE.GLOBAL then
        -- discordchat relays global lines only, in English
        relay = function(english)
            if isElement(p) then
                triggerEvent("globalChatSent", p, english)
            end
        end
    end
    translateFor(p, name, text, players, rgb, relay)
    outputServerLog(string.format("[CHAT] [%s] %s: %s", tag, name, text))
    logMessage(p, text, mode, st.freq)
end

-- Gate every message: logged in, not muted, not flooding; blank text is dropped.
local function accept(p, text)
    if not exports.auth:isAuthenticated(p) then
        return false
    end
    if isMuted(p) then
        return false -- staff's own onPlayerChat handler tells them
    end
    if logic.flood(get(p), getTickCount()) then
        exports.staff:mutePlayer(p, logic.FLOOD_MUTE_S, "chat flooding")
        sayLang(p, "MUTEDFLOODM")
        return false
    end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return false
    end
    return text
end

addEventHandler("onPlayerChat", root, function(message, messageType)
    cancelEvent() -- delivery is ours (MTA would otherwise broadcast it to everyone)
    if messageType == 2 then
        return -- team chat: the gamemode has no teams
    end
    local text = accept(source, message)
    if not text then
        return
    end
    if messageType == 1 then
        return deliver(source, text, "me")
    end
    deliver(source, text, get(source).mode)
end)

-- the command name only (never its arguments: /login carries a password), for the unknown-command question
addEventHandler("onPlayerCommand", root, function(command)
    if log.enabled("debug") then
        log.event("chat.commandUsed", { player = source, command = command }, "debug")
    end
end)

-- /g /l /r (+ /global, /local): alone they switch the mode, with text they send one message in it (upstream CMD:g/l/r)
local function modeCommand(name, mode)
    addCommandHandler(name, function(p, _, ...)
        if getElementType(p) ~= "player" then
            return
        end
        local text = table.concat({ ... }, " ")
        if text == "" then
            return setMode(p, mode, true)
        end
        text = accept(p, text)
        if text then
            deliver(p, text, mode)
        end
    end)
end
modeCommand("g", MODE.GLOBAL)
modeCommand("global", MODE.GLOBAL)
modeCommand("l", MODE.LOCAL)
modeCommand("local", MODE.LOCAL)
modeCommand("r", MODE.RADIO)

addCommandHandler("me", function(p, _, ...)
    if getElementType(p) ~= "player" then
        return
    end
    local text = accept(p, table.concat({ ... }, " "))
    if text then
        deliver(p, text, "me")
    end
end)

addCommandHandler("quiet", function(p)
    if getElementType(p) ~= "player" then
        return
    end
    local st = get(p)
    st.quiet = not st.quiet
    sayLang(p, st.quiet and "RADIOQUIET1" or "RADIOQUIET0")
end)

addCommandHandler("freq", function(p, _, value)
    if getElementType(p) ~= "player" then
        return
    end
    local f = logic.parseFreq(value)
    if not f then
        local usage =
            lang.formatFor(p, "Usage: /freq <%.1f-%.1f> (now %.2f)", logic.FREQ_MIN, logic.FREQ_MAX, get(p).freq)
        return outputChatBox(" >  " .. usage, p, 255, 255, 0)
    end
    setFrequency(p, f)
    outputChatBox(" >  " .. lang.formatFor(p, "Radio tuned to %.2f", f), p, 255, 255, 0)
end)

addCommandHandler("radio", function(p)
    if getElementType(p) == "player" then
        sync(p)
        triggerClientEvent(p, "chatRadioOpened", p)
    end
end)

net.handler("radioTuneRequested", function(p, delta)
    delta = tonumber(delta)
    if not delta or math.abs(delta) > logic.KNOB_STEP + 0.001 then
        return
    end
    setFrequency(p, get(p).freq + delta)
end, { rate = 20 })

net.handler("radioFrequencyEntered", function(p, value)
    local f = logic.parseFreq(value)
    if f then
        setFrequency(p, f)
    end
end, { rate = 5 })

net.handler("chatModeRequested", function(p, mode)
    mode = tonumber(mode)
    if logic.isMode(mode) and mode ~= MODE.ADMIN then
        setMode(p, mode, false)
    end
end, { rate = 5 })

-- The frequency travels with the character (upstream saved it in the player file); the mode always starts global.
addEventHandler("characterSpawned", root, function(charId)
    local st = get(source)
    st.charId = charId
    if not ready then
        return sync(source)
    end
    db.one("SELECT radio_freq FROM characters WHERE id = ?", { charId }, function(row, p)
        if not isElement(p) then
            return
        end
        local s = get(p)
        s.mode = MODE.GLOBAL
        if row then
            s.freq = logic.clampFreq(row.radio_freq)
        end
        sync(p)
    end, source)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Voice (MTA built-in, <voice>1</voice> in mtaserver.conf): a talking player is heard by the text audience of
-- their chat mode joined with the local range, re-chosen every VOICE_REFRESH_MS while they talk. Not logged in or
-- muted: the voice start is cancelled, a muted player is told once per mute.
local talking = {} -- player -> refresh timer while the voice key is held

local function voiceRefresh(p)
    if not isElement(p) then
        return
    end
    if not exports.auth:isAuthenticated(p) or isMuted(p) then
        setPlayerVoiceBroadcastTo(p, {})
        return
    end
    local lists = {}
    for i, mode in ipairs(logic.voiceModes(get(p).mode)) do
        lists[i] = audience(p, mode)
    end
    setPlayerVoiceBroadcastTo(p, logic.voiceRecipients(p, lists))
end

local function voiceStopped(p)
    if talking[p] and isTimer(talking[p]) then
        killTimer(talking[p])
    end
    talking[p] = nil
end

addEventHandler("onPlayerVoiceStart", root, function()
    local st = get(source)
    if not exports.auth:isAuthenticated(source) or isMuted(source) then
        cancelEvent()
        triggerClientEvent(source, "chatVoiceBlocked", source)
        if isMuted(source) and not st.voiceWarned then
            st.voiceWarned = true
            outputChatBox(" >  " .. lang.textFor(source, logic.VOICE_MUTED), source, 255, 255, 0)
        end
        return
    end
    st.voiceWarned = nil
    voiceRefresh(source)
    if not talking[source] then
        talking[source] = setTimer(voiceRefresh, logic.VOICE_REFRESH_MS, 0, source)
    end
end)

addEventHandler("onPlayerVoiceStop", root, function()
    voiceStopped(source)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Info commands (upstream player/commands.pwn): message boxes for /help and /chatinfo, chat lines for the rest.

-- addCommandHandler also hands console commands over; these only make sense for a player
local function playerCommand(name, fn)
    addCommandHandler(name, function(p, ...)
        if getElementType(p) == "player" then
            fn(p, ...)
        end
    end)
end

-- the info commands open CEGUI windows (exports.ui:showInfo, specs from shared/logic/chat.lua)
playerCommand("help", function(p)
    exports.ui:showInfo(p, logic.helpWindow(exports.data:t(langOf(p), "GENCOMDHELP"), trFor(p)))
end)

playerCommand("chatinfo", function(p)
    exports.ui:showInfo(p, logic.textWindow(lang.textFor(p, "Chat"), exports.data:t(langOf(p), "GENCOMDCHAT")))
end)

playerCommand("rules", function(p)
    db.one("SELECT svalue FROM settings WHERE skey = 'server.rules'", {}, function(row, pl)
        if isElement(pl) then
            local title = lang.textFor(pl, "Rules")
            exports.ui:showInfo(pl, logic.listWindow(title, logic.listSetting(row and row.svalue), trFor(pl)))
        end
    end, p)
end)

-- /admins lists the staff accounts themselves (accounts.admin_level), so it never goes stale; online means an
-- account logged in right now
local STAFF_SQL = "SELECT name, admin_level FROM accounts WHERE admin_level > 0 AND active = 1"
    .. " ORDER BY admin_level DESC, name"

playerCommand("admins", function(p)
    db.query(STAFF_SQL, {}, function(rows, pl)
        if not isElement(pl) then
            return
        end
        local online = {}
        for _, player in ipairs(getElementsByType("player")) do
            local name = exports.auth:getAccountName(player)
            if name then
                online[name] = true
            end
        end
        local staffList = {}
        for _, row in ipairs(rows or {}) do
            local rank, r, g, b = exports.staff:getLevelStyle(tonumber(row.admin_level))
            local colour = string.format("#%02X%02X%02X", r, g, b)
            staffList[#staffList + 1] = { name = row.name, rank = rank, colour = colour, online = online[row.name] }
        end
        exports.ui:showInfo(pl, logic.staffWindow(staffList, trFor(pl)))
    end, p)
end)

playerCommand("credits", function(p)
    exports.ui:showInfo(p, logic.creditsWindow(trFor(p)))
end)

playerCommand("pos", function(p)
    local x, y, z = getElementPosition(p)
    outputChatBox(" >  " .. lang.formatFor(p, "Position: #33CCFF%.2f, %.2f, %.2f", x, y, z), p, 255, 255, 0, true)
end)

playerCommand("motd", function(p)
    outputChatBox(" >  MoTD: #33CCFF" .. exports.staff:getMotd(), p, 255, 255, 0, true)
end)

addEventHandler("onPlayerJoin", root, function()
    for _, line in ipairs(logic.joinLines(getPlayerName(source), exports.staff:getMotd())) do
        outputChatBox(line.text, source, line.r, line.g, line.b, true)
    end
end)

-- The "has joined" line for everyone, in each reader's language, with the joiner's language after it.
addEventHandler("playerJoinAnnounced", root, function(code)
    local name = getPlayerName(source)
    local langName = exports.data:languageName(code)
    for _, recipient in ipairs(getElementsByType("player")) do
        -- the joiner has no session yet, so auth cannot say their language: use the one the event carries
        local readerLang = recipient == source and code or lang.code(recipient)
        local template = exports.data:translate(readerLang, logic.JOINED)
        local ok, line = pcall(string.format, template, name, langName)
        if not ok then
            line = string.format(logic.JOINED, name, langName)
        end
        outputChatBox(line, recipient, 255, 255, 255, true)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    voiceStopped(source)
    state[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    ready = db.connect("chat")
    for _, p in ipairs(getElementsByType("player")) do
        local charId = exports.character:getCharacterId(p)
        if charId then
            triggerEvent("characterSpawned", p, charId, false) -- reload this resource's own state only
        end
    end
end)

function getRadio(player)
    local st = state[player]
    if not st then
        return logic.FREQ_DEFAULT, MODE.LOCAL
    end
    return st.freq, st.mode
end

function setChatMode(player, mode)
    return setMode(player, tonumber(mode) or MODE.LOCAL, false)
end

-- Other resources (staff /announce could use it) send a line in a mode on a player's behalf.
function sendAs(player, text, mode)
    if not isElement(player) then
        return false
    end
    deliver(player, tostring(text), tonumber(mode) or get(player).mode)
    return true
end

-- A global line from outside the game (discordchat: Discord messages), shown to everyone not /quiet.
function sendGlobalExternal(tag, name, text)
    local line = string.format("#5865F2[%s] #FFFFFF%s#FFFFFF: %s", tostring(tag), tostring(name), tostring(text))
    local players = audience(nil, MODE.GLOBAL)
    send(line, players, logic.COLOURS[MODE.GLOBAL])
    translateFor(
        nil,
        "[" .. tostring(tag) .. "] " .. tostring(name),
        tostring(text),
        players,
        logic.COLOURS[MODE.GLOBAL]
    )
    outputServerLog(string.format("[CHAT] [%s] %s: %s", tostring(tag), tostring(name), tostring(text)))
    return true
end
