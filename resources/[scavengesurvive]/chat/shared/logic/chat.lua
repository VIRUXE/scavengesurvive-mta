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
        { text = string.format(" >  #B8B8B8%s#FFFFFF has joined", name), r = 255, g = 255, b = 255, toAll = true },
    }
    if type(motd) == "string" and motd ~= "" then
        lines[#lines + 1] = { text = " >  MoTD: #33CCFF" .. motd, r = 255, g = 255, b = 0 }
    end
    return lines
end

-- MTA quit types to upstream's two reasons; kicks and bans print nothing (upstream reason 2 had no line).
local QUIT_LINES = {
    Quit = " >  %s left the server.",
    ["Timed out"] = " >  %s lost connection.",
    ["Bad Connection"] = " >  %s lost connection.",
    Unknown = " >  %s lost connection.",
}
function chat.quitLine(name, quitType)
    local fmt = QUIT_LINES[quitType]
    return fmt and string.format(fmt, name) or nil
end

return chat
