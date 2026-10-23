-- Attachment editor, server side: the /attachedit command, the rcon export dev's "attach" verb forwards to, and the
-- output file. The preview itself lives on the player's client (items' setAttachPreview); the server only relays,
-- caches what each client last reported for a slot, and appends saved rows to attachedit-out.lua.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local logic
do
    local f = fileOpen("shared/logic/attachedit.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    logic = assert(loadstring(src, "=attachedit/logic.lua"))()
end

local OUT = "attachedit-out.lua"
local reports = {} -- player -> slot -> { cfg = config table or false, tick }

local function say(p, fmt, ...)
    local msg = "[attachedit] " .. string.format(fmt, ...)
    if isElement(p) and getElementType(p) == "player" then
        outputChatBox(msg, p, 120, 200, 255)
    else
        outputServerLog(msg)
    end
end

-- same gate as the dev resource: its public *dev.open setting, or any admin level
local function allowed(p)
    if getElementType(p) == "console" then
        return true
    end
    if tostring(get("dev.open")) == "true" then
        return true
    end
    local ok, level = pcall(function()
        return exports.auth:getAdminLevel(p)
    end)
    return ok and (tonumber(level) or 0) > 0
end

local function slotList()
    return table.concat(logic.SLOTS, "|")
end

local function describeConfig(slot, cfg)
    if not cfg then
        return string.format("%s: nothing attached (empty slot, or a weapon GTA draws itself)", slot)
    end
    local values = logic.join(cfg.offsets, cfg.scale)
    return string.format(
        "%s: %s skin=%s bone=%s preview=%s  %s",
        slot,
        tostring(cfg.uname),
        tostring(cfg.skin),
        tostring(cfg.bone),
        cfg.preview and "on" or "off",
        logic.formatEntry(cfg.uname, cfg.skin, slot, values)
    )
end

local function appendLine(line)
    local f = fileExists(OUT) and fileOpen(OUT) or fileCreate(OUT)
    if not f then
        return false
    end
    fileSetPos(f, fileGetSize(f))
    fileWrite(f, line .. "\n")
    fileClose(f)
    return true
end

addCommandHandler("attachedit", function(p, _, slot)
    if getElementType(p) ~= "player" then
        return say(p, "/attachedit is player-only")
    end
    if not allowed(p) then
        return say(p, "not allowed")
    end
    if not logic.isSlot(slot) then
        return say(p, "usage: /attachedit <%s>", slotList())
    end
    triggerClientEvent(p, "attachEditToggled", p, slot)
end)

-- values: the nine numbers; uname and skin come from the client's view of its own attachment
net.handler("attachEditSaveRequested", function(player, slot, uname, skin, values)
    values = logic.checkValues(values)
    if not allowed(player) or not logic.isSlot(slot) or type(uname) ~= "string" or not values then
        return
    end
    local entry = logic.formatEntry(uname, tonumber(skin) or skin, slot, values)
    local t = getRealTime()
    local stamp = string.format(
        "%04d-%02d-%02d %02d:%02d:%02d",
        t.year + 1900,
        t.month + 1,
        t.monthday,
        t.hour,
        t.minute,
        t.second
    )
    outputServerLog(string.format("[attachedit] %s saved %s", getPlayerName(player), entry))
    local line = string.format("%s %s by %s", entry, stamp, getPlayerName(player))
    if appendLine(line) then
        say(player, "appended to attachedit/%s", OUT)
    else
        say(player, "could not write attachedit/%s", OUT)
    end
end, { rate = 5 })

-- cfg: items' getAttachConfig(slot) on that client, or false when the slot shows nothing
net.handler("attachEditConfigReported", function(player, slot, cfg)
    if not logic.isSlot(slot) then
        return
    end
    if type(cfg) == "table" then
        local o, s = cfg.offsets, cfg.scale
        local values = type(o) == "table" and type(s) == "table" and logic.checkValues(logic.join(o, s))
        if not values then
            return
        end
        cfg = {
            uname = tostring(cfg.uname),
            skin = tonumber(cfg.skin),
            bone = tonumber(cfg.bone),
            preview = cfg.preview == true,
            offsets = { unpack(values, 1, 6) },
            scale = { values[7], values[8], values[9] },
        }
    else
        cfg = false
    end
    reports[player] = reports[player] or {}
    reports[player][slot] = { cfg = cfg, tick = getTickCount() }
end, { rate = 30 })

addEventHandler("onPlayerQuit", root, function()
    reports[source] = nil
end)

-- dev's rcon "attach <player> <slot> ..." lands here with the words after the player name.
-- Returns ok, { output lines }. "get" cannot wait for the client inside one HTTP call, so it prints the last
-- report the client sent for that slot (every set/off and every editor change sends one) and asks for a new one.
function rcon(p, words)
    if not isElement(p) or getElementType(p) ~= "player" then
        return false, { "no such player" }
    end
    words = type(words) == "table" and words or {}
    local slot = words[1]
    if not logic.isSlot(slot) then
        return false, { string.format("usage: attach <player> <%s> off|get|x y z rx ry rz [sx sy sz]", slotList()) }
    end
    local args = {}
    for i = 2, #words do
        args[#args + 1] = words[i]
    end
    local cmd, err = logic.parseArgs(args)
    if not cmd then
        return false, { err }
    end
    local name = getPlayerName(p)
    if cmd.action == "get" then
        local r = reports[p] and reports[p][slot]
        triggerClientEvent(p, "attachEditConfigRequested", p, slot)
        if not r then
            return true,
                { string.format("%s %s: no report yet; asked the client, run get again in a moment", name, slot) }
        end
        return true,
            {
                string.format("%s %s", name, describeConfig(slot, r.cfg)),
                string.format("(reported %.1f s ago; a fresh report was requested)", (getTickCount() - r.tick) / 1000),
            }
    elseif cmd.action == "off" then
        triggerClientEvent(p, "attachEditPreviewChanged", p, slot, false)
        return true, { string.format("%s %s: preview cleared", name, slot) }
    end
    triggerClientEvent(p, "attachEditPreviewChanged", p, slot, cmd.offsets, cmd.scale)
    return true, { string.format("%s %s: preview %s", name, slot, logic.formatRow(logic.join(cmd.offsets, cmd.scale))) }
end
