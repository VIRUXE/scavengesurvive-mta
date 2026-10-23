-- Pure staff logic: levels, the command registry, duration parsing, player lookup and list rows.
-- No MTA calls at file scope (busted loads it with tests/lua/helpers/mta_mock.lua).
-- Upstream: gamemodes/sss/core/admin/admin.pwn (levels, names, colours, RegisterAdminCommand/acmds).
local staff = {}

staff.MAX_LEVEL = 5
staff.LEVEL_NAMES = { [0] = "Player", "Game Master", "Moderator", "Administrator", "Lead", "Developer" }
staff.LEVEL_COLOURS = {
    [0] = { 255, 255, 255 },
    { 93, 252, 10 },
    { 51, 204, 255 },
    { 102, 0, 255 },
    { 255, 0, 0 },
    { 255, 50, 0 },
}
-- upstream admin.pwn duty skins (male 217, female 211); female skins from character/shared/logic/spawnpoints.lua
staff.DUTY_SKIN_MALE, staff.DUTY_SKIN_FEMALE = 217, 211
staff.FEMALE_SKINS = { [192] = true, [93] = true, [233] = true, [193] = true, [90] = true, [191] = true, [131] = true }

function staff.levelName(level)
    return staff.LEVEL_NAMES[level] or staff.LEVEL_NAMES[0]
end

function staff.levelColour(level)
    return staff.LEVEL_COLOURS[level] or staff.LEVEL_COLOURS[0]
end

function staff.dutySkin(currentSkin)
    return staff.FEMALE_SKINS[currentSkin] and staff.DUTY_SKIN_FEMALE or staff.DUTY_SKIN_MALE
end

-- Command names that are also MTA server console commands (kick, ban, restart) or that the stock Default ACL
-- denies to every player as command.<name> (mute, unmute): typed in chat they reach MTA's hardcoded handler
-- first and never a script handler, so the client forwards them through staffCommandIssued and the server
-- cancels onPlayerCommand for them (server/main.lua, client/main.lua).
staff.CHAT_BRIDGED = { kick = true, ban = true, mute = true, unmute = true, restart = true }

-- A level may use a command of its own level or below.
function staff.canUse(level, commandLevel)
    return (level or 0) >= (commandLevel or 0)
end

-- Upstream rule for acting on another player: a staff member may only touch someone of a lower level
-- (or themselves). Equal or higher levels are refused ("return 3" in level1.pwn).
function staff.outranks(actorLevel, targetLevel, isSelf)
    if isSelf then
        return true
    end
    return (actorLevel or 0) > (targetLevel or 0)
end

-- Command registry: { name = { name, level, usage, help, fn } } plus insertion order for /acmds.
function staff.newRegistry()
    return { byName = {}, order = {} }
end

function staff.register(reg, def)
    assert(def.name and def.level and def.fn, "staff.register: name, level and fn are required")
    assert(def.level >= 0 and def.level <= staff.MAX_LEVEL, "staff.register: bad level for " .. def.name)
    reg.byName[def.name] = def
    reg.order[#reg.order + 1] = def.name
    return def
end

-- Commands visible to a level, grouped from the highest level the caller holds down to 1 (upstream /acmds
-- order), each group sorted by name. Level-0 commands (/report) are left out: everyone has them.
function staff.commandsFor(reg, level)
    local groups = {}
    for lvl = math.min(level or 0, staff.MAX_LEVEL), 1, -1 do
        local names = {}
        for _, name in ipairs(reg.order) do
            local def = reg.byName[name]
            if def.level == lvl and not def.hidden then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        if #names > 0 then
            local cmds = {}
            for _, name in ipairs(names) do
                local def = reg.byName[name]
                cmds[#cmds + 1] = { name = name, usage = def.usage or ("/" .. name), help = def.help or "" }
            end
            groups[#groups + 1] = { level = lvl, name = staff.levelName(lvl), commands = cmds }
        end
    end
    return groups
end

-- Duration strings: "forever"/"perm"/"permanent"/"0"/"-1" -> 0 (no expiry); "<n>" seconds; "<n>s|m|h|d|w|mo".
-- Returns whole seconds, or nil when the text is not a duration.
local UNITS = { s = 1, m = 60, h = 3600, d = 86400, w = 604800, mo = 2592000 }
function staff.parseDuration(text)
    if type(text) ~= "string" then
        return nil
    end
    local s = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if s == "forever" or s == "perm" or s == "permanent" or s == "0" or s == "-1" then
        return 0
    end
    local n, unit = s:match("^(%d+%.?%d*)%s*([a-z]*)$")
    if not n then
        return nil
    end
    local mult
    if unit == "" then
        mult = 1
    else
        -- accept the full words too: seconds, minutes, hours, days, weeks, months
        unit = unit:gsub("s$", "")
        local short = ({ second = "s", minute = "m", hour = "h", day = "d", week = "w", month = "mo" })[unit] or unit
        mult = UNITS[short]
    end
    if not mult then
        return nil
    end
    local secs = math.floor(tonumber(n) * mult + 0.5)
    if secs <= 0 then
        return nil
    end
    return secs
end

function staff.formatDuration(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return "forever"
    end
    local units = { { 86400, "d" }, { 3600, "h" }, { 60, "m" } }
    for _, u in ipairs(units) do
        if seconds >= u[1] then
            local whole = math.floor(seconds / u[1])
            local rest = seconds - whole * u[1]
            if rest == 0 then
                return whole .. u[2]
            end
            return whole .. u[2] .. " " .. staff.formatDuration(rest)
        end
    end
    return seconds .. "s"
end

-- Finds one player by name: exact match (case-insensitive) first, then a unique prefix, then a unique
-- substring. players = { { name = "Bob", player = <element> }, ... }. Returns entry | nil, code.
function staff.findPlayer(query, players)
    if type(query) ~= "string" or query == "" then
        return nil, "NO_QUERY"
    end
    local q = query:lower()
    local prefix, sub = {}, {}
    for _, e in ipairs(players) do
        local n = e.name:lower()
        if n == q then
            return e, "OK"
        end
        if n:sub(1, #q) == q then
            prefix[#prefix + 1] = e
        elseif n:find(q, 1, true) then
            sub[#sub + 1] = e
        end
    end
    if #prefix == 1 then
        return prefix[1], "OK"
    end
    if #prefix > 1 then
        return nil, "AMBIGUOUS"
    end
    if #sub == 1 then
        return sub[1], "OK"
    end
    if #sub > 1 then
        return nil, "AMBIGUOUS"
    end
    return nil, "NOT_FOUND"
end

-- Splits a command line into words; the tail from index `from` is re-joined as free text.
function staff.words(args)
    local out = {}
    for w in tostring(args or ""):gmatch("%S+") do
        out[#out + 1] = w
    end
    return out
end

function staff.tail(words, from)
    if #words < from then
        return nil
    end
    return table.concat(words, " ", from)
end

-- /report modes (upstream report-cmds.pwn): a name, the nearest player, or whoever last killed you.
staff.REPORT_TYPES = { name = "PLY NAME", online = "PLY ID", near = "PLY CLOSE", killer = "PLY KILL" }

-- Rows for the reports dialog: upstream colours banned names red and unread yellow; the dx list has no
-- colour codes, so the row carries a marker instead.
function staff.reportRows(reports, isBanned)
    local rows = {}
    for _, r in ipairs(reports) do
        local marker = ""
        if isBanned and isBanned(r.name) then
            marker = "[banned] "
        elseif not r.read_at or r.read_at == false then
            marker = "[new] "
        end
        rows[#rows + 1] = {
            id = r.id,
            label = string.format("%s%s (%s)", marker, r.name, r.type or "?"),
            actions = {
                { id = "view", label = "View" },
                { id = "goto", label = "Go to position" },
                { id = "delete", label = "Delete" },
                { id = "deleteall", label = "Delete all of this player" },
                { id = "unread", label = "Mark unread" },
            },
        }
    end
    if #rows == 0 then
        rows[1] = { id = "none", label = "No reports", empty = true }
    end
    return rows
end

function staff.banRows(bans)
    local rows = {}
    for _, b in ipairs(bans) do
        local until_ = (b.expires_at and b.expires_at ~= false) and ("until " .. tostring(b.expires_at)) or "forever"
        rows[#rows + 1] = {
            id = b.name,
            label = string.format("%s - %s (%s, by %s)", b.name, b.reason or "", until_, b.by_name or "Server"),
            actions = { { id = "unban", label = "Unban" } },
        }
    end
    if #rows == 0 then
        rows[1] = { id = "none", label = "No active bans", empty = true }
    end
    return rows
end

-- Remaining mute time in seconds (nil when not muted, 0 when permanent).
function staff.muteRemaining(mute, nowTick)
    if not mute then
        return nil
    end
    if not mute.untilTick then
        return 0
    end
    return math.max(0, math.ceil((mute.untilTick - nowTick) / 1000))
end

-- /setadmin: a lead may hand out levels below their own; a developer may set any level up to 5.
function staff.canSetLevel(actorLevel, newLevel, targetLevel, isSelf)
    if isSelf then
        return false, "SELF"
    end
    if type(newLevel) ~= "number" or newLevel < 0 or newLevel > staff.MAX_LEVEL or newLevel % 1 ~= 0 then
        return false, "BAD_LEVEL"
    end
    local ceiling = actorLevel >= staff.MAX_LEVEL and staff.MAX_LEVEL or actorLevel - 1
    if newLevel > ceiling or (targetLevel or 0) > ceiling then
        return false, "TOO_HIGH"
    end
    return true, "OK"
end

-- The /kick rule from level1.pwn: unless the actor holds the highest staff level online, the kick becomes a
-- request to that person. highest = the highest level among online staff.
function staff.kickNeedsApproval(actorLevel, highestOnline)
    return (highestOnline or 0) > (actorLevel or 0)
end

return staff
