-- Tests for the buttons and the doors they move (world/shared/logic/buttons.lua, upstream button.inc and door.inc)
-- and the zone files' gates and doors (world/shared/logic/doors.lua).
local buttons = dofile("resources/[scavengesurvive]/world/shared/logic/buttons.lua")
local DOORS_FILE = "resources/[scavengesurvive]/world/shared/logic/doors.lua"
local PUZZLES_FILE = "resources/[scavengesurvive]/world/shared/logic/puzzles.lua"
local doors = dofile(DOORS_FILE)

local function door(id, btns, extra)
    local d = {
        id = id,
        model = 1498,
        world = 0,
        closed = { 0, 0, 0, 0, 0, 0 },
        open = { 0, 0, 3.0, 0, 0, 0 },
        buttons = btns,
    }
    for k, v in pairs(extra or {}) do
        d[k] = v
    end
    return d
end

-- each registry from freshly loaded definitions: addDoor writes the doors into the definitions' button tables, so
-- registering the same loaded module twice would give its buttons every door twice
local function zoneRegistry()
    local reg = buttons.new()
    dofile(DOORS_FILE).register(reg, buttons)
    return reg
end

describe("world buttons", function()
    describe("registry", function()
        it("adds buttons and doors, a door's buttons learn it, and doors start closed", function()
            local reg = buttons.new()
            local b = buttons.addButton(reg, { id = "a", 1, 2, 3, 0, "Activate" })
            assert.are.equal(b, reg.byId.a)
            assert.are.equal(1, #reg.buttons)
            local d = buttons.addDoor(reg, door("d", { "a" }))
            assert.are.equal(d, reg.doors.d)
            assert.same({ "d" }, reg.doorIds)
            assert.same({ "d" }, reg.doorsOf.a)
            assert.is_nil(b.doors) -- the button definition is left as it was
            assert.are.equal("closed", reg.states.d)
            assert.are.equal(1.0, d.speed)
            assert.are.equal(3000, d.closeDelay)
        end)

        it("builds two registries from the same definitions without one press moving a door twice", function()
            local r1, r2 = buttons.new(), buttons.new()
            doors.register(r1, buttons)
            doors.register(r2, buttons)
            assert.same({ "sfCity1a" }, r2.doorsOf.sfCity1a1)
            buttons.press(r2, "sfCity1a1")
            assert.are.equal("open", r2.states.sfCity1a)
            assert.are.equal("closed", r1.states.sfCity1a)
        end)

        it("asserts on a duplicate button or door id", function()
            local reg = buttons.new()
            buttons.addButton(reg, { id = "a", 1, 2, 3, 0, "Activate" })
            assert.has_error(function()
                buttons.addButton(reg, { id = "a", 4, 5, 6, 0, "Activate" })
            end)
            buttons.addDoor(reg, door("d", { "a" }))
            assert.has_error(function()
                buttons.addDoor(reg, door("d", { "a" }))
            end)
        end)

        it("asserts on a door with an unknown button", function()
            local reg = buttons.new()
            assert.has_error(function()
                buttons.addDoor(reg, door("d", { "nope" }))
            end)
        end)
    end)

    describe("buttonAt", function()
        local reg = buttons.new()
        buttons.addButton(reg, { id = "near", 0, 0, 0, 0, "Near" })
        buttons.addButton(reg, { id = "far", 1.2, 0, 0, 0, "Far" })
        buttons.addButton(reg, { id = "inside", 0, 0, 0, 1, "Inside" })

        it("picks the closest button within reach", function()
            assert.are.equal("near", buttons.buttonAt(reg, 0.5, 0, 0, 0).id)
            assert.are.equal("far", buttons.buttonAt(reg, 1.0, 0, 0, 0).id)
            assert.are.equal("near", buttons.buttonAt(reg, 0.1, 0, 0).id) -- world defaults to 0
        end)

        it("only sees the buttons of the player's world", function()
            assert.are.equal("inside", buttons.buttonAt(reg, 0.1, 0, 0, 1).id)
            assert.is_nil(buttons.buttonAt(reg, 0, 0, 0, 2))
        end)

        it("skips hidden buttons", function()
            local hidden = function(b)
                return b.id == "near"
            end
            assert.are.equal("far", buttons.buttonAt(reg, 0.2, 0, 0, 0, hidden).id)
        end)

        it("returns nil out of reach", function()
            assert.are.equal(1.5, buttons.REACH)
            assert.is_nil(buttons.buttonAt(reg, -1.6, 0, 0, 0))
            assert.is_nil(buttons.buttonAt(reg, 0, 0, 2, 0))
        end)
    end)

    describe("doorMs", function()
        it("is the distance over the speed in ms", function()
            local reg = zoneRegistry()
            dofile(PUZZLES_FILE).register(reg, buttons)
            assert.are.equal(3240, buttons.doorMs(reg.doors.sfCity1a))
            assert.are.equal(8000, buttons.doorMs(reg.doors.lvKacc1))
            assert.are.equal(19250, buttons.doorMs(reg.doors.caveLift))
            assert.are.equal(659, buttons.doorMs(reg.doors.chDoor)) -- the radio station's door mostly turns
            assert.are.equal(2000, buttons.doorMs(reg.doors.sfNavalGate)) -- 2 cm at 1 cm/s
        end)

        it("never goes under 200 ms", function()
            local d = door("d", {}, { speed = 1.0, open = { 0, 0, 0.01, 0, 0, 90 } })
            assert.are.equal(buttons.MIN_MOVE_MS, buttons.doorMs(d))
            assert.are.equal(200, buttons.doorMs(door("e", {}, { speed = 1.0, open = { 0, 0, 0, 0, 0, 0 } })))
        end)

        it("draws a door at its open pose only when open", function()
            local d = door("d", {})
            assert.are.equal(d.open, buttons.pose(d, "open"))
            assert.are.equal(d.closed, buttons.pose(d, "closed"))
        end)
    end)

    describe("toggleDoor and press", function()
        it("opens a door that shuts by itself with changed and an autoclose after its move and delay", function()
            local reg = zoneRegistry()
            local out = buttons.press(reg, "sfCity1a1")
            assert.are.equal("open", reg.states.sfCity1a)
            assert.same({ { "changed" }, { "autoclose", "sfCity1a", 3240 + 3000 } }, out)
        end)

        it("gives no autoclose for a closeDelay -1 door", function()
            local reg = zoneRegistry()
            assert.same({ { "changed" } }, buttons.press(reg, "sfNavalGate"))
            assert.are.equal("open", reg.states.sfNavalGate)
        end)

        it("closes again on a second press, from either of the door's buttons", function()
            local reg = zoneRegistry()
            buttons.press(reg, "sfCity1a1")
            assert.same({ { "changed" } }, buttons.press(reg, "sfCity1a2"))
            assert.are.equal("closed", reg.states.sfCity1a)
        end)

        it("toggleDoor appends to the given list", function()
            local reg = zoneRegistry()
            local out = { { "x" } }
            assert.are.equal(out, buttons.toggleDoor(reg, "sfNavalGate", out))
            assert.same({ { "x" }, { "changed" } }, out)
        end)

        it("one button moves both KACC gates", function()
            local reg = zoneRegistry()
            local out = buttons.press(reg, "lvKacc")
            assert.are.equal("open", reg.states.lvKacc1)
            assert.are.equal("open", reg.states.lvKacc2)
            local want = {
                { "changed" },
                { "autoclose", "lvKacc1", 11000 },
                { "changed" },
                { "autoclose", "lvKacc2", 11000 },
            }
            assert.same(want, out)
        end)

        it("teleports to the linked button", function()
            local reg = buttons.new()
            buttons.addButton(reg, { id = "a", 1, 2, 3, 0, "Enter", to = "b" })
            buttons.addButton(reg, { id = "b", 4, 5, 6, 1, "Leave", to = "a" })
            assert.same({ { "teleport", 4, 5, 6, 1 } }, buttons.press(reg, "a"))
            assert.same({ { "teleport", 1, 2, 3, 0 } }, buttons.press(reg, "b"))
        end)

        it("does nothing for an unknown button", function()
            assert.same({}, buttons.press(zoneRegistry(), "nope"))
        end)
    end)

    describe("autoClose", function()
        it("shuts an open door once, then reports it shut already", function()
            local reg = zoneRegistry()
            buttons.press(reg, "sfCity1a1")
            assert.is_true(buttons.autoClose(reg, "sfCity1a"))
            assert.are.equal("closed", reg.states.sfCity1a)
            assert.is_false(buttons.autoClose(reg, "sfCity1a"))
        end)
    end)

    describe("the zone files' doors", function()
        it("registers 6 buttons and 5 doors", function()
            local reg = zoneRegistry()
            assert.are.equal(6, #reg.buttons)
            assert.same({ "sfCity1a", "sfCity1b", "sfNavalGate", "lvKacc1", "lvKacc2" }, reg.doorIds)
            for _, id in ipairs(reg.doorIds) do
                assert.are.equal("closed", reg.states[id])
            end
        end)

        it("stands the KACC keypad as a prop", function()
            local found = false
            for _, p in ipairs(doors.PROPS) do
                found = found or p[1] == 19273
            end
            assert.is_true(found)
        end)
    end)
end)
