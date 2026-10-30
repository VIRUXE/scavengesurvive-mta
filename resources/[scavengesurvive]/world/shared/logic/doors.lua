-- The zone files' gates and doors (upstream gamemodes/sss/world/zones/*.pwn CreateButton + CreateDoor), hand-ported
-- as the design spec plans for buttons and doors. The teleport buttons there (LinkTP) sit in comment blocks
-- upstream and are not ported. register(reg) adds them to a buttons.lua registry.
local M = {}

-- objects that go with them and stand nowhere else: the keypad by the KACC gates (lv.pwn CreateObject)
M.PROPS = {
    { 19273, 2503.98120, 2780.09302, 11.36690, 0, 0, 90.0, 0 },
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

function M.register(reg, buttons)
    for _, b in ipairs(BUTTONS) do
        buttons.addButton(reg, b)
    end
    for _, d in ipairs(DOORS) do
        buttons.addDoor(reg, d)
    end
end

return M
