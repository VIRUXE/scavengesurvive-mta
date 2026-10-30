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
-- upstream admin.pwn duty skins (male 217, female 211); the gender of a skin comes from items (isFemaleSkin,
-- items/shared/logic/skins.lua covers every ped model)
staff.DUTY_SKIN_MALE, staff.DUTY_SKIN_FEMALE = 217, 211

function staff.levelName(level)
    return staff.LEVEL_NAMES[level] or staff.LEVEL_NAMES[0]
end

function staff.levelColour(level)
    return staff.LEVEL_COLOURS[level] or staff.LEVEL_COLOURS[0]
end

function staff.dutySkin(female)
    return female and staff.DUTY_SKIN_FEMALE or staff.DUTY_SKIN_MALE
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

-- Command registry: { name = { name, level, usage, help, fn [, aliases] } } plus insertion order for /acmds. An
-- alias (/tp for /gotopos) runs the same command and is found by name, but only the command itself is listed.
function staff.newRegistry()
    return { byName = {}, order = {} }
end

function staff.register(reg, def)
    assert(def.name and def.level and def.fn, "staff.register: name, level and fn are required")
    assert(def.level >= 0 and def.level <= staff.MAX_LEVEL, "staff.register: bad level for " .. def.name)
    assert(not reg.byName[def.name], "staff.register: " .. def.name .. " is taken")
    reg.byName[def.name] = def
    reg.order[#reg.order + 1] = def.name
    for _, alias in ipairs(def.aliases or {}) do
        assert(not reg.byName[alias], "staff.register: " .. alias .. " is taken")
        reg.byName[alias] = def
    end
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

-- Text typed into an input dialog without its surrounding spaces ("" when blank).
function staff.trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- /aliases match modes (upstream i/p/h/a): the gpci hash becomes the MTA serial (h kept as an alias of s) and
-- "same password" is dropped because bcrypt hashes are salted. No mode matches both columns.
staff.ALIAS_MODES = { a = "both", i = "ip", s = "serial", h = "serial" }

function staff.aliasMode(arg)
    if arg == nil then
        return "both"
    end
    return staff.ALIAS_MODES[tostring(arg):lower()]
end

-- Post-login alias report (upstream aliases.pwn CheckForExtraAccounts): rows are { name, lvl, banned } for the
-- other names seen from the player's IP or serial. Staff at or above the highest alias's level (at least 1) read
-- "Aliases: (n) a, b, ..." (six names at most, as upstream); a banned alias warns level 1+ in red and, with no staff
-- online, kicks the player instead. Upstream only looked for bans with two or more aliases; any count does here.
staff.ALIAS_REPORT_NAMES = 6
staff.ALIAS_BANNED_KICK = "One of your previously used accounts is banned."

function staff.aliasReport(rows, staffOnline)
    if #rows == 0 then
        return nil
    end
    local names, level, banned = {}, 1, false
    for i, r in ipairs(rows) do
        if i <= staff.ALIAS_REPORT_NAMES then
            names[#names + 1] = r.name
        end
        level = math.max(level, tonumber(r.lvl) or 0)
        banned = banned or tonumber(r.banned) == 1
    end
    return {
        count = #rows,
        list = table.concat(names, ", "),
        level = level,
        banned = banned,
        kick = banned and staffOnline == 0,
    }
end

-- getPlayerSerial is 32 upper-case hex digits; returns that form of `text`, or nil when it is not a serial.
function staff.normaliseSerial(text)
    local s = tostring(text or ""):upper()
    if #s == 32 and not s:find("[^0-9A-F]") then
        return s
    end
    return nil
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

-- /field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ> (args = the words after "add"): the field to insert, or
-- nil and one of ARGS, NAME, NUMBER, ZBAND. Points are the polygon's corners in order around its boundary.
function staff.parseField(args)
    if #args ~= 11 then
        return nil, "ARGS"
    end
    local name = args[1]
    if not name:match("^[%w_%-]+$") or #name > 64 then
        return nil, "NAME"
    end
    local nums = {}
    for i = 2, 11 do
        nums[i - 1] = tonumber(args[i])
        if not nums[i - 1] then
            return nil, "NUMBER"
        end
    end
    if nums[9] >= nums[10] then
        return nil, "ZBAND"
    end
    local points = {}
    for i = 1, 8, 2 do
        points[#points + 1] = { nums[i], nums[i + 1] }
    end
    return { name = name, points = points, minZ = nums[9], maxZ = nums[10] }
end

-- One line for the staff_actions details column: name, corners and Z band.
function staff.fieldSummary(field)
    local corners = {}
    for i, p in ipairs(field.points) do
        corners[i] = string.format("%.1f,%.1f", p[1], p[2])
    end
    return string.format("%s [%s] z %.1f..%.1f", field.name, table.concat(corners, " "), field.minZ, field.maxZ)
end

-- Staff panel forms: the argument fields of a usage line ("/ban <player|name> [<duration|forever> <reason>]").
-- <...> is a text field, or a player picker when its first alternative is "player" (the other alternatives,
-- "name" aside, become extra picker items); a bare a|b|c is a choice; [...] marks what it holds optional; ...
-- is optional free text. A field is { name, kind = "player" | "choice" | "text", optional, options | nil }, in
-- usage order.
local function addUsageField(fields, content, optional, bare)
    if content == "..." then
        fields[#fields + 1] = { name = "arguments", kind = "text", optional = true }
        return
    end
    local alts = {}
    for alt in content:gmatch("[^|]+") do
        alts[#alts + 1] = alt
    end
    if alts[1] == "player" then
        local options = {}
        for i = 2, #alts do
            if alts[i] ~= "name" then
                options[#options + 1] = alts[i]
            end
        end
        fields[#fields + 1] = { name = content, kind = "player", optional = optional, options = options }
    elseif bare and #alts > 1 then
        fields[#fields + 1] = { name = content, kind = "choice", optional = optional, options = alts }
    elseif bare and not optional then
        return -- a literal word in the usage, not an argument
    else
        fields[#fields + 1] = { name = content, kind = "text", optional = optional }
    end
end

local function parseUsage(seg, optional, fields)
    local i = 1
    while i <= #seg do
        local ch = seg:sub(i, i)
        if ch == "[" then
            local depth, j = 1, i + 1
            while j <= #seg and depth > 0 do
                local c = seg:sub(j, j)
                if c == "[" then
                    depth = depth + 1
                elseif c == "]" then
                    depth = depth - 1
                end
                j = j + 1
            end
            local inner = seg:sub(i + 1, j - 2)
            if inner:find("<", 1, true) then
                parseUsage(inner, true, fields)
            else
                addUsageField(fields, inner, true, not inner:find("%s"))
            end
            i = j
        elseif ch == "<" then
            local close = seg:find(">", i, true) or #seg + 1
            addUsageField(fields, seg:sub(i + 1, close - 1), optional, false)
            i = close + 1
        elseif ch:match("%s") then
            i = i + 1
        else
            local j = seg:find("[%s%[<]", i) or #seg + 1
            addUsageField(fields, seg:sub(i, j - 1), optional, true)
            i = j
        end
    end
end

function staff.usageFields(usage)
    local fields = {}
    local rest = tostring(usage or ""):gsub("^%s*/%S*%s*", "")
    parseUsage(rest, false, fields)
    return fields
end

-- The argument text for a command from the form's values (one per field, in order): the filled fields joined
-- by spaces. nil and a message when a required field is blank or a blank optional field is followed by a
-- filled one (arguments are positional).
function staff.commandArgs(fields, values)
    local parts, blank = {}, nil
    for i, f in ipairs(fields) do
        local v = staff.trim(values[i])
        if v == "" then
            if not f.optional then
                return nil, "Fill in " .. f.name .. "."
            end
            blank = blank or f.name
        elseif blank then
            return nil, "Fill in " .. blank .. " before " .. f.name .. "."
        else
            parts[#parts + 1] = v
        end
    end
    return table.concat(parts, " ")
end

-- The staff panel's command list for a level: commandsFor's groups flattened, each command with its fields.
function staff.panelCommands(reg, level)
    local out = {}
    for _, group in ipairs(staff.commandsFor(reg, level)) do
        for _, c in ipairs(group.commands) do
            out[#out + 1] = {
                name = c.name,
                level = group.level,
                levelName = group.name,
                usage = c.usage,
                help = c.help,
                fields = staff.usageFields(c.usage),
            }
        end
    end
    return out
end

-- Bug reports (upstream admin/bug-report.pwn). /issues lists the oldest 32 as "name: reason", the reason cut to the
-- 31 characters upstream's list buffer held and marked "[...]" when it ran that long.
staff.BUG_REASON_MAX = 128
staff.BUG_LIST_MAX = 32
staff.BUG_DELETE_LEVEL = 2 -- upstream GetPlayerAdminLevel(playerid) > 1

function staff.bugRows(bugs)
    local rows = {}
    for _, b in ipairs(bugs) do
        local reason = tostring(b.reason or "")
        local label = tostring(b.name or "") .. ": " .. reason:sub(1, 31)
        if #reason >= 31 then
            label = label .. "[...]"
        end
        rows[#rows + 1] = { id = b.id, label = label }
    end
    return rows
end

-- the report's message box, upstream ShowBugReportInfo's three fields
function staff.bugText(b)
    return string.format("Reporter:\n    %s\n\nReason:\n    %s\n\nDate:\n    %s", b.name, b.reason, b.created)
end

return staff
