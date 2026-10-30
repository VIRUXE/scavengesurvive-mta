-- Tests for the world puzzles (world/shared/logic/puzzles.lua, upstream world/puzzles/mtchill.pwn, ranch.pwn and
-- codehunt.pwn) on the buttons.lua registry, and their generated data (world/data/puzzles.lua).
local buttons = dofile("resources/[scavengesurvive]/world/shared/logic/buttons.lua")
local DOORS_FILE = "resources/[scavengesurvive]/world/shared/logic/doors.lua"
local PUZZLES_FILE = "resources/[scavengesurvive]/world/shared/logic/puzzles.lua"
local puzzles = dofile(PUZZLES_FILE)
local data = dofile("resources/[scavengesurvive]/world/data/puzzles.lua")

-- each registry from freshly loaded definitions (addDoor writes into the definitions' button tables)
local function registry()
    local reg = buttons.new()
    dofile(DOORS_FILE).register(reg, buttons)
    dofile(PUZZLES_FILE).register(reg, buttons)
    return reg
end

local function message(key)
    return { "message", puzzles.SAY[key][1], puzzles.SAY[key][2] }
end

local function teleport(reg, id)
    local b = reg.byId[id]
    return { "teleport", b[1], b[2], b[3], b[4] }
end

local function has(out, effect)
    for _, e in ipairs(out) do
        if e[1] == effect then
            return true
        end
    end
    return false
end

describe("world puzzles", function()
    local reg, state
    before_each(function()
        reg = registry()
        state = puzzles.newState()
    end)

    local function press(id, tag, holding)
        return puzzles.press(state, reg, buttons, id, tag, holding)
    end

    describe("Mt Chiliad radio station door", function()
        it("says the keypad is broken while unpowered", function()
            assert.same({ { "message", "Door", "The keypad seems broken" } }, press("chDoor"))
            assert.are.equal("closed", reg.states.chDoor)
        end)

        it("takes the fusebox, then empty hands move the door, which stays where it was moved", function()
            assert.same({ { "consume" } }, press("chDoor", puzzles.TAGS.fusebox, true))
            assert.is_true(state.powered)
            assert.same({ { "changed" } }, press("chDoor"))
            assert.are.equal("open", reg.states.chDoor)
            assert.same({ { "changed" } }, press("chDoor"))
            assert.are.equal("closed", reg.states.chDoor)
        end)

        it("does nothing with any other item in hand", function()
            assert.same({}, press("chDoor", nil, true))
            assert.same({}, press("chDoor", puzzles.TAGS.hdd, true))
            press("chDoor", puzzles.TAGS.fusebox, true)
            assert.same({}, press("chDoor", nil, true))
            assert.are.equal("closed", reg.states.chDoor)
        end)

        it("shorts on the battery: the keypad sparks, its button goes and every press after is empty", function()
            local out = press("chDoor", puzzles.TAGS.battery, true)
            assert.is_true(state.shorted)
            assert.is_true(has(out, "changed"))
            assert.is_true(has(out, "spark"))
            assert.same({}, press("chDoor"))
            assert.same({}, press("chDoor", puzzles.TAGS.fusebox, true))
            assert.is_true(puzzles.hidden(state, reg.byId.chDoor))
            assert.is_false(puzzles.hidden(state, reg.byId.chGate))
            local hidden = function(b)
                return puzzles.hidden(state, b)
            end
            local at = buttons.buttonAt(reg, -2311.49, -1647.70, 484.36, 0, hidden)
            assert.is_nil(at)
        end)

        it("is not hidden before shorting", function()
            assert.is_false(puzzles.hidden(state, reg.byId.chDoor))
        end)

        it("opens the gate with a plain button press", function()
            assert.same({ { "changed" } }, buttons.press(reg, "chGate"))
            assert.are.equal("open", reg.states.chGate)
        end)
    end)

    describe("ranch PC", function()
        it("is off without the hard drive", function()
            assert.same({ message("pcOff") }, press("ranchPc"))
        end)

        it("starts the install with the hard drive in hand", function()
            assert.same({ message("hddIn"), { "hdd" } }, press("ranchPc", puzzles.TAGS.hdd, true))
            assert.is_false(state.pcOn)
        end)

        it("shows the view once the drive is in", function()
            puzzles.installHdd(state)
            assert.is_true(state.pcOn)
            assert.same({ { "view" } }, press("ranchPc"))
            assert.same({ { "view" } }, press("ranchPc", puzzles.TAGS.hdd, true))
        end)
    end)

    describe("quarry door", function()
        it("is locked without the key", function()
            assert.same({ message("quarryLocked") }, press("quarryDoor"))
            assert.is_false(state.quarryOpen)
        end)

        it("opens with the key, then leads into the cave and back", function()
            assert.same({ message("quarryOpened") }, press("quarryDoor", puzzles.TAGS.key, true))
            assert.is_true(state.quarryOpen)
            local into = press("quarryDoor")
            assert.same({ teleport(reg, "caveDoor") }, into)
            assert.are.equal(1, into[1][5])
            local back = buttons.press(reg, "caveDoor")
            assert.same({ teleport(reg, "quarryDoor") }, back)
            assert.are.equal(0, back[1][5])
        end)
    end)

    describe("SF lockup", function()
        it("opens the keypad", function()
            assert.same({ { "keypad", "lockup" } }, press("lockupKeypad"))
        end)

        it("points at the keypad while locked", function()
            assert.same({ { "toast", "NEARBYKEYP" } }, press("lockupOut"))
        end)

        it("opens on the right code only, as a number or a string", function()
            assert.is_false(puzzles.enterCode(state, 4321, 1234))
            assert.is_false(puzzles.enterCode(state, 4321, "abc"))
            assert.is_false(state.lockupOpen)
            assert.is_true(puzzles.enterCode(state, 4321, 4321))
            local s2 = puzzles.newState()
            assert.is_true(puzzles.enterCode(s2, 4321, "4321"))
            assert.is_true(s2.lockupOpen)
        end)

        it("lets the player in once open and out again", function()
            puzzles.enterCode(state, 4321, "4321")
            assert.same({ teleport(reg, "lockupIn") }, press("lockupOut"))
            assert.same({ teleport(reg, "lockupOut") }, buttons.press(reg, "lockupIn"))
        end)
    end)

    describe("code hunt", function()
        it("makes a 4 digit code and lays its digits in order at 4 distinct spots", function()
            local calls = {}
            local rand = function(n)
                calls[#calls + 1] = n
                return n == 8999 and 1234 or 0
            end
            local code, parts = puzzles.newCode(rand)
            assert.are.equal(2234, code)
            assert.are.equal(8999, calls[1])
            assert.are.equal(4, #parts)
            local digits, seen = {}, {}
            for i, p in ipairs(parts) do
                digits[i] = p.digit
                assert.is_nil(seen[p.spot])
                seen[p.spot] = true
            end
            assert.same({ 2, 2, 3, 4 }, digits)
            -- a rand that always gives 0 swaps every spot with the first: 2, 3, 4, 5 come out on top
            for i = 1, 4 do
                assert.are.equal(puzzles.CODE_SPOTS[i + 1], parts[i].spot)
            end
        end)

        it("stays within 1000..9999 and the spots list for any rand", function()
            local seed = 7
            local rand = function(n)
                seed = (seed * 1103515245 + 12345) % 2147483648
                return seed % n
            end
            for _ = 1, 50 do
                local code, parts = puzzles.newCode(rand)
                assert.is_true(code >= 1000 and code <= 9999)
                local spots, seen = {}, {}
                for _, s in ipairs(puzzles.CODE_SPOTS) do
                    spots[s] = true
                end
                local text = ""
                for _, p in ipairs(parts) do
                    assert.is_true(spots[p.spot])
                    assert.is_nil(seen[p.spot])
                    seen[p.spot] = true
                    text = text .. p.digit
                end
                assert.are.equal(tostring(code), text)
            end
        end)
    end)

    describe("tagOf", function()
        it("reads the tag from either JSON shape", function()
            assert.are.equal("x", puzzles.tagOf({ puzzle = "x" }))
            assert.are.equal("x", puzzles.tagOf({ { puzzle = "x" } }))
        end)

        it("is nil without a tag", function()
            assert.is_nil(puzzles.tagOf(nil))
            assert.is_nil(puzzles.tagOf("x"))
            assert.is_nil(puzzles.tagOf(false))
            assert.is_nil(puzzles.tagOf({}))
            assert.is_nil(puzzles.tagOf({ puzzle = 3 }))
            assert.is_nil(puzzles.tagOf({ { text = "hi" } }))
        end)
    end)

    describe("registry", function()
        it("links every `to` to an existing button", function()
            for _, b in ipairs(reg.buttons) do
                if b.to then
                    assert.is_table(reg.byId[b.to], b.id .. " -> " .. b.to)
                end
            end
        end)

        it("handles every puzzle-owned button", function()
            local owned = 0
            for _, b in ipairs(reg.buttons) do
                if b.owner == "puzzles" then
                    owned = owned + 1
                    local s = puzzles.newState()
                    assert.is_true(#puzzles.press(s, reg, buttons, b.id) > 0, b.id)
                end
            end
            assert.are.equal(5, owned)
        end)
    end)

    describe("data", function()
        it("has the 179 objects not in scriptfiles/maps", function()
            assert.are.equal(179, #data.objects)
        end)

        it("has the 4 tagged puzzle items, each tag one the logic asks for", function()
            local byTag = {}
            for _, t in pairs(puzzles.TAGS) do
                byTag[t] = true
            end
            local tags = {}
            for _, f in ipairs(data.fixtures) do
                assert.is_true(byTag[f[7]], f[7])
                tags[#tags + 1] = f[7]
            end
            local want = { "mtchill.ch_battery", "mtchill.ch_fusebox", "ranch.QuarryDoorKey", "ranch.RanchHdd" }
            assert.same(want, tags)
        end)
    end)
end)
