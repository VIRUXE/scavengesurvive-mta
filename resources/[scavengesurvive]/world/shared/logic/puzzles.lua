-- The world puzzles (upstream gamemodes/sss/world/puzzles/mtchill.pwn, ranch.pwn, codehunt.pwn) on top of the
-- buttons.lua registry. Their static objects are data/puzzles.lua (tools/convert/puzzles.py); their items (the radio
-- station's battery and fusebox, the ranch's hard drive, the quarry key) are fixtures tagged with the upstream
-- variable they were created into, put back by the world resource when gone. State lives in the world resource and
-- resets on its start, as upstream's globals reset on a restart.
local M = {}

M.HDD_MS = 2500 -- upstream AttachRanchHdd timer
M.SPARK_MS, M.KEYPAD_FALL_DELAY_MS = 2000, 400 -- upstream ch_keypadprt_destroy / ch_keypad_move timers

M.TAGS = {
    fusebox = "mtchill.ch_fusebox",
    battery = "mtchill.ch_battery",
    hdd = "ranch.RanchHdd",
    key = "ranch.QuarryDoorKey",
}

-- mtchill.pwn: the keypad by the door, where the battery knocks it, and the spark it gives off
M.KEYPAD = { model = 19273, pos = { -2311.4968, -1647.6813, 484.3600, 0, 0, 26.2200 }, speed = 2.8 }
M.KEYPAD.broken = { -2311.5601, -1647.6781, 484.2200, 0, 32.0, 26.0 }
M.SPARK = { model = 18724, pos = { -2311.4900, -1647.7000, 482.3600, 0, 0, 26.2200 } }

-- ranch.pwn RanchPcObj: the screen the diary appears on once the hard drive is back, and the view of it
M.SCREEN = { model = 19475, pos = { -690.966735, 942.852416, 13.642812, 0, 0, -110.324981 } }
M.SCREEN.text = table.concat({
    "system:",
    "  >login terminal\\root\\user\\steve",
    "  >open diary\\entry\\recent",
    "   I have left the ranch, they are after me",
    "   whoever finds this, I decided to go to a friends",
    "   place on chilliad, he was dead when I got there",
    "   I've hidden the key there, they won't find it",
    "   I dont know how long it will be before they find me",
}, "\n")
M.VIEW = { -691.141845, 942.489868, 13.759174, -689.749084, 946.223693, 14.104162 }

-- objects the puzzles add to the normal world (world 0), { model, x, y, z, rx, ry, rz, world }: ranch.pwn's "LS
-- entrance (by Dogmeat)" is one cellar hatch on the grass at the Ganton ladder button, created upstream in
-- RANCH_STUFF_VIRTUALW with every other ranch object, so the button stood on bare grass; it marks a world-0 button
-- and stands there too
M.PROPS = {
    { 12986, 2526.416015625, -1649.09375, 13.893012046814, 9.920654296875, 5.9490966796875, 210.89904785156, 0 },
}

-- { id, x, y, z, world, label }; owner = "puzzles" when a press needs the puzzle's state, `to` = linked button
local BUTTONS = {
    -- mtchill.pwn
    { id = "chGate", -2307.81, -1650.67, 484.36, 0, "Activate" },
    { id = "chDoor", -2311.4900, -1647.7000, 484.3600, 0, "Use", owner = "puzzles" },
    -- ranch.pwn
    { id = "ranchPc", -691.1692, 942.1066, 13.6328, 0, "Use", owner = "puzzles" },
    { id = "quarryDoor", 495.451873, 780.096191, -21.747426, 0, "Enter", owner = "puzzles" },
    { id = "caveDoor", -2702.358398, 3801.477050, 52.652801, 1, "Enter", to = "quarryDoor" },
    { id = "liftTop", -2764.0332, 3757.0466, 46.8343, 1, "Use the lift" },
    { id = "liftBottom", -2764.3410, 3755.5153, 8.2390, 1, "Use the lift" },
    { id = "clawDoor1", 264.316284, -171.135223, -50.206447, 1, "Activate" },
    { id = "clawDoor2", 265.862182, -170.113632, -50.204307, 1, "Activate" },
    { id = "metroLocked", -972.153869, 4303.185058, 48.666248, 1, "Locked" },
    -- the ranch's passages: upstream creates both ends but leaves LinkTP commented out, so its "Press F to enter"
    -- did nothing and cave 2, cave 3, the metro and the Fort Claw underground could not be reached; linked here
    { id = "cave1", -2796.933349, 3682.779785, 2.515481, 1, "Enter", to = "cave2a" },
    { id = "cave2a", -1445.01, 3673.77, 4.08, 1, "Enter", to = "cave1" },
    { id = "cave2b", -1618.94, 3648.38, 6.90, 1, "Enter", to = "cave3" },
    { id = "cave3", -785.9272, 3727.1111, 0.5293, 1, "Enter", to = "cave2b" },
    { id = "metroLadder", -1007.395263, 5782.741210, 42.951477, 1, "Climb up the ladder", to = "lsLadder" },
    { id = "lsLadder", 2526.719482, -1648.620605, 14.471982, 0, "Climb down the ladder", to = "metroLadder" },
    { id = "fcUnder", 250.599380, -154.643936, -50.768798, 1, "Enter", to = "fcTop" },
    { id = "fcTop", 247.878799, -154.444061, 2.399550, 0, "Enter", to = "fcUnder" },
    { id = "metroCave", -2276.608642, 5324.488281, 41.677970, 1, "Enter", to = "caveMetro" },
    { id = "caveMetro", -734.773986, 3861.994628, 12.482711, 1, "Enter", to = "metroCave" },
    { id = "clawUnder", 246.698684, -178.849655, -50.199367, 1, "Enter", to = "metroStation" },
    { id = "metroStation", -952.559326, 5137.799804, 46.183383, 1, "Enter", to = "clawUnder" },
    -- codehunt.pwn LoadLockup_SF: the keypad, the door outside (locked until the code is entered) and the way out
    -- (CreateLockup's "TODO: implement LinkTP", linked here: the lockup is the code hunt's reward)
    { id = "lockupKeypad", -2493.90112, 313.94443, 29.72062, 0, "Interact", owner = "puzzles" },
    { id = "lockupOut", -2499.1262, 315.1892, 29.4147, 0, "Go inside", owner = "puzzles", to = "lockupIn" },
    { id = "lockupIn", -2499.1262, 318.6712, 1036.9948, 0, "Leave", to = "lockupOut" },
}

local DOORS = {
    -- mtchill.pwn: the gate, and the radio station's door (moved by the puzzle, not by its button)
    {
        id = "chGate",
        model = 975,
        world = 0,
        closed = { -2312.10, -1652.69, 484.41, 0, 0, -154.50 },
        open = { -2317.88, -1655.44, 484.41, 0, 0, -154.50 },
        speed = 1.0,
        closeDelay = -1,
        buttons = { "chGate" },
    },
    {
        id = "chDoor",
        model = 1498,
        world = 0,
        closed = { -2311.2200, -1647.4800, 482.7210, 0, 0, 25.1400 },
        open = { -2311.2083, -1647.4178, 482.7395, 0, 0, 111.6000 },
        speed = 0.1,
        closeDelay = -1,
    },
    -- ranch.pwn CaveLift: down is "closed", up is "open"; both buttons send it to the other end (upstream's bottom
    -- button kept its flag inverted and skipped presses)
    {
        id = "caveLift",
        model = 7246,
        world = 1,
        closed = { -2759.4704, 3756.8691, 6.9, 270, 180, 340.9154 },
        open = { -2759.4704, 3756.8691, 45.4, 270, 180, 340.9154 },
        speed = 2.0,
        closeDelay = -1,
        buttons = { "liftTop", "liftBottom" },
    },
    -- ranch.pwn: the Fort Claw door underground (door.inc defaults: speed 1.0, shuts 3 s after it opened)
    {
        id = "clawDoor",
        model = 5779,
        world = 1,
        closed = { 265.0330, -168.9362, -49.9792, 0, 0, 0 },
        open = { 265.0322, -168.9355, -46.8575, 0, 0, 0 },
        buttons = { "clawDoor1", "clawDoor2" },
    },
}

function M.register(reg, buttons)
    for _, b in ipairs(BUTTONS) do
        buttons.addButton(reg, b)
    end
    for _, d in ipairs(DOORS) do
        buttons.addDoor(reg, d)
    end
end

-- codehunt.pwn: the code parts lie at 4 of these 8 spots, one digit each
M.CODE_SPOTS = {
    { -1988.97327, 1105.93872, 82.59016 },
    { -2701.18188, 849.91577, 70.42641 },
    { -1688.13623, 1331.96411, 16.24742 },
    { -1896.49524, 985.39124, 44.41820 },
    { -2579.95630, 330.52792, 9.55951 },
    { -2134.74487, 185.65819, 45.51329 },
    { -2531.18848, -709.22864, 138.31668 },
    { -1478.10754, -330.93860, 13.59040 },
}
M.CODE_TAG = "codehunt"

function M.newState()
    return {
        powered = false, -- the fusebox is in: the door's keypad works
        shorted = false, -- the battery went in instead: the keypad is knocked off and its button gone
        pcOn = false,
        quarryOpen = false,
        lockupOpen = false,
    }
end

-- a puzzle button that is gone: the shorted keypad's (upstream DestroyButton(ch_doorBtn))
function M.hidden(state, b)
    return b.id == "chDoor" and state.shorted
end

M.SAY = {
    broken = { "Door", "The keypad seems broken" },
    pcOff = {
        "Computer",
        "You try to turn on the computer but the hard disk is missing.\n"
            .. "You wonder where it could be and think it's mighty suspicious.\nThere is nothing useful nearby.",
    },
    hddIn = { "Computer", "You begin reattaching the hard drive to the computer." },
    hddDone = { "Computer", "You successfully install the hard drive without electricuting yourself, well done!" },
    quarryLocked = {
        "Door",
        "You pull on the door but it won't budge, the lock seems sturdy.\n"
            .. "There's no way you can get through here without a key.\nPerhaps you should search the shed?",
    },
    quarryOpened = { "Door", "You have unlocked the mystery door!" },
}

local function say(out, key)
    out[#out + 1] = { "message", M.SAY[key][1], M.SAY[key][2] }
end

local function teleportTo(reg, id, out)
    local t = reg.byId[id]
    out[#out + 1] = { "teleport", t[1], t[2], t[3], t[4] }
end

-- A press on a puzzle-owned button `id`, with `heldTag` (the puzzle tag of the item in hand, or nil) and `holding`
-- (anything in hand). Changes `state` and the registry's door states; returns buttons.lua's effects and:
--   { "message", title, body } · { "toast", code } · { "keypad", id } · { "consume" } the held item goes
--   { "hdd" } the 2.5 s hard drive install · { "view" } the PC's camera on or off · { "spark" } the shorted keypad
function M.press(state, reg, buttons, id, heldTag, holding)
    local out = {}
    if id == "chDoor" then
        -- OnPlayerUseItemWithBtn: the fusebox powers the keypad, the battery knocks it off and the button with it;
        -- OnPlayerActivateDoor: an item in hand never opens the door, an unpowered keypad is "broken"
        if state.shorted then
            return out
        elseif heldTag == M.TAGS.fusebox then
            state.powered = true
            out[#out + 1] = { "consume" }
        elseif heldTag == M.TAGS.battery then
            state.shorted = true
            out[#out + 1] = { "changed" }
            out[#out + 1] = { "spark" }
        elseif holding then
            return out
        elseif not state.powered then
            say(out, "broken")
        else
            buttons.toggleDoor(reg, "chDoor", out)
        end
    elseif id == "ranchPc" then
        if heldTag == M.TAGS.hdd and not state.pcOn then
            say(out, "hddIn")
            out[#out + 1] = { "hdd" }
        elseif not state.pcOn then
            say(out, "pcOff")
        else
            out[#out + 1] = { "view" }
        end
    elseif id == "quarryDoor" then
        if heldTag == M.TAGS.key and not state.quarryOpen then
            state.quarryOpen = true
            say(out, "quarryOpened")
        elseif not state.quarryOpen then
            say(out, "quarryLocked")
        else
            teleportTo(reg, "caveDoor", out)
        end
    elseif id == "lockupKeypad" then
        out[#out + 1] = { "keypad", "lockup" }
    elseif id == "lockupOut" then
        if state.lockupOpen then
            teleportTo(reg, "lockupIn", out)
        else
            out[#out + 1] = { "toast", "NEARBYKEYP" }
        end
    end
    return out
end

-- the hard drive is in (AttachRanchHdd): the PC shows the diary
function M.installHdd(state)
    state.pcOn = true
end

-- the lockup keypad (OnPlayerKeypadEnter k_Lockup): the right code opens the lockup until the next start
function M.enterCode(state, code, entered)
    if tonumber(entered) == code then
        state.lockupOpen = true
        return true
    end
    return false
end

-- codehunt.pwn CreateLockup / CreateCodeParts: a code of 1000 + random(8999) and 4 of the 8 spots, the code's
-- digits in order; rand(n) -> 0..n-1
function M.newCode(rand)
    local code = 1000 + rand(8999)
    local digits = {}
    for c in tostring(code):gmatch("%d") do
        digits[#digits + 1] = tonumber(c)
    end
    local spots = {}
    for i = 1, #M.CODE_SPOTS do
        spots[i] = i
    end
    for i = #spots, 2, -1 do
        local j = rand(i) + 1
        spots[i], spots[j] = spots[j], spots[i]
    end
    local parts = {}
    for i = 1, 4 do
        parts[i] = { digit = digits[i], spot = M.CODE_SPOTS[spots[i]] }
    end
    return code, parts
end

-- the puzzle tag an item's data carries ({ puzzle = tag }, or MTA's fromJSON wrapping it in an array)
function M.tagOf(data)
    if type(data) ~= "table" then
        return nil
    end
    local d = type(data[1]) == "table" and data[1] or data
    return type(d.puzzle) == "string" and d.puzzle or nil
end

return M
