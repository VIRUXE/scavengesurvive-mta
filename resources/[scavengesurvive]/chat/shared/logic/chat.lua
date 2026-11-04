-- Chat modes and the radio, pure logic. Upstream: core/player/chat.pwn (local 40 m / global / radio by frequency /
-- admin, flood mute, 128-char line split) and core/ui/radio.pwn (87.5-108.0 MHz, 0.5 MHz knobs, power and
-- global/freq toggles on a 200-unit panel at 320,200).
local chat = {}

chat.MODE = { LOCAL = 0, GLOBAL = 1, RADIO = 2, ADMIN = 3 }
chat.MODE_NAMES = { [0] = "local", [1] = "global", [2] = "radio", [3] = "admin" }
chat.LOCAL_RANGE = 40.0
chat.FREQ_MIN, chat.FREQ_MAX, chat.FREQ_DEFAULT = 87.5, 108.0, 98.12
chat.KNOB_STEP, chat.FINE_STEP = 0.5, 0.01
chat.MAX_LINE = 128
chat.FLOOD_WINDOW_MS, chat.FLOOD_STREAK, chat.FLOOD_MUTE_S = 1000, 3, 30
-- GENCOMDCHAT colours: global green text in the help, but upstream sends global lines white; local light blue;
-- radio orange; admin lines carry the staff level colour.
chat.COLOURS = { [0] = { 51, 204, 255 }, [1] = { 255, 255, 255 }, [2] = { 255, 170, 0 }, [3] = { 51, 204, 255 } }

function chat.clampFreq(f)
    f = tonumber(f) or chat.FREQ_DEFAULT
    f = math.floor(f * 100 + 0.5) / 100
    if f < chat.FREQ_MIN then
        return chat.FREQ_MIN
    end
    if f > chat.FREQ_MAX then
        return chat.FREQ_MAX
    end
    return f
end

-- "101.3" -> 101.3; nil when not a number or outside the band (upstream re-asks instead of clamping)
function chat.parseFreq(text)
    local f = tonumber(text)
    if not f or f < chat.FREQ_MIN or f > chat.FREQ_MAX then
        return nil
    end
    return math.floor(f * 100 + 0.5) / 100
end

-- Upstream: -0.05 < a - b < 0.05 counts as the same channel.
function chat.sameFrequency(a, b)
    return math.abs((a or 0) - (b or 0)) < 0.05
end

function chat.isMode(mode)
    return mode == 0 or mode == 1 or mode == 2 or mode == 3
end

-- Voice (MTA built-in voice) follows the text modes: a speaker is always heard within the local range, and in a
-- transmitting mode (global, radio, admin) also by that mode's text audience. The modes whose audiences are joined.
chat.VOICE_REFRESH_MS = 500
-- lang:begin
chat.VOICE_MUTED = "You are muted: nobody hears your voice until the mute ends."
-- lang:end

function chat.voiceModes(mode)
    if mode == chat.MODE.LOCAL or not chat.isMode(mode) then
        return { chat.MODE.LOCAL }
    end
    return { chat.MODE.LOCAL, mode }
end

-- Joins audience lists into one recipient list, each listener once, the speaker left out (no echo).
function chat.voiceRecipients(speaker, lists)
    local seen, out = { [speaker] = true }, {}
    for _, list in ipairs(lists) do
        for _, listener in ipairs(list) do
            if not seen[listener] then
                seen[listener] = true
                out[#out + 1] = listener
            end
        end
    end
    return out
end

-- Three messages within a second each mute the sender for 30 s; a quiet second lowers the streak by one.
-- st = { streak, lastTick } is mutated. Returns true when the mute triggers.
function chat.flood(st, nowMs)
    if nowMs - (st.lastTick or 0) < chat.FLOOD_WINDOW_MS then
        st.streak = (st.streak or 0) + 1
        if st.streak >= chat.FLOOD_STREAK then
            st.streak = 0
            st.lastTick = nowMs
            return true
        end
    elseif (st.streak or 0) > 0 then
        st.streak = st.streak - 1
    end
    st.lastTick = nowMs
    return false
end

-- Upstream TruncateChatMessage: a line over 128 characters continues on a second line, split at a space.
function chat.split(text)
    text = tostring(text or "")
    if #text <= chat.MAX_LINE then
        return text, nil
    end
    local cut = chat.MAX_LINE
    for i = chat.MAX_LINE, chat.MAX_LINE - 40, -1 do
        if text:sub(i, i) == " " then
            cut = i
            break
        end
    end
    return text:sub(1, cut - 1 > 0 and cut - 1 or cut), text:sub(cut + 1)
end

-- The line as everyone sees it. mode 3 (admin) takes the sender's level colour as "#RRGGBB".
function chat.format(mode, name, text, freq, levelColour)
    if mode == chat.MODE.LOCAL then
        return string.format("[Local] %s#FFFFFF: %s", name, text)
    elseif mode == chat.MODE.GLOBAL then
        return string.format("[Global] %s#FFFFFF: %s", name, text)
    elseif mode == chat.MODE.ADMIN then
        return string.format("%s[Admin] %s#FFFFFF: %s", levelColour or "#FFFFFF", name, text)
    elseif mode == "me" then
        return string.format("[Local] %s %s", name, text)
    end
    return string.format("[%.2f] %s#FFFFFF: %s", freq or chat.FREQ_DEFAULT, name, text)
end

-- Radio panel: power "on" means the transmitter is in global or radio mode; "off" is local chat.
-- the radio panel's labels (the client shows them through lang.text)
-- lang:begin
chat.PANEL_LABELS = { "off", "on", "global", "freq" }
-- lang:end

function chat.powerLabel(mode)
    return mode == chat.MODE.LOCAL and "off" or "on"
end

function chat.modeLabel(mode, oldMode)
    if mode == chat.MODE.GLOBAL or (mode == chat.MODE.LOCAL and oldMode == chat.MODE.GLOBAL) then
        return "global"
    end
    return "freq"
end

-- The global/freq toggle only switches between the two transmitting modes.
function chat.toggleMode(mode)
    if mode == chat.MODE.GLOBAL then
        return chat.MODE.RADIO
    elseif mode == chat.MODE.RADIO then
        return chat.MODE.GLOBAL
    end
    return mode
end

-- Power: off remembers which transmitting mode to come back to. Returns newMode, newOldMode.
function chat.togglePower(mode, oldMode)
    if mode == chat.MODE.LOCAL then
        return (oldMode == chat.MODE.GLOBAL) and chat.MODE.GLOBAL or chat.MODE.RADIO, oldMode
    end
    return chat.MODE.LOCAL, mode
end

-- Panel geometry in 640x480 units (core/ui/radio.pwn textdraw positions and text sizes).
chat.PANEL = {
    box = { x = 220, y = 200, w = 200, h = 88 },
    title = { x = 320, y = 200 },
    strip = { x = 320, y = 220 },
    knobL = { x = 220, y = 203, w = 30, h = 30 },
    knobR = { x = 390, y = 203, w = 30, h = 30 },
    mode = { x = 223, y = 251, w = 30, h = 14, cx = 238 },
    freq = { x = 260, y = 251, w = 120, h = 14, cx = 320 },
    power = { x = 387, y = 251, w = 30, h = 14, cx = 402 },
    close = { x = 220, y = 274, w = 200, h = 14, cx = 320 },
}
chat.HOTSPOTS = { "knobL", "knobR", "mode", "freq", "power", "close" }

-- Which hotspot a point (in units) is over, or nil.
function chat.hit(ux, uy)
    for _, name in ipairs(chat.HOTSPOTS) do
        local r = chat.PANEL[name]
        if ux >= r.x and ux <= r.x + r.w and uy >= r.y and uy <= r.y + r.h then
            return name
        end
    end
    return nil
end

-- Join and quit lines (upstream player.pwn OnPlayerConnect / OnPlayerDisconnect). The copyright line stays as
-- upstream asked ("DO NOT REMOVE THIS MESSAGE"); the name is in upstream's connect colour B8B8B8; MTA has no
-- player ids, so "NAME (id) has joined" loses the id.
chat.COPYRIGHT = 'Scavenge and Survive #33CCFF(Copyright (C) 2016 Barnaby "Southclaws" Keene)'

-- { text, r, g, b, toAll } in send order; the MoTD line only when one is set.
function chat.joinLines(name, motd)
    local lines = {
        { text = chat.COPYRIGHT, r = 255, g = 170, b = 0 },
        {
            text = string.format(" >  #B8B8B8%s#FFFFFF has joined", name),
            r = 255,
            g = 255,
            b = 255,
            toAll = true,
            localized = true,
        },
    }
    if type(motd) == "string" and motd ~= "" then
        lines[#lines + 1] = { text = " >  MoTD: #33CCFF" .. motd, r = 255, g = 255, b = 0 }
    end
    return lines
end

-- Info commands (upstream player/commands.pwn) as ui showInfo specs (CEGUI windows: a table, or coloured
-- paragraphs from SA-MP dialog text).

-- GENCOMDHELP lines of upstream commands the port leaves out: /restartinfo (the port has no scheduled restart and
-- saves continuously, so upstream's restart and saving notes do not apply).
chat.DROPPED_HELP = { restartinfo = true }

-- Upstream's /help ends with "coded and owned by Southclaws ... all rights reserved"; the port credits both instead.
-- lang:begin
chat.HELP_FOOTER = "Scavenge and Survive by Southclaws, ported to MTA:SA by VIRUXE."
-- lang:end

-- tr(text): the window's own labels in the reader's language (the server passes lang.textFor for the player)
local function identity(s)
    return s
end

-- The /help window: each "#RRGGBB/command - description" line becomes a row in its colour; upstream's other text
-- (the ownership line) gives way to HELP_FOOTER.
function chat.helpWindow(text, tr)
    tr = tr or identity
    local rows = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local colour, cmd, desc = line:match("^%s*(#%x%x%x%x%x%x)(/%S+)%s+%-%s+(.+)$")
        if cmd and not chat.DROPPED_HELP[cmd:sub(2)] then
            rows[#rows + 1] = { cmd, desc, colour = colour }
        end
    end
    local columns = { tr("Command"), tr("Description") }
    local footer = "#AFAFAF" .. tr(chat.HELP_FOOTER)
    return { title = tr("General Information"), columns = columns, rows = rows, footer = footer }
end

-- /chatinfo: the text as coloured paragraphs.
function chat.textWindow(title, text)
    return { title = title, text = tostring(text or "") }
end

-- /rules: a numbered list of the setting's entries.
function chat.listWindow(title, items, tr)
    tr = tr or identity
    local rows = {}
    for i, item in ipairs(items) do
        rows[#rows + 1] = { tostring(i), item }
    end
    local header = #items == 0 and "#AAAAAA" .. tr("Nothing listed yet.") or nil
    return { title = title, header = header, columns = { "#", title }, rows = rows }
end

-- /admins: every staff account, highest rank first (the query orders them). staff = { { name, rank, colour, online } }
-- with colour "#RRGGBB" of the rank.
function chat.staffWindow(staff, tr)
    tr = tr or identity
    local rows = {}
    for _, s in ipairs(staff) do
        rows[#rows + 1] = { s.name, s.rank, s.online and tr("online") or "", colour = s.colour }
    end
    local header = #staff == 0 and "#AAAAAA" .. tr("No staff yet.") or nil
    local columns = { tr("Name"), tr("Rank"), tr("Status") }
    return { title = tr("Staff"), header = header, columns = columns, rows = rows }
end

-- /credits: the opening line, then one row per contributor.
function chat.creditsWindow(tr)
    tr = tr or identity
    local rows = {}
    for i = 2, #chat.CREDITS do
        local name, what = chat.CREDITS[i]:match("^(.-) %- (.+)$")
        rows[#rows + 1] = { name, what }
    end
    local header = "#FFFF00" .. chat.CREDITS[1]
    local columns = { tr("Contributor"), tr("Contribution") }
    return { title = tr("Credits"), header = header, columns = columns, rows = rows }
end

-- server.rules (upstream settings.ini array): entries separated by "|", blanks dropped.
function chat.listSetting(value)
    local out = {}
    if type(value) ~= "string" then
        return out
    end
    for part in (value .. "|"):gmatch("(.-)|") do
        local item = part:gsub("^%s+", ""):gsub("%s+$", "")
        if item ~= "" then
            out[#out + 1] = item
        end
    end
    return out
end

chat.CREDITS = {
    "Scavenge and Survive was created by Southclaws (www.southcla.ws) and ported to MTA:SA by VIRUXE, with these"
        .. " contributors:",
    "Y_Less - Tons of useful code, libraries and conversations",
    "Viruxe - MTA:SA port, anti-cheat work",
    "Kadaradam - Fishing, Trees and lots of bug fixes",
    "Eidorian - French translation",
    "Hiddos - Better water detection code",
    "YOLO - Bosnian/Croatian/Serbian Translation",
    "JJ - Czech Translation",
    "KingSergio - Russian Translation",
    "Blacky - Romanian Translation",
    "Reza - Indonesian Translation",
    "PrettyDiamond - Spanish Translation",
}

return chat
