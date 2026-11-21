-- The zone files' gates and doors (upstream gamemodes/sss/world/zones/*.pwn CreateButton + CreateDoor), hand-ported
-- as the design spec plans for buttons and doors. The teleport buttons there (LinkTP) sit in comment blocks
-- upstream and are not ported. register(reg) adds them to a buttons.lua registry.
local M = {}

-- objects that go with them and stand nowhere else: the keypad by the KACC gates (lv.pwn CreateObject); the hand chain
-- of Harry Plums' loading door, inside by its south jamb (prop_models shutter_chain)
M.PROPS = {
    { 19273, 2503.98120, 2780.09302, 11.36690, 0, 0, 90.0, 0 },
    { 20306, -2103.128, -19.509, 35.227, 0, 0, 90.0, 0 },
}

-- vanilla objects a door here (or a hauled one) takes the place of: { model, radius, x, y, z } (removeWorldModel)
M.REMOVALS = {
    { 11102, 3.0, -2102.9297, -16.0547, 36.4844 }, -- burgalrydoor_SFS, Harry Plums' loading door
}

local BUTTONS = {
    -- sf.pwn SF_District_City1: two shutters, two buttons each
    { id = "sfCity1a1", -2208.2568, 579.8558, 35.7653, 0, "Activate" },
    { id = "sfCity1a2", -2208.2561, 584.4679, 35.7653, 0, "Activate" },
    { id = "sfCity1b1", -2243.0400, 640.7287, 49.9911, 0, "Activate" },
    { id = "sfCity1b2", -2238.6035, 641.0287, 49.9911, 0, "Activate" },
    -- sf.pwn SF_District_Naval: the barrier arm (lifted by turning ry from 270 to 0)
    { id = "sfNavalGate", -1520.4270, 482.1193, 7.6727, 0, "Activate gate" },
    -- lv.pwn LV_District_KACC: one button for the two gates
    { id = "lvKacc", 2503.98120, 2780.09302, 11.36690, 0, "Activate" },
}

local DOORS = {
    {
        id = "sfCity1a",
        model = 16501,
        world = 0,
        closed = { -2211.40, 581.99, 36.37, 0, 0, 90.0 },
        open = { -2211.40, 581.99, 39.61, 0, 0, 90.0 },
        buttons = { "sfCity1a1", "sfCity1a2" },
    },
    {
        id = "sfCity1b",
        model = 16501,
        world = 0,
        closed = { -2241.90, 643.55, 50.69, 0, 0, 0 },
        open = { -2241.90, 643.55, 53.96, 0, 0, 0 },
        buttons = { "sfCity1b1", "sfCity1b2" },
    },
    {
        id = "sfNavalGate",
        model = 968,
        world = 0,
        closed = { -1526.4375, 481.3828, 7.02, 356.8584, 270.0, 0 },
        open = { -1526.4375, 481.3828, 7.00, 356.8584, 0, 0 },
        speed = 0.01,
        closeDelay = -1,
        buttons = { "sfNavalGate" },
    },
    {
        id = "lvKacc1",
        model = 985,
        world = 0,
        closed = { 2497.36523438, 2777.06933594, 11.55891800, 0, 0, 90.0 },
        open = { 2497.36523438, 2785.06933594, 11.55891800, 0, 0, 90.0 },
        buttons = { "lvKacc" },
    },
    {
        id = "lvKacc2",
        model = 986,
        world = 0,
        closed = { 2497.35888672, 2769.11181641, 11.55891800, 0, 0, 90.0 },
        open = { 2497.36523438, 2761.11181641, 11.55891800, 0, 0, 90.0 },
        buttons = { "lvKacc" },
    },
}

-- Doors worked by hand on a chain, not by a button: hold the engine-bay key (E) at `reach` and the door moves while
-- the key is down, stops where it is when it comes up, and falls shut if the hauler walks off, dies or leaves while
-- hauling. A hold from shut raises it, from fully open lowers it, from part way reverses the last haul. `t` runs from
-- 0 (closed) to 1 (open); a full haul takes upMs or downMs, a fall from fully open fallMs.
-- lang:begin
local PULL_CHAIN = "(Hold) Pull chain"
-- lang:end
M.HAULED = {
    {
        -- Harry Plums' warehouse, Doherty (house_shell burgalrystore_sfs): the vanilla roller door, up and over, it
        -- tips back to lie under the roof inside; its hand chain inside by the south jamb (M.PROPS), reached from
        -- 1.2 m in so the wall keeps it from the street
        id = "hpLoading",
        model = 11102,
        world = 0,
        closed = { -2102.9297, -16.0547, 36.4844, 0, 0, 180.0 },
        open = { -2105.31, -16.0547, 39.31, 0, 90.0, 180.0 },
        reach = { -2104.3, -19.51, 35.32 },
        chain = { -2103.128, -19.509, 36.6 },
        label = PULL_CHAIN,
        upMs = 7000,
        downMs = 5500,
        fallMs = 1400,
    },
}
M.HAUL_REACH = 1.5 -- the hold starts within this of `reach`; walking past HAUL_REACH + 1.0 drops the door

-- the pose of a hauled door at t (0 closed .. 1 open), each value straight between its poses as moveObject runs them
function M.hauledPose(d, t)
    local out = {}
    for i = 1, 6 do
        out[i] = d.closed[i] + (d.open[i] - d.closed[i]) * t
    end
    return out
end

function M.register(reg, buttons)
    for _, b in ipairs(BUTTONS) do
        buttons.addButton(reg, b)
    end
    for _, d in ipairs(DOORS) do
        buttons.addDoor(reg, d)
    end
end

return M
