-- Pure logic for explosives (presets, distance, damage, arming rules).
-- Ported from upstream Scavenge & Survive (gamemodes/sss/core/world/explosive.pwn).
local M = {}

-- Upstream presets: gamemodes/sss/core/world/explosive.pwn:47-56
-- { exp_type, Float:exp_size, exp_itemDmg }
M.PRESETS = {
    -- explosive.pwn:49: {12, 3.0, 1} // EXP_SMALL
    SMALL = { anim = 12, size = 3.0, itemDmg = 1 },
    -- explosive.pwn:50: {00, 8.0, 2} // EXP_MEDIUM
    MEDIUM = { anim = 0, size = 8.0, itemDmg = 2 },
    -- explosive.pwn:51: {06, 24.0, 3} // EXP_LARGE
    LARGE = { anim = 6, size = 24.0, itemDmg = 3 },
    -- explosive.pwn:52: {02, 5.0, 0} // EXP_INCEN - large fire anim from explosion
    INCEN = { anim = 2, size = 5.0, itemDmg = 0, unimplemented = true },
    -- explosive.pwn:53: {04, 8.0, 0} // EXP_THERM - fire anim from explosion combined with prt
    THERM = { anim = 4, size = 8.0, itemDmg = 0, unimplemented = true },
    -- explosive.pwn:54: {00, 12.0, 0} // EXP_EMP - no exp anim or fire, prt used
    EMP = { anim = 0, size = 12.0, itemDmg = 0, emp = true, knockoutMs = 60000 },
    -- explosive.pwn:55: {12, 10.0, 0} // EXP_SHRAP - knockout range small, bleed range large
    SHRAP = {
        anim = 12,
        size = 10.0,
        itemDmg = 0,
        shrapnel = true,
        knockRange = 3.0,
        knockDurationMs = 3000,
        bleedRange = 10.0,
        bleedRate = 0.005,
        hpLoss = 25.0,
    },
}

-- Upstream trigger types: gamemodes/sss/core/world/explosive.pwn:22-28 (enum EXP_TRIGGER)
M.TRIGGERS = {
    TIMED = "TIMED",
    RADIO = "RADIO",
    PROXIMITY = "PROXIMITY",
    MOTION = "MOTION",
}

-- Upstream arming hold time: explosive.pwn:199, 208, 217 (StartHoldAction(playerid, 1000))
M.ARM_HOLD_MS = 1000

-- Upstream timed fuse delay: explosive.pwn:307 (defer SetItemToExplodeDelay(_:exp_ArmingItem[playerid], 5000))
M.TIMED_FUSE_MS = 5000

-- Upstream proximity mine arm delay: explosive.pwn:317, 349 (timer CreateTntMineProx[5000])
M.PROX_ARM_DELAY_MS = 5000

-- Upstream proximity detection radius: explosive.pwn:362 (CreateDynamicSphere(x, y, z, 6.0))
M.PROX_RADIUS = 6.0

-- Upstream proximity trigger delay: explosive.pwn:411 (defer SetItemToExplodeDelay(_:itemid, 1000))
M.PROX_TRIGGER_DELAY_MS = 1000

-- Upstream radio trigger debounce: explosive.pwn:227
-- (GetTickCountDifference(GetTickCount(), exp_ArmTick[playerid]) < 1000)
M.RADIO_DEBOUNCE_MS = 1000

-- Upstream radio trigger item: gamemodes/sss/core/server/init.pwn:1230 (SetRadioExplosiveTriggerItem(item_MobilePhone))
M.RADIO_TRIGGER_ITEM = "MobilePhone"

-- Upstream EMP visual object model: explosive.pwn:585
-- (CreateTimedDynamicObject(18724, x, y, z - 1.0, 0.0, 0.0, 0.0, 3000))
M.EMP_OBJECT_MODEL = 18724

-- Upstream EMP visual lifetime: explosive.pwn:585 (3000 ms)
M.EMP_OBJECT_LIFETIME_MS = 3000

-- Upstream EMP player knockout duration: explosive.pwn:591 (KnockOutPlayer(i, 60000))
M.EMP_KNOCKOUT_MS = 60000

function M.getPreset(presetName)
    if not presetName then
        return nil
    end
    return M.PRESETS[presetName]
end

function M.isItemInRange(ix, iy, iz, ex, ey, ez, range)
    if not ix or not iy or not iz or not ex or not ey or not ez or not range then
        return false
    end
    local dx = ix - ex
    local dy = iy - ey
    local dz = iz - ez
    return (dx * dx + dy * dy + dz * dz) <= (range * range)
end

function M.filterItemsInRange(items, ex, ey, ez, range, interior, dimension)
    local out = {}
    if type(items) ~= "table" then
        return out
    end
    interior = interior or 0
    dimension = dimension or 0
    for _, it in ipairs(items) do
        local itInt = it.interior or 0
        local itDim = it.dimension or 0
        if itInt == interior and itDim == dimension then
            if M.isItemInRange(it.x, it.y, it.z, ex, ey, ez, range) then
                out[#out + 1] = it
            end
        end
    end
    return out
end

-- Port change: upstream takes the preset's full itemDmg off every item in range (explosive.pwn:599). Here it falls
-- off linearly with the distance from the blast to the item's origin, rounded up, so a stack loses the most at the
-- charge and still at least 1 hitpoint anywhere inside the range; nothing outside it.
function M.itemDamageAt(itemDmg, dist, range)
    itemDmg, dist, range = tonumber(itemDmg) or 0, tonumber(dist) or 0, tonumber(range) or 0
    if itemDmg <= 0 or range <= 0 or dist > range then
        return 0
    end
    return math.max(1, math.ceil(itemDmg * (1 - dist / range)))
end

function M.calculateItemDamage(items, itemDmg)
    local destroyed = {}
    local damaged = {}
    if type(items) ~= "table" or (tonumber(itemDmg) or 0) <= 0 then
        return destroyed, damaged
    end
    itemDmg = tonumber(itemDmg)
    for _, it in ipairs(items) do
        local curHp = tonumber(it.hitpoints or it.hp) or 0
        local remaining = curHp - itemDmg
        if remaining <= 0 then
            destroyed[#destroyed + 1] = {
                id = it.id,
                uname = it.type_uname or it.uname,
                x = it.x,
                y = it.y,
                z = it.z,
                rz = it.rz,
                data = it.data,
            }
        else
            damaged[#damaged + 1] = {
                id = it.id,
                hp = remaining,
            }
        end
    end
    return destroyed, damaged
end

function M.canRadioDetonate(phoneData, bombRow, bombType)
    if type(phoneData) ~= "table" or not phoneData.bombId then
        return false, "RADIONOSYNC"
    end
    if not bombRow or not bombType then
        return false, "RADIONOSYNC"
    end
    if tonumber(bombRow.id) ~= tonumber(phoneData.bombId) then
        return false, "RADIONOSYNC"
    end
    local exp = bombType.explosive
    if not exp or exp.trigger ~= M.TRIGGERS.RADIO then
        return false, "RADIONOSYNC"
    end
    local bData = bombRow.data
    if type(bData) ~= "table" or bData.armed ~= 1 then
        return false, "RADIONOSYNC"
    end
    return true
end

function M.isArmedTripMine(itemType, itemData)
    if not itemType or not itemType.explosive then
        return false
    end
    if itemType.explosive.trigger ~= M.TRIGGERS.MOTION then
        return false
    end
    return type(itemData) == "table" and itemData.armed == 1
end

function M.findArmedTripMine(items, itemTypeFn)
    if type(items) ~= "table" or type(itemTypeFn) ~= "function" then
        return nil
    end
    for _, it in ipairs(items) do
        local t = itemTypeFn(it.type_uname or it.uname)
        if M.isArmedTripMine(t, it.data) then
            return it
        end
    end
    return nil
end

return M
