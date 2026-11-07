-- The snack machine (tools/make_vending.py): a SnackMachine item is a take-only container of 20 coils behind a glass
-- pane. The pane takes GLASS_HP hits before it breaks; only then does the machine open. Its data:
--   glass: hits the pane still takes (absent: GLASS_HP, intact; 0: broken)
--   ids:   20 item ids, coil by coil (0 for an empty coil), so a snack keeps its coil while others are taken
--   shelf: the 20 unames the coils show ("" for empty), what clients draw
-- Machine space: the base's centre at the origin, the front facing -Y (as the vanilla machine), z up.
local M = {}

M.UNAME = "SnackMachine"
M.GLASS_HP = 3
M.ROWS, M.COLS = 5, 4
M.SLOTS = M.ROWS * M.COLS
M.MODEL_GLASS, M.MODEL_BROKEN = 20234, 20235

-- tools/make_vending.py WINDOW, GLASS_Y, TRAY_TOPS (bottom tray first), COLUMNS, SLOT_Y
M.WINDOW = { x0 = -0.52, x1 = 0.24, z0 = 0.56, z1 = 1.99 }
M.GLASS_Y = -0.385
M.TRAY_TOPS = { 0.58, 0.866, 1.152, 1.438, 1.724 }
M.COLUMNS = { -0.425, -0.235, -0.045, 0.145 }
M.SLOT_Y = -0.25

-- half the height each snack stands in a coil: its model's length (lying, along Y) halved (make_vending SNACKS dims)
M.HALF = {
    PhatChips = 0.11,
    CheesyPuffs = 0.11,
    Pretzels = 0.1,
    SaltedPeanuts = 0.075,
    BeefJerky = 0.085,
    MeteoriteBar = 0.0225,
    ZebraBar = 0.0225,
    EgoChaser = 0.02,
    FruitCandy = 0.0375,
    Cookies = 0.095,
}

function M.is(uname)
    return uname == M.UNAME
end

-- hits the pane still takes, from the machine's decoded data
function M.glass(data)
    local g = type(data) == "table" and tonumber(data.glass)
    return g or M.GLASS_HP
end

function M.isBroken(data)
    return M.glass(data) <= 0
end

-- a hit's damage to the pane by GTA weapon id: a fist 1, a melee weapon 2, anything fired breaks it at once
function M.hitDamage(weapon)
    weapon = tonumber(weapon) or 0
    if weapon == 0 or weapon == 1 then
        return 1
    elseif weapon < 16 then
        return 2
    end
    return M.GLASS_HP
end

-- coil (1..20, top row first, left to right seen from the front) -> machine-space offset of the snack and its
-- rotation (stood up, label out)
function M.slotPose(coil, uname)
    local row = math.floor((coil - 1) / M.COLS) -- 0 = top
    local col = (coil - 1) % M.COLS + 1
    local zt = M.TRAY_TOPS[M.ROWS - row]
    return M.COLUMNS[col], M.SLOT_Y, zt + (M.HALF[uname] or 0.08), 90, 0, 0
end

-- The coils after a change: prevIds (data.ids, or nil) and items { { id, uname } ... } as the container holds them now
-- (slot order). A snack still there keeps its coil, a new one takes the first free coil. Returns ids, shelf.
function M.assign(prevIds, items)
    local ids, shelf, present, placed = {}, {}, {}, {}
    for _, it in ipairs(items) do
        present[tonumber(it.id)] = it.uname
    end
    for c = 1, M.SLOTS do
        local id = type(prevIds) == "table" and tonumber(prevIds[c]) or 0
        if id and id > 0 and present[id] and not placed[id] then
            ids[c], shelf[c], placed[id] = id, present[id], true
        else
            ids[c], shelf[c] = 0, ""
        end
    end
    local free = 1
    for _, it in ipairs(items) do
        local id = tonumber(it.id)
        if id and not placed[id] then
            while free <= M.SLOTS and ids[free] ~= 0 do
                free = free + 1
            end
            if free > M.SLOTS then
                break
            end
            ids[free], shelf[free], placed[id] = id, it.uname, true
        end
    end
    return ids, shelf
end

-- a world point into machine space (machine at mx, my, mz turned rz degrees)
function M.toLocal(mx, my, mz, rz, x, y, z)
    local a = math.rad(-(rz or 0))
    local dx, dy = x - mx, y - my
    return dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a), z - mz
end

-- true when the segment a -> b (world) crosses the pane of a machine at mx, my, mz, rz from the front
function M.segmentHitsGlass(mx, my, mz, rz, ax, ay, az, bx, by, bz)
    local x0, y0, z0 = M.toLocal(mx, my, mz, rz, ax, ay, az)
    local x1, y1, z1 = M.toLocal(mx, my, mz, rz, bx, by, bz)
    if y0 > M.GLASS_Y or y1 < M.GLASS_Y - 0.05 then -- starts behind the pane, or stops short of it
        return false
    end
    local t = (y1 == y0) and 0 or (M.GLASS_Y - y0) / (y1 - y0)
    if t < 0 or t > 1.05 then
        return false
    end
    local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
    local w = M.WINDOW
    return x >= w.x0 and x <= w.x1 and z >= w.z0 and z <= w.z1
end

-- true when a player at (px, py) facing prz degrees stands in front of the machine's glass within reach of a swing
function M.inSwingReach(mx, my, mz, rz, px, py, pz, prz)
    local x, y, z = M.toLocal(mx, my, mz, rz, px, py, pz)
    if y > M.GLASS_Y or y < M.GLASS_Y - 1.3 or x < M.WINDOW.x0 - 0.35 or x > M.WINDOW.x1 + 0.35 then
        return false
    end
    if z < -1.0 or z > 2.5 then
        return false
    end
    -- the player faces the machine: their heading within 60 degrees of the machine's back (+Y in machine space)
    local face = ((prz or 0) - (rz or 0)) % 360
    return face <= 60 or face >= 300
end

return M
