local wound = {}
wound.DEFAULT_RANGE = 35
wound.RANGE_TOLERANCE = 5
wound.FIST_BLEED = 0.001
wound.RANGE = {
    [0] = 2, -- melee: upstream 2.0 m cone
    [22] = 35,
    [23] = 35,
    [24] = 35, -- pistols
    [25] = 40,
    [26] = 40,
    [27] = 40, -- shotguns
    [28] = 45,
    [29] = 45,
    [32] = 45, -- SMGs (MP5 = 29)
    [30] = 70, -- AK-47
    [31] = 90, -- M4
    [33] = 100, -- country rifle
    [34] = 320, -- sniper
    [38] = 75, -- minigun
}
-- vanilla GTA melee weapons (1..15: knuckles, knife, bat, katana, ...) share the melee cone
for id = 1, 15 do
    wound.RANGE[id] = wound.RANGE[0]
end
local KNOCK = { [3] = 1.0, [4] = 1.2, [5] = 0.9, [6] = 0.9, [7] = 0.8, [8] = 0.8, [9] = 9.9 }
local CAUSES =
    { [54] = "fall", [53] = "drowned", [37] = "burned", [51] = "explosion", [49] = "vehicle", [50] = "vehicle" }

function wound.range(weaponId)
    return wound.RANGE[weaponId] or wound.DEFAULT_RANGE
end

function wound.inRange(weaponId, dist)
    return dist <= wound.range(weaponId) + wound.RANGE_TOLERANCE
end

-- GTA melee weapon ids (fist 0 and vanilla melee 1..15)
function wound.isMeleeWeapon(weaponId)
    return weaponId >= 0 and weaponId <= 15
end

function wound.cooldown(weaponId)
    return weaponId == 24 and 790 or 100
end

-- upstream damage-firearm.pwn: v = muzzleVel - dist^(1 - muzzleVel/11300)
--   bleed = calibreBleed * v/1000 * ammoBleedMult
function wound.firearm(muzzleVelocity, distance, calibreBleed, ammoBleedMult)
    local v = muzzleVelocity - math.max(0, distance) ^ (1 - muzzleVelocity / 11300)
    if v ~= v or v < 0 then
        v = 0
    end
    return calibreBleed * v / 1000 * (ammoBleedMult or 1.0)
end

function wound.bodypartKnock(bodypart)
    return KNOCK[bodypart] or 1.0
end

-- MVP: knockouts are post-MVP, so a headshot doubles bleed instead
function wound.bodypartBleed(bleed, bodypart)
    return bodypart == 9 and bleed * 2 or bleed
end

function wound.hpLoss(bleed)
    return bleed * 100
end

-- returns hpLoss, bleedAdd for damage without a player attacker
function wound.environmental(weaponId, loss)
    if weaponId == 54 then
        return math.min(loss, 30) * 0.5, loss * 2.5 * 0.00024
    end
    if weaponId == 53 then
        return math.min(loss, 10), 0
    end
    if weaponId == 37 then
        return loss * 0.1, 0
    end
    if weaponId == 51 then
        local bleed = 0.5 * (loss / 80)
        return wound.hpLoss(bleed), bleed
    end
    if weaponId == 49 or weaponId == 50 then
        local bleed = 0.04 * (loss * 0.02)
        return wound.hpLoss(bleed), bleed
    end
    return math.min(loss, 20), 0
end

-- damage types that no held item can justify (fall, drown, fire, explosion, vehicle)
function wound.isEnvironmental(weaponId)
    return CAUSES[weaponId] ~= nil
end

function wound.cause(weaponId)
    return CAUSES[weaponId] or "killed"
end

return wound
