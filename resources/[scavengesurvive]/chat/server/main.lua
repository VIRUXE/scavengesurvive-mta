-- Chat delivery by mode (upstream core/player/chat.pwn): every chat line is cancelled and re-sent by this
-- resource to the right audience; /g /l /r /me /quiet /freq /radio; the radio frequency and mode persist on the
-- character (characters.radio_freq / chat_mode in sql/schema.sql). Mutes themselves live in staff
-- (exports.staff:isMuted / mutePlayer).
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local logic
do
    local f = fileOpen("shared/logic/chat.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    logic = assert(loadstring(src, "=chat/chat.lua"))()
end
local MODE = logic.MODE

local ready = false
local state = {} -- player -> { mode, oldMode, freq, quiet, streak, lastTick, charId }

local function get(p)
    local st = state[p]
    if not st then
        st = {
            mode = MODE.LOCAL,
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

local function lang(p)
    return exports.auth:getLanguage(p) or "en"
end

local function sayLang(p, key, ...)
    outputChatBox(exports.data:t(lang(p), key, ...), p, 255, 255, 255, true)
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

-- Delivers one message in a mode (0-3, or "me" for /me). Logged like upstream's [CHAT] lines.
local function deliver(p, text, mode)
    local name = getPlayerName(p)
    local st = get(p)
    local audience, rgb, tag
    if mode == MODE.LOCAL or mode == "me" then
        audience, rgb, tag = nearby(p, logic.LOCAL_RANGE), logic.COLOURS[0], mode == "me" and "LOCALME" or "LOCAL"
    elseif mode == MODE.GLOBAL then
        audience, rgb, tag = {}, logic.COLOURS[1], "GLOBAL"
        for _, o in ipairs(getElementsByType("player")) do
            if not (state[o] and state[o].quiet) then
                audience[#audience + 1] = o
            end
        end
    elseif mode == MODE.ADMIN then
        audience, rgb, tag = {}, logic.COLOURS[3], "ADMIN"
        for _, o in ipairs(getElementsByType("player")) do
            if staffLevel(o) > 0 then
                audience[#audience + 1] = o
            end
        end
    else
        audience, rgb, tag = {}, logic.COLOURS[2], string.format("RADIO %.2f", st.freq)
        for _, o in ipairs(getElementsByType("player")) do
            local os = state[o]
            if os and logic.sameFrequency(os.freq, st.freq) then
                audience[#audience + 1] = o
            end
        end
    end
    local colourHex = nil
    if mode == MODE.ADMIN then
        local c = exports.staff:getLevelColour(p)
        if type(c) == "table" then
            colourHex = string.format("#%02X%02X%02X", c[1], c[2], c[3])
        end
    end
    send(logic.format(mode, name, text, st.freq, colourHex), audience, rgb)
    outputServerLog(string.format("[CHAT] [%s] %s: %s", tag, name, text))
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

-- /g /l /r: alone they switch the mode, with text they send one message in that mode (upstream CMD:g/l/r)
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
modeCommand("l", MODE.LOCAL)
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
        local fmt = " >  Usage: /freq <%.1f-%.1f> (now %.2f)"
        return outputChatBox(string.format(fmt, logic.FREQ_MIN, logic.FREQ_MAX, get(p).freq), p, 255, 255, 0)
    end
    setFrequency(p, f)
    outputChatBox(string.format(" >  Radio tuned to %.2f", f), p, 255, 255, 0)
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

net.handler("chatModeRequested", function(p, mode)
    mode = tonumber(mode)
    if logic.isMode(mode) and mode ~= MODE.ADMIN then
        setMode(p, mode, false)
    end
end, { rate = 5 })

-- Frequency and mode travel with the character (upstream saved them in the player file).
addEventHandler("characterSpawned", root, function(charId)
    local st = get(source)
    st.charId = charId
    if not ready then
        return sync(source)
    end
    db.one("SELECT radio_freq, chat_mode FROM characters WHERE id = ?", { charId }, function(row, p)
        if not isElement(p) then
            return
        end
        local s = get(p)
        if row then
            s.freq = logic.clampFreq(row.radio_freq)
            s.mode = logic.isMode(tonumber(row.chat_mode)) and tonumber(row.chat_mode) or MODE.LOCAL
            if s.mode == MODE.ADMIN and staffLevel(p) < 1 then
                s.mode = MODE.LOCAL
            end
        end
        sync(p)
    end, source)
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

local function showInfo(p, title, key)
    triggerClientEvent(p, "chatInfoShown", p, title, logic.dialogBody(exports.data:t(lang(p), key)))
end

playerCommand("help", function(p)
    showInfo(p, "General Information", "GENCOMDHELP")
end)

playerCommand("chatinfo", function(p)
    showInfo(p, "Information about #33CCFFChat", "GENCOMDCHAT")
end)

local function sayList(p, header, settingKey)
    db.one("SELECT svalue FROM settings WHERE skey = ?", { settingKey }, function(row, pl)
        if not isElement(pl) then
            return
        end
        local items = logic.listSetting(row and row.svalue)
        for i, line in ipairs(logic.listLines(header, items)) do
            local r, g, b = 255, 255, 0
            if i > 1 then
                r, g, b = 51, 204, 255
            end
            outputChatBox(line, pl, r, g, b, true)
        end
    end, p)
end

playerCommand("rules", function(p)
    sayList(p, "Rules List", "server.rules")
end)

playerCommand("admins", function(p)
    sayList(p, "Staff List", "server.staff")
end)

playerCommand("credits", function(p)
    for i, line in ipairs(logic.CREDITS) do
        local r, g, b = 51, 204, 255
        if i == 1 then
            r, g, b = 255, 255, 0
        end
        outputChatBox(" >  " .. line, p, r, g, b)
    end
end)

playerCommand("motd", function(p)
    outputChatBox(" >  MoTD: #33CCFF" .. exports.staff:getMotd(), p, 255, 255, 0, true)
end)

addEventHandler("onPlayerJoin", root, function()
    local name = getPlayerName(source)
    for _, line in ipairs(logic.joinLines(name, exports.staff:getMotd())) do
        outputChatBox(line.text, line.toAll and root or source, line.r, line.g, line.b, true)
    end
end)

addEventHandler("onPlayerQuit", root, function(quitType)
    state[source] = nil
    local line = logic.quitLine(getPlayerName(source), quitType)
    if line then
        outputChatBox(line, root, 175, 175, 175)
    end
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

-- Other resources (staff /msg could use it) send a line in a mode on a player's behalf.
function sendAs(player, text, mode)
    if not isElement(player) then
        return false
    end
    deliver(player, tostring(text), tonumber(mode) or get(player).mode)
    return true
end
