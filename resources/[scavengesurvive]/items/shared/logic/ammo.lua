-- Pure ammo, magazine, reload, unload, loot-roll and display-name logic.
-- Mirrors ../ScavengeSurvive/gamemodes/sss/core/weapon/{weapon,ammunition,loot,interact}.pwn.
local Ammo = {}

local MILITARY_LOOT = {
    world_police = true,
    world_military = true,
    vehicle_police = true,
    vehicle_military = true,
    airdrop_low_weapons = true,
    airdrop_military_weapons = true,
}

function Ammo.isCalibreWeapon(def)
    if type(def) ~= "table" or def.category ~= "weapon" or type(def.categoryData) ~= "table" then
        return false
    end
    return def.categoryData.calibre ~= nil and not def.categoryData.liquid
end

function Ammo.isAmmoItem(def)
    if type(def) ~= "table" or def.category ~= "ammo" or type(def.categoryData) ~= "table" then
        return false
    end
    return def.categoryData.calibre ~= nil
end

function Ammo.weaponState(def, data, defaultAmmo)
    if not Ammo.isCalibreWeapon(def) then
        return { mag = 0, reserve = 0, ammoItem = nil }
    end
    local cd = def.categoryData
    local magSize = math.max(0, math.floor(tonumber(cd.magSize) or 0))
    local maxReserveMags = math.max(0, math.floor(tonumber(cd.maxReserveMags) or 0))
    local maxReserve = magSize * maxReserveMags

    -- Backwards compatibility: items created without explicit mag data (e.g. /additem or legacy rows)
    -- default to a full magazine of the calibre's primary ammo type.
    if type(data) ~= "table" or data.mag == nil then
        return {
            mag = magSize,
            reserve = 0,
            ammoItem = magSize > 0 and defaultAmmo or nil,
        }
    end

    local mag = math.max(0, math.min(magSize, math.floor(tonumber(data.mag) or 0)))
    local reserve = math.max(0, math.min(maxReserve, math.floor(tonumber(data.reserve) or 0)))
    local ammoItem = nil
    if mag > 0 or reserve > 0 then
        ammoItem = (type(data.ammoItem) == "string" and data.ammoItem ~= "" and data.ammoItem) or defaultAmmo
    end
    return {
        mag = mag,
        reserve = reserve,
        ammoItem = ammoItem,
    }
end

function Ammo.ammoRounds(def, data)
    if not Ammo.isAmmoItem(def) then
        return 0
    end
    local cap = math.max(0, math.floor(tonumber(def.categoryData.rounds) or 0))
    if type(data) ~= "table" or data.rounds == nil then
        return cap
    end
    return math.max(0, math.floor(tonumber(data.rounds) or 0))
end

function Ammo.rollLootData(def, lootIndex, ammoTypes, rand)
    local rng = rand or math.random
    if Ammo.isAmmoItem(def) then
        local cap = math.max(1, math.floor(tonumber(def.categoryData.rounds) or 1))
        local rounds = cap <= 1 and 1 or rng(1, cap - 1)
        return { rounds = rounds }
    end
    if Ammo.isCalibreWeapon(def) then
        local magSize = math.max(0, math.floor(tonumber(def.categoryData.magSize) or 0))
        -- upstream's random(magsize) never loads a one-round gun (Model 70, M77-RM, ...): those get a coin flip
        local function partial()
            return magSize > 1 and rng(0, magSize - 1) or (magSize == 1 and rng(0, 1)) or 0
        end
        local mag
        if MILITARY_LOOT[lootIndex] then
            local r = rng(0, 99)
            if r < 30 then
                mag = 0
            elseif r < 50 then
                mag = partial()
            else
                mag = magSize
            end
        else
            mag = partial()
        end
        local ammoItem = nil
        if mag > 0 and type(ammoTypes) == "table" and #ammoTypes > 0 then
            ammoItem = ammoTypes[rng(1, #ammoTypes)]
        else
            mag = 0
        end
        return { mag = mag, reserve = 0, ammoItem = ammoItem }
    end
    return nil
end

function Ammo.reload(def, data, defaultAmmo)
    local state = Ammo.weaponState(def, data, defaultAmmo)
    if not Ammo.isCalibreWeapon(def) then
        return false, state, 0
    end
    local magSize = math.max(0, math.floor(tonumber(def.categoryData.magSize) or 0))
    local need = magSize - state.mag
    if need <= 0 or state.reserve <= 0 then
        return false, state, 0
    end
    local moved = math.min(need, state.reserve)
    local nextState = {
        mag = state.mag + moved,
        reserve = state.reserve - moved,
        ammoItem = state.ammoItem,
    }
    return true, nextState, moved
end

function Ammo.fire(def, data, defaultAmmo)
    local state = Ammo.weaponState(def, data, defaultAmmo)
    if not Ammo.isCalibreWeapon(def) or state.mag <= 0 then
        return false, state, false
    end
    state.mag = state.mag - 1
    local autoReloaded = false
    if state.mag == 0 and state.reserve > 0 then
        autoReloaded, state = Ammo.reload(def, state, defaultAmmo)
    end
    if state.mag == 0 and state.reserve == 0 then
        state.ammoItem = nil
    end
    return true, state, autoReloaded
end

function Ammo.unload(def, data, defaultAmmo)
    if not Ammo.isCalibreWeapon(def) then
        return false, "INVALID"
    end
    local state = Ammo.weaponState(def, data, defaultAmmo)
    local total = state.mag + state.reserve
    if total <= 0 or not state.ammoItem then
        return false, "WEAPAUNLOAD"
    end
    return true, { mag = 0, reserve = 0, ammoItem = nil }, { uname = state.ammoItem, data = { rounds = total } }
end

function Ammo.transfer(srcDef, srcData, dstDef, dstData, defaultAmmo)
    local srcIsWep = Ammo.isCalibreWeapon(srcDef)
    local srcIsAmmo = Ammo.isAmmoItem(srcDef)
    local dstIsWep = Ammo.isCalibreWeapon(dstDef)
    local dstIsAmmo = Ammo.isAmmoItem(dstDef)
    if (not srcIsWep and not srcIsAmmo) or (not dstIsWep and not dstIsAmmo) then
        return false, "INVALID"
    end
    if srcDef.categoryData.noTransfer or dstDef.categoryData.noTransfer then
        return false, "NOTRANSFER"
    end
    if srcDef.categoryData.calibre ~= dstDef.categoryData.calibre then
        return false, "AMWRONGCALI"
    end

    if srcIsAmmo and dstIsWep then
        local srcRounds = Ammo.ammoRounds(srcDef, srcData)
        local dstState = Ammo.weaponState(dstDef, dstData, defaultAmmo)
        local dstTotal = dstState.mag + dstState.reserve
        if dstTotal > 0 and dstState.ammoItem and dstState.ammoItem ~= srcDef.uname then
            return false, "AMDIFFATYPE"
        end
        local magSize = math.max(0, math.floor(tonumber(dstDef.categoryData.magSize) or 0))
        local maxReserve = magSize * math.max(0, math.floor(tonumber(dstDef.categoryData.maxReserveMags) or 0))
        local toMag = math.min(srcRounds, math.max(0, magSize - dstState.mag))
        local rem = srcRounds - toMag
        local toRes = math.min(rem, math.max(0, maxReserve - dstState.reserve))
        local moved = toMag + toRes
        local nextDst = {
            mag = dstState.mag + toMag,
            reserve = dstState.reserve + toRes,
            ammoItem = (dstTotal + moved > 0) and srcDef.uname or nil,
        }
        return true, "AMTRANS", { rounds = srcRounds - moved }, nextDst, moved
    end

    if srcIsAmmo and dstIsAmmo then
        if srcDef.uname ~= dstDef.uname then
            return false, "AMMIXINTINS"
        end
        local srcRounds = Ammo.ammoRounds(srcDef, srcData)
        local dstRounds = Ammo.ammoRounds(dstDef, dstData)
        local moved = srcRounds
        return true, "AMTRANS", { rounds = 0 }, { rounds = dstRounds + moved }, moved
    end

    if srcIsWep and dstIsAmmo then
        local srcState = Ammo.weaponState(srcDef, srcData, defaultAmmo)
        local srcTotal = srcState.mag + srcState.reserve
        if srcTotal > 0 and srcState.ammoItem and srcState.ammoItem ~= dstDef.uname then
            return false, "AMDIFFATYPE"
        end
        local dstRounds = Ammo.ammoRounds(dstDef, dstData)
        local moved = srcTotal
        local nextSrc = { mag = 0, reserve = 0, ammoItem = nil }
        local nextDst = { rounds = dstRounds + moved }
        return true, "AMTRANS", nextSrc, nextDst, moved
    end

    if srcIsWep and dstIsWep then
        local srcState = Ammo.weaponState(srcDef, srcData, defaultAmmo)
        local dstState = Ammo.weaponState(dstDef, dstData, defaultAmmo)
        local srcTotal = srcState.mag + srcState.reserve
        local dstTotal = dstState.mag + dstState.reserve
        if srcTotal <= 0 or not srcState.ammoItem then
            return true, "AMTRANS", srcState, dstState, 0
        end
        if dstTotal > 0 and dstState.ammoItem and dstState.ammoItem ~= srcState.ammoItem then
            return false, "AMDIFFATYPE"
        end
        local dstMagSize = math.max(0, math.floor(tonumber(dstDef.categoryData.magSize) or 0))
        local dstMaxRes = dstMagSize * math.max(0, math.floor(tonumber(dstDef.categoryData.maxReserveMags) or 0))
        local dstCap = dstMagSize + dstMaxRes
        local moved = math.min(srcTotal, math.max(0, dstCap - dstTotal))
        local newSrcTotal = srcTotal - moved
        local newDstTotal = dstTotal + moved
        local srcMagSize = math.max(0, math.floor(tonumber(srcDef.categoryData.magSize) or 0))
        local newSrcMag = math.min(srcMagSize, newSrcTotal)
        local newDstMag = math.min(dstMagSize, newDstTotal)
        local ammoType = srcState.ammoItem
        local nextSrc = {
            mag = newSrcMag,
            reserve = newSrcTotal - newSrcMag,
            ammoItem = newSrcTotal > 0 and ammoType or nil,
        }
        local nextDst = {
            mag = newDstMag,
            reserve = newDstTotal - newDstMag,
            ammoItem = newDstTotal > 0 and (dstState.ammoItem or ammoType) or nil,
        }
        return true, "AMTRANS", nextSrc, nextDst, moved
    end

    return false, "INVALID"
end

-- Routes interaction between a held item and a world item following core/weapon/interact.pwn:
-- holding a weapon pulls ammo from a world weapon or world ammo tin into the held weapon;
-- holding an ammo tin pulls ammo from a world weapon or world ammo tin into the held tin.
-- Returns ok, code, nextHeldData, nextWorldData, moved, deleteWorldItem, deleteHeldItem
function Ammo.interactTransfer(heldDef, heldData, worldDef, worldData, defaultAmmo)
    local ok, code, nextWorld, nextHeld, moved = Ammo.transfer(worldDef, worldData, heldDef, heldData, defaultAmmo)
    if not ok then
        return false, code
    end
    local delWorld = Ammo.isAmmoItem(worldDef) and (nextWorld.rounds or 0) <= 0
    return true, code, nextHeld, nextWorld, moved, delWorld, false
end

function Ammo.displayName(def, data, resolveItemType, resolveCalibreName, defaultAmmo)
    if type(def) ~= "table" then
        return ""
    end
    if Ammo.isCalibreWeapon(def) then
        local cal = def.categoryData.calibre
        local calName = (resolveCalibreName and resolveCalibreName(cal)) or cal
        local state = Ammo.weaponState(def, data, defaultAmmo)
        local ammoLabel = "Unloaded"
        if state.ammoItem and resolveItemType then
            local ammoDef = resolveItemType(state.ammoItem)
            if ammoDef then
                ammoLabel = (ammoDef.categoryData and ammoDef.categoryData.name) or ammoDef.name or ammoLabel
            end
        end
        return string.format("%s (%d/%d, %s, %s)", def.name, state.mag, state.reserve, calName, ammoLabel)
    end
    if Ammo.isAmmoItem(def) then
        local cal = def.categoryData.calibre
        local calName = (resolveCalibreName and resolveCalibreName(cal)) or cal
        local rounds = Ammo.ammoRounds(def, data)
        local kind = def.categoryData.name or def.name
        return string.format("%s (%d, %s, %s)", def.name, rounds, calName, kind)
    end
    return def.name or def.uname or ""
end

function Ammo.encodeData(data)
    if type(data) ~= "table" then
        return nil
    end
    if data.rounds ~= nil then
        return string.format('{"rounds":%d}', math.max(0, math.floor(tonumber(data.rounds) or 0)))
    end
    if data.mag ~= nil then
        local mag = math.max(0, math.floor(tonumber(data.mag) or 0))
        local res = math.max(0, math.floor(tonumber(data.reserve) or 0))
        if type(data.ammoItem) == "string" and data.ammoItem ~= "" then
            return string.format('{"mag":%d,"reserve":%d,"ammoItem":%q}', mag, res, data.ammoItem)
        end
        return string.format('{"mag":%d,"reserve":%d}', mag, res)
    end
    return nil
end

return Ammo
