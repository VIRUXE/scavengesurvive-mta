-- Furniture (upstream core/itemtype/furniture.pwn with init.pwn:1289-1290 and 1311-1316, #148): six item types built
-- by construction recipes that are never picked up. An item used on a Desk, Table, Barstool or Small Table is put on
-- top of it; a Gun Case or Cupboard (a safebox whose dialog never shows) holds one item, shows it lying in the case
-- and gives it back to an empty hand. The shown item's type is the case's item data { display = uname }. Pure: no
-- MTA calls at file scope.
local M = {}

-- DefineItemTypeFurniture(type, px, py, pz, rx, ry, rz); display: DefineSafeboxType(type, 5, false, false)
M.TYPES = {
    Desk = { z = 0.80 },
    Table = { z = 0.80 },
    GunCase = { z = 0.25, rx = -90, ry = -90, display = true },
    Cupboard = { z = 0.35, rx = -90, ry = -90, display = true },
    Barstool = { z = 0.48 },
    SmallTable = { z = 0.45 },
}
M.DISPLAY_SIZE = 5
M.ON_TOP_REACH = 0.6 -- metres from the furniture's centre an item still counts as lying on it
M.TEXT = { CNTEXTRASLO = "Extra %d slots required" }

function M.is(uname)
    return M.TYPES[uname] ~= nil
end

function M.isDisplay(uname)
    local f = M.TYPES[uname]
    return f ~= nil and f.display == true
end

-- every furniture type, sorted (for SQL lists)
function M.unames()
    local list = {}
    for uname in pairs(M.TYPES) do
        list[#list + 1] = uname
    end
    table.sort(list)
    return list
end

-- where an item put on a furniture row lies: the furniture's position raised by its offset, its heading kept
-- (CreateItemInWorld(itemid, x + px, y + py, z + pz, rx, ry, rz); every upstream x/y offset is 0)
function M.onTop(row)
    local f = M.TYPES[row.uname]
    return row.x, row.y, (row.z or 0) + (f and f.z or 0), row.rz or 0
end

-- the shown item's type in a case's item data, either JSON shape; nil when the case is empty
function M.display(data)
    if type(data) ~= "table" then
        return nil
    end
    local d = data.display
    if d == nil and type(data[1]) == "table" then
        d = data[1].display
    end
    return type(d) == "string" and d ~= "" and d or nil
end

-- The shown item's object in a case: caseType / shownType are item type rows (rotx/roty/rotz). Upstream adds the
-- case's offset to its own position and rotation, then the shown type's rotation (GetItemTypeRotation); it swaps
-- the x and y rotation offsets, which changes nothing since both are -90. x, y, z, rx, ry, rz.
function M.displayPose(row, caseType, shownType)
    local f = M.TYPES[row.uname] or {}
    local rx = (f.rx or 0) + (shownType and shownType.rotx or 0)
    local ry = (f.ry or 0) + (shownType and shownType.roty or 0)
    local rz = (row.rz or 0) + (caseType and caseType.rotz or 0) + (shownType and shownType.rotz or 0)
    return row.x, row.y, (row.z or 0) + (f.z or 0), rx, ry, rz % 360
end

return M
