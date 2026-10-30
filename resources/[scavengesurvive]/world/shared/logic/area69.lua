-- Area 69 (upstream gamemodes/sss/world/puzzles/area69.pwn) on top of the buttons.lua registry: 12 doors behind
-- keypads, each code drawn at random on every start, and two consoles that list the codes once their own code is
-- entered (or hacked). A door's button never moves it; it opens the keypad, the right code opens the door, and it
-- stays open until the next start (closeDelay -1, nothing closes it). Holding a Hack Device at a keypad tries the code
-- for 10 s: 40% it goes in, else a spark, -5 HP and a 3 s knockout (upstream core/ui/keypad.pwn HackKeypad). Any code
-- entered with the device in hand uses it up. The objects are data/puzzles.lua (tools/convert/puzzles.py).
local M = {}

M.CODE_NAMES = {
    "controlTower",
    "mainGate",
    "airstripGate",
    "blastDoor",
    "inner",
    "storage",
    "storageWatch",
    "generator",
    "passageTop",
    "passageBottom",
    "catwalk",
    "headquarters",
    "shaft",
}

M.HACK_MS, M.HACK_TICK_MS, M.HACK_ODDS = 10000, 100, 40 -- 100 tries at 100 ms, random(100) < 40 succeeds
M.HACK_ENTER_MS = 1000 -- HackKeypadFinish: the hacked code goes in 1 s after the last digit
M.HACK_HP, M.HACK_KO_MS = 5, 3000 -- GivePlayerHP(playerid, -5); KnockOutPlayer(playerid, 3000)
M.HACK_DEVICE = "HackDevice"

-- keypad id -> the code it takes and the doors it opens; the two consoles open none and list codes instead
-- upstream checks the main gate against the control tower's code while code list 1 shows code_MainGate for it, so the
-- listed code never worked; here the main gate takes its own listed code
M.KEYPADS = {
    controlTower = { code = "controlTower", list = 1 },
    storageWatch = { code = "storageWatch", list = 2 },
    mainGate = { code = "mainGate", doors = { "a69Main" } },
    airstripGate = { code = "airstripGate", doors = { "a69Airstrip" } },
    blastDoor = { code = "blastDoor", doors = { "a69Blast1", "a69Blast2" } },
    storage = { code = "storage", doors = { "a69Storage" } },
    generator = { code = "generator", doors = { "a69Generator" } },
    passageTop = { code = "passageTop", doors = { "a69PassageTop" } },
    passageBottom = { code = "passageBottom", doors = { "a69PassageBottom" } },
    catwalk = { code = "catwalk", doors = { "a69Catwalk" } },
    headquarters = { code = "headquarters", doors = { "a69Hq1", "a69Hq2" } },
    shaft = { code = "shaft", doors = { "a69Shaft" } },
}

-- { id, x, y, z, world, label, keypad }
local BUTTONS = {
    { id = "a69ControlTower", 211.6015, 1812.2878, 21.8594, 0, "Interact", keypad = "controlTower" },
    { id = "a69StorageWatch", 246.4888, 1861.1544, 14.0840, 0, "Interact", keypad = "storageWatch" },
    { id = "a69MainGate", 117.8747, 1932.3739, 19.5773, 0, "Activate gate", keypad = "mainGate" },
    { id = "a69AirstripGate", 280.7763, 1828.0514, 2.3915, 0, "Activate gate", keypad = "airstripGate" },
    { id = "a69Blast1", 210.3842, 1876.6578, 13.1406, 0, "Activate door", keypad = "blastDoor" },
    { id = "a69Blast2", 209.5598, 1874.3828, 13.1469, 0, "Activate door", keypad = "blastDoor" },
    { id = "a69Storage1", 237.4928, 1871.3110, 11.4609, 0, "Activate door", keypad = "storage" },
    { id = "a69Storage2", 239.3345, 1870.4381, 11.4609, 0, "Activate door", keypad = "storage" },
    { id = "a69Generator1", 247.3196, 1842.8588, 8.7614, 0, "Activate door", keypad = "generator" },
    { id = "a69Generator2", 247.3196, 1840.5961, 8.7578, 0, "Activate door", keypad = "generator" },
    { id = "a69PassageTop1", 255.3204, 1842.7847, 8.7578, 0, "Activate door", keypad = "passageTop" },
    { id = "a69PassageTop2", 257.0612, 1843.4278, 8.7578, 0, "Activate door", keypad = "passageTop" },
    { id = "a69PassageBottom1", 255.5610, 1832.4649, 4.7109, 0, "Activate door", keypad = "passageBottom" },
    { id = "a69PassageBottom2", 257.0517, 1833.1218, 4.7109, 0, "Activate door", keypad = "passageBottom" },
    { id = "a69Catwalk1", 249.3303, 1805.2384, 7.4796, 0, "Activate door", keypad = "catwalk" },
    { id = "a69Catwalk2", 249.0138, 1806.8889, 7.5546, 0, "Activate door", keypad = "catwalk" },
    { id = "a69Hq1", 234.1869, 1821.3165, 7.4141, 0, "Activate door", keypad = "headquarters" },
    { id = "a69Hq2", 228.3555, 1820.2427, 7.4141, 0, "Activate door", keypad = "headquarters" },
    { id = "a69Shaft1", 269.4969, 1873.1721, 8.6094, 0, "Activate door", keypad = "shaft" },
    { id = "a69Shaft2", 270.6281, 1875.8774, 8.4375, 0, "Activate door", keypad = "shaft" },
    -- the airstrip shaft's two ends: created upstream but never linked (the buttonid pair is not passed to LinkTP)
    { id = "a69ShaftTop", 279.1897, 1833.1392, 18.0874, 0, "Enter", to = "a69ShaftBottom" },
    { id = "a69ShaftBottom", 279.2243, 1832.3821, 2.7813, 0, "Enter", to = "a69ShaftTop" },
}

-- CreateDoor(model, buttons, closed pose, open pose, moveSpeed (1.0 unless given), .closeDelay = -1):
-- { id, model, closed, open [, speed] }
local DOORS = {
    {
        "a69Main",
        19313,
        { 134.91060, 1941.52124, 21.77760, 0, 0, 0 },
        { 120.9106, 1941.52124, 21.77760, 0, 0, 0 },
    },
    {
        "a69Airstrip",
        19313,
        { 285.98541, 1822.31140, 20.09470, 0, 0, 270 },
        { 285.98541, 1834.31140, 20.09470, 0, 0, 270 },
    },
    {
        "a69Blast1",
        2927,
        { 215.9915, 1875.2880, 13.9389, 0, 0, 0 },
        { 219.8936, 1875.2880, 13.9389, 0, 0, 0 },
        0.4,
    },
    {
        "a69Blast2",
        2929,
        { 211.8555, 1875.2880, 13.9389, 0, 0, 0 },
        { 207.8556, 1875.2880, 13.9389, 0, 0, 0 },
        0.4,
    },
    {
        "a69Storage",
        5422,
        { 238.4573, 1872.2921, 12.4737, 0, 0, 0 },
        { 238.4573, 1872.2921, 14.6002, 0, 0, 0 },
    },
    {
        "a69Generator",
        5422,
        { 248.275406, 1842.032104, 9.7770, 0, 0, 90 },
        { 248.270325, 1842.033691, 11.9806, 0, 0, 90 },
    },
    {
        "a69PassageTop",
        9093,
        { 256.3291, 1845.7827, 9.5281, 0, 0, 0 },
        { 256.3291, 1845.7827, 12.1, 0, 0, 0 },
    },
    {
        "a69PassageBottom",
        9093,
        { 256.3094, 1835.3549, 5.4820, 0, 0, 0 },
        { 256.3094, 1835.3549, 8.0035, 0, 0, 0 },
    },
    {
        "a69Catwalk",
        5422,
        { 248.3001, 1805.8772, 8.5633, 0, 0, 90 },
        { 248.3001, 1805.8772, 10.8075, 0, 0, 90 },
    },
    {
        "a69Hq1",
        1508,
        { 233.793884, 1825.885498, 7.097370, 0, 0, 0 },
        { 233.793884, 1827.063477, 7.097370, 0, 0, 0 },
    },
    {
        "a69Hq2",
        1508,
        { 233.793884, 1819.572388, 7.097370, 0, 0, 0 },
        { 233.793884, 1818.413452, 7.097370, 0, 0, 0 },
    },
    {
        "a69Shaft",
        5422,
        { 268.0739, 1875.3544, 9.6097, 0, 0, 90 },
        { 268.0739, 1875.3544, 11.6097, 0, 0, 90 },
    },
}

function M.register(reg, buttons)
    for _, b in ipairs(BUTTONS) do
        if b.keypad then
            b.owner = "area69"
        end
        buttons.addButton(reg, b)
    end
    for _, r in ipairs(DOORS) do
        local d = { id = r[1], model = r[2], world = 0, closed = r[3], open = r[4], speed = r[5], closeDelay = -1 }
        buttons.addDoor(reg, d)
    end
end

-- the codes, server-side only (never in what is sent to clients); rand(n) -> 0..n-1
function M.newState(rand)
    local codes = {}
    for _, name in ipairs(M.CODE_NAMES) do
        codes[name] = 1000 + rand(8999)
    end
    return { codes = codes, unlocked = {} }
end

-- ShowCodeList1 / ShowCodeList2: { title, body } (colours as upstream's C_ORANGE, C_WHITE, C_YELLOW)
local LISTS = {
    {
        "SECTOR 01",
        { "Control Tower", "controlTower" },
        { "Main gate", "mainGate" },
        { "Airstrip Gate", "airstripGate" },
        { "Blast Door", "blastDoor" },
        { "Inner Door 1", "inner" },
        { "Inner Door 2", "storage" },
    },
    {
        "SECTOR 02",
        { "Generator", "generator" },
        { "Passage 1", "passageTop" },
        { "Passage 2", "passageBottom" },
        { "Catwalk", "catwalk" },
        { "Headquarters", "headquarters" },
        { "Shaft", "shaft" },
    },
}

function M.codeList(state, n)
    local list = LISTS[n]
    local lines = { "#FFAA00Keycodes for security system. " .. list[1] .. ":", "" }
    for i = 2, #list do
        lines[#lines + 1] = string.format("    #FFFFFF%s:  #FFFF00%d", list[i][1], state.codes[list[i][2]])
    end
    return "Main Control", table.concat(lines, "\n")
end

-- A press on an Area 69 keypad button (OnButtonPress / OnPlayerActivateDoor -> PlayerActivateDoorButton). Returns
-- { "keypad", "a69:<keypad>", hack } (hack: the Hack Device in hand starts trying) or, at an unlocked console,
-- { "message", title, body }. With the registry: once every door a keypad opens is open, a press does nothing
-- (upstream showed the keypad again and a Hack Device there was used up for nothing).
function M.press(state, b, heldUname, reg)
    local kp = M.KEYPADS[b.keypad]
    if kp.list and state.unlocked[b.keypad] then
        local title, body = M.codeList(state, kp.list)
        return { { "message", title, body } }
    end
    if reg and M.allOpen(reg, b.keypad) then
        return {}
    end
    return { { "keypad", "a69:" .. b.keypad, heldUname == M.HACK_DEVICE } }
end

-- true when every door the keypad opens is open (false for the consoles, which open none)
function M.allOpen(reg, keypad)
    local doors = M.KEYPADS[keypad] and M.KEYPADS[keypad].doors
    if not doors then
        return false
    end
    for _, d in ipairs(doors) do
        if reg.states[d] ~= "open" then
            return false
        end
    end
    return true
end

-- the keypad's code, for the hack to put in when it succeeds
function M.codeFor(state, keypadId)
    local kp = M.KEYPADS[(keypadId or ""):match("^a69:(.+)$") or ""]
    return kp and state.codes[kp.code] or nil
end

-- OnPlayerKeypadEnter for keypad id "a69:<keypad>" with `entered` and the Hack Device in hand or not. Changes the
-- state and the registry's doors; returns effects:
--   { "consume" } the device goes · { "changed" } · { "close" } the keypad shuts · { "message", title, body }
-- and false when the code was wrong (nothing but the device's loss).
function M.enterCode(state, reg, keypadId, entered, holdingDevice)
    local name = (keypadId or ""):match("^a69:(.+)$")
    local kp = name and M.KEYPADS[name]
    local out = {}
    if not kp then
        return out, false
    end
    if holdingDevice then
        out[#out + 1] = { "consume" }
    end
    if tonumber(entered) ~= state.codes[kp.code] then
        return out, false
    end
    out[#out + 1] = { "close" }
    if kp.list then
        state.unlocked[name] = true
        local title, body = M.codeList(state, kp.list)
        out[#out + 1] = { "message", title, body }
    end
    for _, d in ipairs(kp.doors or {}) do
        if reg.states[d] ~= "open" then
            reg.states[d] = "open"
            out[#out + 1] = { "changed" }
        end
    end
    return out, true
end

-- HackKeypadUpdate's last try: true when the code goes in (random(100) < 40); rand(n) -> 0..n-1
function M.hackSucceeds(rand)
    return rand(100) < M.HACK_ODDS
end

return M
