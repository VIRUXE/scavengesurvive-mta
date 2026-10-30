-- Tests for Area 69 (world/shared/logic/area69.lua, upstream world/puzzles/area69.pwn and core/ui/keypad.pwn
-- HackKeypad) on the buttons.lua registry.
local buttons = dofile("resources/[scavengesurvive]/world/shared/logic/buttons.lua")
local DOORS_FILE = "resources/[scavengesurvive]/world/shared/logic/doors.lua"
local PUZZLES_FILE = "resources/[scavengesurvive]/world/shared/logic/puzzles.lua"
local AREA69_FILE = "resources/[scavengesurvive]/world/shared/logic/area69.lua"
local area69 = dofile(AREA69_FILE)

local BLAST_DOORS = { a69Blast1 = true, a69Blast2 = true }

-- each registry from freshly loaded definitions (register writes into the definitions' button tables)
local function registry()
    local reg = buttons.new()
    dofile(AREA69_FILE).register(reg, buttons)
    return reg
end

-- rand(n) -> 100, 200, ... on each call, so every code differs
local function counter()
    local i = 0
    return function()
        i = i + 1
        return i * 100
    end
end

local function count(out, effect)
    local n = 0
    for _, e in ipairs(out) do
        if e[1] == effect then
            n = n + 1
        end
    end
    return n
end

local function find(out, effect)
    for _, e in ipairs(out) do
        if e[1] == effect then
            return e
        end
    end
    return nil
end

local function stateWithCodes()
    return area69.newState(counter())
end

describe("area69", function()
    describe("register", function()
        local reg
        before_each(function()
            reg = registry()
        end)

        it("adds 22 buttons: 20 keypad buttons owned by area69 and the two linked shaft ends", function()
            assert.are.equal(22, #reg.buttons)
            local owned = 0
            for _, b in ipairs(reg.buttons) do
                if b.keypad then
                    assert.are.equal("area69", b.owner, b.id)
                    owned = owned + 1
                end
            end
            assert.are.equal(20, owned)
            local top, bottom = reg.byId.a69ShaftTop, reg.byId.a69ShaftBottom
            assert.are.equal("a69ShaftBottom", top.to)
            assert.are.equal("a69ShaftTop", bottom.to)
            assert.is_nil(top.owner)
            assert.is_nil(bottom.owner)
        end)

        it("adds 12 doors that stay open, the blast doors at 0.4 and the rest at 1.0", function()
            assert.are.equal(12, #reg.doorIds)
            for _, id in ipairs(reg.doorIds) do
                local d = reg.doors[id]
                assert.are.equal(-1, d.closeDelay, id)
                assert.are.equal(BLAST_DOORS[id] and 0.4 or 1.0, d.speed, id)
                assert.are.equal("closed", reg.states[id])
            end
        end)

        it("names only existing doors in KEYPADS and only KEYPADS keys on buttons", function()
            for name, kp in pairs(area69.KEYPADS) do
                for _, d in ipairs(kp.doors or {}) do
                    assert.is_table(reg.doors[d], name .. " -> " .. d)
                end
            end
            for _, b in ipairs(reg.buttons) do
                if b.keypad then
                    assert.is_table(area69.KEYPADS[b.keypad], b.id)
                end
            end
        end)

        it("leaves the shaft ends to the plain button press: a teleport to the other end", function()
            local b = reg.byId.a69ShaftBottom
            assert.same({ { "teleport", b[1], b[2], b[3], b[4] } }, buttons.press(reg, "a69ShaftTop"))
        end)

        it("registers next to the zone doors and the puzzles without a duplicate id", function()
            local full = buttons.new()
            dofile(DOORS_FILE).register(full, buttons)
            dofile(PUZZLES_FILE).register(full, buttons)
            local before = #full.buttons
            assert.has_no.errors(function()
                dofile(AREA69_FILE).register(full, buttons)
            end)
            assert.are.equal(before + 22, #full.buttons)
        end)
    end)

    describe("newState", function()
        it("draws one code per name, each 1000 + rand(8999), and unlocks nothing", function()
            local asked = {}
            local i = 0
            local rand = function(n)
                asked[#asked + 1] = n
                i = i + 1
                return i * 100
            end
            local state = area69.newState(rand)
            assert.are.equal(13, #area69.CODE_NAMES)
            assert.are.equal(13, #asked)
            local n = 0
            for _ in pairs(state.codes) do
                n = n + 1
            end
            assert.are.equal(13, n)
            for k, name in ipairs(area69.CODE_NAMES) do
                assert.are.equal(8999, asked[k])
                assert.are.equal(1000 + k * 100, state.codes[name], name)
            end
            assert.same({}, state.unlocked)
        end)
    end)

    describe("press", function()
        local reg, state
        before_each(function()
            reg = registry()
            state = stateWithCodes()
        end)

        it("opens the keypad at a door button, hacking only with the Hack Device in hand", function()
            local b = reg.byId.a69Blast1
            assert.same({ { "keypad", "a69:blastDoor", false } }, area69.press(state, b))
            assert.same({ { "keypad", "a69:blastDoor", true } }, area69.press(state, b, "HackDevice"))
            assert.same({ { "keypad", "a69:blastDoor", false } }, area69.press(state, b, "M9Pistol"))
        end)

        it("does nothing at a door button once all its doors are open, so no Hack Device is wasted there", function()
            local b = reg.byId.a69Blast1
            reg.states.a69Blast1 = "open"
            assert.same({ { "keypad", "a69:blastDoor", true } }, area69.press(state, b, "HackDevice", reg))
            assert.is_false(area69.allOpen(reg, "blastDoor"))
            reg.states.a69Blast2 = "open"
            assert.is_true(area69.allOpen(reg, "blastDoor"))
            assert.same({}, area69.press(state, b, "HackDevice", reg))
            assert.is_false(area69.allOpen(reg, "controlTower")) -- a console opens no doors
        end)

        it("opens the keypad at the control tower until unlocked, then lists the SECTOR 01 codes", function()
            local b = reg.byId.a69ControlTower
            assert.same({ { "keypad", "a69:controlTower", false } }, area69.press(state, b))
            state.unlocked.controlTower = true
            local out = area69.press(state, b)
            assert.are.equal(1, #out)
            assert.are.equal("message", out[1][1])
            assert.are.equal("Main Control", out[1][2])
            local body = out[1][3]
            assert.truthy(body:find("#FFAA00", 1, true))
            assert.truthy(body:find("SECTOR 01", 1, true))
            local names = { "controlTower", "mainGate", "airstripGate", "blastDoor", "inner", "storage" }
            for _, name in ipairs(names) do
                assert.truthy(body:find(tostring(state.codes[name]), 1, true), name)
            end
        end)

        it("opens the keypad at the storage watch until unlocked, then lists the SECTOR 02 codes", function()
            local b = reg.byId.a69StorageWatch
            assert.same({ { "keypad", "a69:storageWatch", false } }, area69.press(state, b))
            state.unlocked.storageWatch = true
            local out = area69.press(state, b)
            assert.are.equal("message", out[1][1])
            assert.are.equal("Main Control", out[1][2])
            local body = out[1][3]
            assert.truthy(body:find("#FFAA00", 1, true))
            assert.truthy(body:find("SECTOR 02", 1, true))
            local names = { "generator", "passageTop", "passageBottom", "catwalk", "headquarters", "shaft" }
            for _, name in ipairs(names) do
                assert.truthy(body:find(tostring(state.codes[name]), 1, true), name)
            end
        end)
    end)

    describe("enterCode", function()
        local reg, state
        before_each(function()
            reg = registry()
            state = stateWithCodes()
        end)

        local function allClosed()
            for _, id in ipairs(reg.doorIds) do
                assert.are.equal("closed", reg.states[id], id)
            end
        end

        it("does nothing on a wrong code", function()
            local out, ok = area69.enterCode(state, reg, "a69:blastDoor", state.codes.blastDoor + 1)
            assert.same({}, out)
            assert.is_false(ok)
            allClosed()
        end)

        it("uses up the Hack Device on a wrong code", function()
            local out, ok = area69.enterCode(state, reg, "a69:blastDoor", 1, true)
            assert.same({ { "consume" } }, out)
            assert.is_false(ok)
            allClosed()
        end)

        it("opens both blast doors on the right code, and changes nothing when entered again", function()
            local code = state.codes.blastDoor
            local out, ok = area69.enterCode(state, reg, "a69:blastDoor", code)
            assert.is_true(ok)
            assert.are.equal("open", reg.states.a69Blast1)
            assert.are.equal("open", reg.states.a69Blast2)
            assert.are.equal(1, count(out, "close"))
            assert.are.equal(2, count(out, "changed"))
            assert.are.equal(0, count(out, "consume"))
            local again, ok2 = area69.enterCode(state, reg, "a69:blastDoor", code)
            assert.is_true(ok2)
            assert.are.equal(1, count(again, "close"))
            assert.are.equal(0, count(again, "changed"))
        end)

        it("uses up the Hack Device on a right code too", function()
            local out, ok = area69.enterCode(state, reg, "a69:storage", state.codes.storage, true)
            assert.is_true(ok)
            assert.are.equal(1, count(out, "consume"))
            assert.are.equal("open", reg.states.a69Storage)
        end)

        it("opens both headquarters doors", function()
            local _, ok = area69.enterCode(state, reg, "a69:headquarters", state.codes.headquarters)
            assert.is_true(ok)
            assert.are.equal("open", reg.states.a69Hq1)
            assert.are.equal("open", reg.states.a69Hq2)
        end)

        it("unlocks the control tower console and lists its codes without opening a door", function()
            local out, ok = area69.enterCode(state, reg, "a69:controlTower", state.codes.controlTower)
            assert.is_true(ok)
            assert.is_true(state.unlocked.controlTower)
            local msg = find(out, "message")
            assert.is_table(msg)
            assert.are.equal("Main Control", msg[2])
            local title, body = area69.codeList(state, 1)
            assert.same({ "message", title, body }, msg)
            assert.are.equal(0, count(out, "changed"))
            allClosed()
        end)

        it("opens the main gate on its own listed code, not the control tower's", function()
            assert.are_not.equal(state.codes.mainGate, state.codes.controlTower)
            local _, wrong = area69.enterCode(state, reg, "a69:mainGate", state.codes.controlTower)
            assert.is_false(wrong)
            assert.are.equal("closed", reg.states.a69Main)
            local _, ok = area69.enterCode(state, reg, "a69:mainGate", state.codes.mainGate)
            assert.is_true(ok)
            assert.are.equal("open", reg.states.a69Main)
        end)

        it("ignores a keypad that is not Area 69's", function()
            for _, id in ipairs({ "a69:nope", "lockup" }) do
                local out, ok = area69.enterCode(state, reg, id, state.codes.blastDoor, true)
                assert.same({}, out)
                assert.is_false(ok)
            end
            local out, ok = area69.enterCode(state, reg, nil, state.codes.blastDoor)
            assert.same({}, out)
            assert.is_false(ok)
            allClosed()
        end)

        it("takes the code as a string", function()
            state.codes.blastDoor = 1234
            local _, ok = area69.enterCode(state, reg, "a69:blastDoor", "1234")
            assert.is_true(ok)
            assert.are.equal("open", reg.states.a69Blast1)
        end)
    end)

    describe("codeFor", function()
        it("gives the keypad's code, or nil for an unknown keypad", function()
            local state = stateWithCodes()
            assert.are.equal(state.codes.storage, area69.codeFor(state, "a69:storage"))
            assert.are.equal(state.codes.headquarters, area69.codeFor(state, "a69:headquarters"))
            assert.is_nil(area69.codeFor(state, "a69:nope"))
            assert.is_nil(area69.codeFor(state, "lockup"))
            assert.is_nil(area69.codeFor(state, nil))
        end)
    end)

    describe("hackSucceeds", function()
        it("succeeds when rand(100) is below 40", function()
            for r = 0, 99 do
                local asked
                local rand = function(n)
                    asked = n
                    return r
                end
                assert.are.equal(r < 40, area69.hackSucceeds(rand), tostring(r))
                assert.are.equal(100, asked)
            end
        end)
    end)

    describe("codeList", function()
        it("titles both lists Main Control with a header, a blank line and 6 codes", function()
            local state = stateWithCodes()
            for n = 1, 2 do
                local title, body = area69.codeList(state, n)
                assert.are.equal("Main Control", title)
                local lines = {}
                for line in (body .. "\n"):gmatch("(.-)\n") do
                    lines[#lines + 1] = line
                end
                assert.are.equal(8, #lines)
                assert.are.equal("", lines[2])
                assert.truthy(lines[1]:find("SECTOR 0" .. n, 1, true))
                for i = 3, 8 do
                    assert.truthy(lines[i]:find("#FFFF00%d%d%d%d$"), lines[i])
                end
            end
        end)
    end)
end)
