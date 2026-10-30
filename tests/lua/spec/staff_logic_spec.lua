local staff = dofile("resources/[scavengesurvive]/staff/shared/logic/staff.lua")

describe("staff levels and permissions", function()
    it("names and colours the five upstream levels", function()
        assert.equals("Game Master", staff.levelName(1))
        assert.equals("Developer", staff.levelName(5))
        assert.equals("Player", staff.levelName(0))
        assert.equals("Player", staff.levelName(9))
        assert.same({ 51, 204, 255 }, staff.levelColour(2))
    end)
    it("gates commands by level and lets staff act only on lower levels or themselves", function()
        assert.is_true(staff.canUse(2, 2))
        assert.is_false(staff.canUse(1, 2))
        assert.is_true(staff.outranks(2, 1, false))
        assert.is_false(staff.outranks(2, 2, false))
        assert.is_true(staff.outranks(2, 2, true))
        assert.is_false(staff.outranks(0, 0, false))
    end)
    it("picks the duty skin from the character's gender", function()
        assert.equals(217, staff.dutySkin(false))
        assert.equals(211, staff.dutySkin(true))
    end)
    it("limits /setadmin to levels below the actor, developers excepted", function()
        assert.same({ true, "OK" }, { staff.canSetLevel(4, 3, 0, false) })
        assert.same({ false, "TOO_HIGH" }, { staff.canSetLevel(4, 4, 0, false) })
        assert.same({ false, "TOO_HIGH" }, { staff.canSetLevel(4, 1, 4, false) }) -- demoting an equal
        assert.same({ true, "OK" }, { staff.canSetLevel(5, 5, 5, false) })
        assert.same({ false, "SELF" }, { staff.canSetLevel(5, 1, 5, true) })
        assert.same({ false, "BAD_LEVEL" }, { staff.canSetLevel(5, 6, 0, false) })
        assert.same({ false, "BAD_LEVEL" }, { staff.canSetLevel(5, 1.5, 0, false) })
    end)
    it("turns a kick into a request when higher staff are online", function()
        assert.is_true(staff.kickNeedsApproval(1, 3))
        assert.is_false(staff.kickNeedsApproval(3, 3))
        assert.is_false(staff.kickNeedsApproval(2, 0))
    end)
end)

describe("staff command registry", function()
    it("lists commands grouped from the caller's level down, sorted by name", function()
        local reg = staff.newRegistry()
        local noop = function() end
        staff.register(reg, { name = "mute", level = 1, fn = noop, usage = "/mute <p>", help = "Mute" })
        staff.register(reg, { name = "ban", level = 2, fn = noop })
        staff.register(reg, { name = "kick", level = 1, fn = noop })
        staff.register(reg, { name = "report", level = 0, fn = noop })
        staff.register(reg, { name = "secret", level = 2, fn = noop, hidden = true })
        local groups = staff.commandsFor(reg, 2)
        assert.equals(2, #groups)
        assert.equals(2, groups[1].level)
        assert.same({ "ban" }, { groups[1].commands[1].name })
        assert.same({ "kick", "mute" }, { groups[2].commands[1].name, groups[2].commands[2].name })
        assert.equals("/mute <p>", groups[2].commands[2].usage)
        assert.equals("/kick", groups[2].commands[1].usage)
        assert.equals(1, #staff.commandsFor(reg, 1))
        assert.equals(0, #staff.commandsFor(reg, 0))
    end)
    it("rejects registrations without a level or outside 0-5", function()
        local reg = staff.newRegistry()
        assert.has_error(function()
            staff.register(reg, { name = "x", fn = function() end })
        end)
        assert.has_error(function()
            staff.register(reg, { name = "x", level = 6, fn = function() end })
        end)
    end)
    it("finds a command by its alias but lists it once, under its own name (/tp for /gotopos)", function()
        local reg = staff.newRegistry()
        local def = staff.register(reg, { name = "gotopos", aliases = { "tp" }, level = 2, fn = function() end })
        assert.equals(def, reg.byName.tp)
        assert.same({ "gotopos" }, reg.order)
        local cmds = staff.commandsFor(reg, 2)[1].commands
        assert.equals(1, #cmds)
        assert.equals("gotopos", cmds[1].name)
        assert.has_error(function()
            staff.register(reg, { name = "tp", level = 2, fn = function() end })
        end)
    end)
end)

describe("staff durations", function()
    it("parses seconds, units, words and forever", function()
        assert.equals(90, staff.parseDuration("90"))
        assert.equals(600, staff.parseDuration("10m"))
        assert.equals(7200, staff.parseDuration("2h"))
        assert.equals(259200, staff.parseDuration("3d"))
        assert.equals(1209600, staff.parseDuration("2 weeks"))
        assert.equals(2592000, staff.parseDuration("1mo"))
        assert.equals(5184000, staff.parseDuration("2 months"))
        assert.equals(0, staff.parseDuration("forever"))
        assert.equals(0, staff.parseDuration("-1"))
        assert.equals(0, staff.parseDuration("0"))
        assert.is_nil(staff.parseDuration("soon"))
        assert.is_nil(staff.parseDuration("3x"))
        assert.is_nil(staff.parseDuration(nil))
    end)
    it("formats durations back", function()
        assert.equals("forever", staff.formatDuration(0))
        assert.equals("45s", staff.formatDuration(45))
        assert.equals("10m", staff.formatDuration(600))
        assert.equals("1d 2h 30m", staff.formatDuration(86400 + 7200 + 1800))
    end)
    it("reports mute remainders", function()
        assert.is_nil(staff.muteRemaining(nil, 0))
        assert.equals(0, staff.muteRemaining({}, 0))
        assert.equals(5, staff.muteRemaining({ untilTick = 15000 }, 10000))
        assert.equals(0, staff.muteRemaining({ untilTick = 1000 }, 10000))
    end)
end)

describe("staff player lookup and arguments", function()
    local players = {
        { name = "Southclaws", player = "p1" },
        { name = "south_bob", player = "p2" },
        { name = "Alice", player = "p3" },
        { name = "malice", player = "p4" },
    }
    it("matches exact, unique prefix and unique substring, case-insensitively", function()
        assert.equals("p1", staff.findPlayer("southclaws", players).player)
        assert.equals("p1", staff.findPlayer("Southc", players).player)
        assert.same({ nil, "AMBIGUOUS" }, { staff.findPlayer("south", players) })
        assert.equals("p3", staff.findPlayer("Alice", players).player) -- exact beats substring in "malice"
        assert.equals("p4", staff.findPlayer("mal", players).player)
        assert.same({ nil, "AMBIGUOUS" }, { staff.findPlayer("lic", players) })
        assert.same({ nil, "NOT_FOUND" }, { staff.findPlayer("zed", players) })
        assert.same({ nil, "NO_QUERY" }, { staff.findPlayer("", players) })
    end)
    it("splits words and re-joins the free-text tail", function()
        local w = staff.words("  Bob  3d  was  cheating badly ")
        assert.same({ "Bob", "3d", "was", "cheating", "badly" }, w)
        assert.equals("was cheating badly", staff.tail(w, 3))
        assert.is_nil(staff.tail(w, 6))
    end)
    it("trims dialog input", function()
        assert.equals("cheating badly", staff.trim("  cheating badly 	"))
        assert.equals("", staff.trim("   "))
        assert.equals("", staff.trim(nil))
    end)
end)

describe("staff list rows", function()
    it("marks banned and unread reports and offers the upstream options", function()
        local rows = staff.reportRows({
            { id = 1, name = "Bob", type = "PLY ID", read_at = false },
            { id = 2, name = "Eve", type = "PLY KILL", read_at = "2026-10-23 10:00:00" },
            { id = 3, name = "Mal", type = "PLY NAME", read_at = false },
        }, function(name)
            return name == "Mal"
        end)
        assert.equals("[new] Bob (PLY ID)", rows[1].label)
        assert.equals("Eve (PLY KILL)", rows[2].label)
        assert.equals("[banned] Mal (PLY NAME)", rows[3].label)
        assert.equals(5, #rows[1].actions)
        assert.equals("view", rows[1].actions[1].id)
        local empty = staff.reportRows({})
        assert.is_true(empty[1].empty)
    end)
    it("formats ban rows with expiry and author", function()
        local rows = staff.banRows({
            { name = "Bob", reason = "cheats", expires_at = "2026-11-01 10:00", by_name = "Mod" },
            { name = "Eve", reason = "", expires_at = false, by_name = "Server" },
        })
        assert.equals("Bob - cheats (until 2026-11-01 10:00, by Mod)", rows[1].label)
        assert.equals("Eve -  (forever, by Server)", rows[2].label)
        assert.equals("unban", rows[1].actions[1].id)
    end)
end)

describe("staff chat-bridged commands", function()
    it("lists exactly the names MTA's console owns or the stock Default ACL denies to players", function()
        local names = {}
        for name in pairs(staff.CHAT_BRIDGED) do
            names[#names + 1] = name
        end
        table.sort(names)
        assert.same({ "ban", "kick", "mute", "restart", "unmute" }, names)
    end)
end)

describe("staff alias modes and serials", function()
    it("defaults /aliases to both columns and maps i, s, h and a case-insensitively", function()
        assert.equals("both", staff.aliasMode(nil))
        assert.equals("both", staff.aliasMode("a"))
        assert.equals("ip", staff.aliasMode("i"))
        assert.equals("ip", staff.aliasMode("I"))
        assert.equals("serial", staff.aliasMode("s"))
        assert.equals("serial", staff.aliasMode("H"))
    end)
    it("rejects the dropped password mode and anything else", function()
        assert.is_nil(staff.aliasMode("p"))
        assert.is_nil(staff.aliasMode("x"))
        assert.is_nil(staff.aliasMode("ip"))
        assert.is_nil(staff.aliasMode(""))
    end)
    it("upper-cases a 32-hex-digit serial and rejects anything else", function()
        local serial = "0123456789ABCDEF0123456789ABCDEF"
        assert.equals(serial, staff.normaliseSerial(serial))
        assert.equals(serial, staff.normaliseSerial(serial:lower()))
        assert.is_nil(staff.normaliseSerial(serial:sub(2)))
        assert.is_nil(staff.normaliseSerial(serial .. "0"))
        assert.is_nil(staff.normaliseSerial("0123456789ABCDEF0123456789ABCDEG"))
        assert.is_nil(staff.normaliseSerial(" " .. serial:sub(2)))
        assert.is_nil(staff.normaliseSerial(nil))
        assert.is_nil(staff.normaliseSerial(""))
    end)
end)

describe("staff post-login alias report", function()
    it("reports nothing without aliases", function()
        assert.is_nil(staff.aliasReport({}, 3))
    end)
    it("lists six names, counts all and asks for the highest alias level, at least 1", function()
        local rows = {}
        for i = 1, 8 do
            rows[i] = { name = "n" .. i, lvl = i == 3 and 2 or 0, banned = 0 }
        end
        local r = staff.aliasReport(rows, 1)
        assert.equals(8, r.count)
        assert.equals("n1, n2, n3, n4, n5, n6", r.list)
        assert.equals(2, r.level)
        assert.is_false(r.banned)
        assert.is_false(r.kick)
        assert.equals(1, staff.aliasReport({ { name = "a", lvl = 0, banned = 0 } }, 1).level)
    end)
    it("warns on a single banned alias and kicks only with no staff online", function()
        local rows = { { name = "evader", lvl = "0", banned = "1" } }
        local r = staff.aliasReport(rows, 1)
        assert.is_true(r.banned)
        assert.is_false(r.kick)
        assert.is_true(staff.aliasReport(rows, 0).kick)
    end)
end)

describe("detection field arguments", function()
    local words = { "smoke", "995", "995", "1005", "995", "1005", "1005", "995", "1005", "0", "20" }
    it("parses /field add into a named four-point polygon with a Z band", function()
        local field, err = staff.parseField(words)
        assert.is_nil(err)
        assert.same({
            name = "smoke",
            points = { { 995, 995 }, { 1005, 995 }, { 1005, 1005 }, { 995, 1005 } },
            minZ = 0,
            maxZ = 20,
        }, field)
        assert.equals(
            "smoke [995.0,995.0 1005.0,995.0 1005.0,1005.0 995.0,1005.0] z 0.0..20.0",
            staff.fieldSummary(field)
        )
    end)
    it("names the first problem with the arguments", function()
        assert.same({ nil, "ARGS" }, { staff.parseField({ "smoke", "1", "2" }) })
        local bad = { unpack(words) }
        bad[1] = "no spaces!"
        assert.same({ nil, "NAME" }, { staff.parseField(bad) })
        bad = { unpack(words) }
        bad[5] = "east"
        assert.same({ nil, "NUMBER" }, { staff.parseField(bad) })
        bad = { unpack(words) }
        bad[10], bad[11] = "20", "20"
        assert.same({ nil, "ZBAND" }, { staff.parseField(bad) })
    end)
end)

describe("staff panel forms", function()
    local function kinds(usage)
        local out = {}
        for _, f in ipairs(staff.usageFields(usage)) do
            out[#out + 1] = f.kind .. ":" .. f.name .. (f.optional and "?" or "")
        end
        return out
    end
    it("reads text, player and choice fields from a usage line", function()
        assert.same(
            { "player:player|name", "text:duration|forever?", "text:reason?" },
            kinds("/ban <player|name> [<duration|forever> <reason>]")
        )
        assert.same(
            { "choice:add|remove|?|list|on|off|auto", "text:name?" },
            kinds("/whitelist add|remove|?|list|on|off|auto [name]")
        )
        assert.same({ "text:name", "choice:i|s?" }, kinds("/aliases <name> [i|s]"))
        assert.same({ "text:skill", "text:0-1", "player:player?" }, kinds("/setskill <skill> <0-1> [player]"))
        assert.same({ "text:type 1-5?" }, kinds("/sc [type 1-5]"))
        assert.same({}, kinds("/duty"))
    end)
    it("offers the literal alternatives of a player field as picker items, 'name' aside", function()
        local spec = staff.usageFields("/spec <player|next|prev|off>")[1]
        assert.same({ "next", "prev", "off" }, spec.options)
        assert.same({}, staff.usageFields("/ip <player|name>")[1].options)
        local field = staff.usageFields("/field add|list|log|remove ...")
        assert.same({ "add", "list", "log", "remove" }, field[1].options)
        assert.same({ name = "arguments", kind = "text", optional = true }, field[2])
        local idlekick = staff.usageFields("/idlekick [on|off|<seconds>]")[1]
        assert.is_true(idlekick.optional)
        assert.same({ "on", "off" }, idlekick.options)
    end)
    it("joins the filled fields in order and refuses gaps", function()
        local fields = staff.usageFields("/ban <player|name> [<duration|forever> <reason>]")
        assert.equals("Bob", staff.commandArgs(fields, { " Bob ", "", "" }))
        assert.equals("Bob 1h spam and more", staff.commandArgs(fields, { "Bob", "1h", "spam and more" }))
        assert.same({ nil, "Fill in player|name." }, { staff.commandArgs(fields, { "", "", "" }) })
        assert.same(
            { nil, "Fill in duration|forever before reason." },
            { staff.commandArgs(fields, { "Bob", "", "x" }) }
        )
        assert.equals("", staff.commandArgs({}, {}))
    end)
    it("flattens the level groups for the panel with each command's fields", function()
        local reg = staff.newRegistry()
        local fn = function() end
        staff.register(reg, { name = "goto", level = 2, usage = "/goto <player>", help = "tp", fn = fn })
        staff.register(reg, { name = "a", level = 1, usage = "/a <message>", help = "staff chat", fn = fn })
        staff.register(reg, { name = "players", level = 4, usage = "/players", fn = fn })
        local cmds = staff.panelCommands(reg, 2)
        assert.same({ "goto", "a" }, { cmds[1].name, cmds[2].name })
        assert.equals("Moderator", cmds[1].levelName)
        assert.equals("player", cmds[1].fields[1].kind)
        assert.same({}, staff.panelCommands(reg, 0))
    end)
end)

describe("bug reports", function()
    it("lists a report as name and reason, cut where upstream's 32-byte buffer ended", function()
        local short = { id = 1, name = "Ann", reason = "door stuck" }
        local long = { id = 2, name = "Bo", reason = string.rep("x", 31) .. "tail" }
        local rows = staff.bugRows({ short, long })
        assert.same({ id = 1, label = "Ann: door stuck" }, rows[1])
        assert.equals("Bo: " .. string.rep("x", 31) .. "[...]", rows[2].label)
    end)
    it("shows reporter, reason and date", function()
        local text = staff.bugText({ name = "Ann", reason = "door stuck", created = "2026-10-30 21:00" })
        assert.equals("Reporter:\n    Ann\n\nReason:\n    door stuck\n\nDate:\n    2026-10-30 21:00", text)
    end)
end)
