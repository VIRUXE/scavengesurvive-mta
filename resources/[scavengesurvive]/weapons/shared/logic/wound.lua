local wound = {}
wound.DEFAULT_RANGE = 35
wound.RANGE_TOLERANCE = 5
wound.FIST_BLEED = 0.001
wound.FIST_KNOCK = 0.5
wound.MAX_KNOCKOUT_MS = 120000
wound.MIN_KNOCKOUT_MS = 1500
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
-- the weapon ids an explosion reaches onClientPlayerDamage with: MTA passes 16 (grenade) or 19 (rocket) for a
-- createExplosion with no creator, the explosives resource's case (live 2026-10-30), not SA-MP's 51
local EXPLOSIONS = { [16] = true, [19] = true, [35] = true, [36] = true, [39] = true, [51] = true }

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
--   knockMult = (v/50) * ammoKoMult
function wound.firearmVelocity(muzzleVelocity, distance)
    local v = muzzleVelocity - math.max(0, distance) ^ (1 - muzzleVelocity / 11300)
    if v ~= v or v < 0 then
        v = 0
    end
    return v
end

function wound.firearm(muzzleVelocity, distance, calibreBleed, ammoBleedMult)
    return calibreBleed * wound.firearmVelocity(muzzleVelocity, distance) / 1000 * (ammoBleedMult or 1.0)
end

function wound.firearmKnock(muzzleVelocity, distance, ammoKoMult)
    return (wound.firearmVelocity(muzzleVelocity, distance) / 50.0) * (ammoKoMult or 1.0)
end

function wound.bodypartKnock(bodypart)
    return KNOCK[bodypart] or 1.0
end

-- upstream damage.pwn:141, 208
function wound.knockoutChance(knockMult, bodypart, woundCount, totalBleedRate)
    local km = (tonumber(knockMult) or 0) * wound.bodypartKnock(bodypart)
    return km * ((((tonumber(woundCount) or 0) + 1) * 0.2) * (((tonumber(totalBleedRate) or 0) * 50) + 1))
end

-- upstream damage.pwn:148-153
function wound.knockoutDuration(knockMult, bodypart, woundCount, totalBleedRate, hp)
    local km = (tonumber(knockMult) or 0) * wound.bodypartKnock(bodypart)
    local wc = (tonumber(woundCount) or 0) + 1
    local tb = tonumber(totalBleedRate) or 0
    local remHp = math.max(0, 110.0 - (tonumber(hp) or 100.0))
    local ms = math.floor((km * 0.2) * (wc * ((tb * 10) + 1) * remHp + (200 * remHp)) + 0.5)
    if ms <= wound.MIN_KNOCKOUT_MS then
        return 0
    end
    return math.min(wound.MAX_KNOCKOUT_MS, ms)
end

-- MVP: knockouts are post-MVP, so a headshot doubles bleed instead
function wound.bodypartBleed(bleed, bodypart)
    return bodypart == 9 and bleed * 2 or bleed
end

function wound.hpLoss(bleed)
    return bleed * 100
end

-- Damage no held item is behind: upstream damage-world.pwn (a fall 54, drowning 53, fire 37),
-- damage-vehicle.pwn (a ram 49, run over 50) and damage-explosive.pwn (51), each an OnPlayerTakeDamage hook.
-- Upstream wrote its own hp counter back over the player's health every update (player.pwn:403), so GTA's own
-- damage never counted there: these wounds were the whole effect. loss is GTA's health loss (upstream's amount),
-- ctx.velocity the ramming vehicle's speed from wound.velocity, ctx.bleedMult / ctx.knockMult the
-- vehicles.damage_* settings (upstream vehicle.damage/bleed-mult and knock-mult, 1.0), rnd draws in [0, 1).
-- Returns nil when nothing happens, else { hp, bleed, knockMult, knockoutMs, bodypart, cause }: hp and bleed make
-- the wound, knockMult feeds the wound's knockout roll, knockoutMs is a knockout of its own (drowning, a fast ram).
wound.FALL_MIN_LOSS = 10 -- damage-world.pwn:38: amount > 10.0
wound.RAM_KNOCK_VELOCITY = 55 -- damage-vehicle.pwn:57
wound.DROWN_MAX_HP = 10 -- port: GTA's drowning tick, capped (upstream's resync made drowning cost no hp)
wound.VELOCITY_SCALE = 150 -- player.pwn:383: |velocity| * 150, the km/h the speed readout shows

function wound.velocity(vx, vy, vz)
    vx, vy, vz = tonumber(vx) or 0, tonumber(vy) or 0, tonumber(vz) or 0
    return math.sqrt(vx * vx + vy * vy + vz * vz) * wound.VELOCITY_SCALE
end

-- random(2) ? BODY_PART_TORSO : (random(2) ? BODY_PART_RIGHT_LEG : BODY_PART_LEFT_LEG)
function wound.torsoOrLeg(rnd)
    if rnd() < 0.5 then
        return 3
    end
    return rnd() < 0.5 and 8 or 7
end

function wound.nonFirearm(weaponId, loss, ctx, rnd)
    rnd = rnd or math.random
    weaponId = wound.isExplosion(weaponId) and 51 or weaponId
    ctx = ctx or {}
    loss = math.max(0, tonumber(loss) or 0)
    if weaponId == 54 then
        -- damage-world.pwn _DoFallDamage: a leg wound with chance multiplier % (multiplier = amount * 2.5)
        if loss <= wound.FALL_MIN_LOSS then
            return nil
        end
        local mult = loss * 2.5
        if rnd() * 100 >= mult then
            return nil
        end
        local bleed = mult > 1.0 and mult * 0.00024 or 0
        return {
            hp = wound.hpLoss(bleed),
            bleed = bleed,
            knockMult = mult * 0.9,
            bodypart = rnd() < 0.5 and 7 or 8,
            cause = "fall",
        }
    elseif weaponId == 53 then
        -- damage-world.pwn: KnockOutPlayer(1500 + random(1500)) and no wound; the port keeps GTA's drowning hp loss
        return {
            hp = math.min(loss, wound.DROWN_MAX_HP),
            bleed = 0,
            knockoutMs = 1500 + math.floor(rnd() * 1500),
            bodypart = 3,
            cause = "drowned",
        }
    elseif weaponId == 37 then
        -- damage-world.pwn: GivePlayerHP(-(amount * 0.1))
        return { hp = loss * 0.1, bleed = 0, bodypart = 3, cause = "burned" }
    elseif weaponId == 49 or weaponId == 50 then
        -- damage-vehicle.pwn _DoVehicleCollisionDamage: bleed from the driver's speed, a knockout past 55 km/h
        local v = math.max(0, tonumber(ctx.velocity) or 0)
        local bleed = (0.04 * (v * 0.02)) * (tonumber(ctx.bleedMult) or 1.0)
        local koMs = 0
        if v > wound.RAM_KNOCK_VELOCITY and rnd() * v > wound.RAM_KNOCK_VELOCITY then
            koMs = math.floor((1000 + ((v * 0.05) * 1000)) * (tonumber(ctx.knockMult) or 1.0) + 0.5)
        end
        return {
            hp = wound.hpLoss(bleed),
            bleed = bleed,
            knockMult = 1.0,
            knockoutMs = koMs,
            bodypart = wound.torsoOrLeg(rnd),
            cause = "vehicle",
        }
    elseif weaponId == 51 then
        -- damage-explosive.pwn _DoExplosiveDamage: a burn wound, knockmult 150 + amount
        local bleed = 0.5 * (loss / 80.0)
        return {
            hp = wound.hpLoss(bleed),
            bleed = bleed,
            knockMult = 150.0 + loss,
            bodypart = wound.torsoOrLeg(rnd),
            cause = "explosion",
        }
    end
    -- anything else without a player behind it (upstream let GTA's damage vanish; the port takes it, capped)
    return { hp = math.min(loss, 20), bleed = 0, bodypart = 3, cause = "killed" }
end

-- damage types that no held item can justify (fall, drown, fire, explosion, vehicle)
-- The shield (upstream item/shield.pwn _HandleShieldHit): a Shield in the victim's hand stops shots coming from
-- their front (within SHIELD_FRONT degrees of where they face), one on their back (holstered) stops shots from
-- behind (within SHIELD_BACK of straight behind). The head is never covered, and the legs only when the shooter
-- crouches behind it. where = "held" | "holster"; facing = the victim's heading; (vx, vy) victim, (ax, ay) attacker.
wound.SHIELD_FRONT, wound.SHIELD_BACK = 45, 25

function wound.shieldBlocks(where, bodypart, attackerDucking, facing, vx, vy, ax, ay)
    if bodypart == 9 then
        return false
    end
    if (bodypart == 7 or bodypart == 8) and not attackerDucking then
        return false
    end
    local toAttacker = (-math.deg(math.atan2(ax - vx, ay - vy))) % 360
    local off = math.abs((((facing or 0) - toAttacker) + 180) % 360 - 180)
    if where == "held" then
        return off <= wound.SHIELD_FRONT
    elseif where == "holster" then
        return off >= 180 - wound.SHIELD_BACK
    end
    return false
end

-- What a body shows for a kill by a player with this weapon (upstream death.pwn's switch): the key of
-- character/shared/logic/bodies.lua REASONS, "killed" for anything else.
function wound.killCause(weaponId)
    local w = tonumber(weaponId) or -1
    if w == 4 then
        return "knife"
    elseif w == 8 then
        return "sword"
    elseif w == 9 then
        return "chainsaw"
    elseif w >= 0 and w <= 15 then
        return "beaten"
    elseif wound.isExplosion(w) then
        return "explosion"
    elseif w == 18 or w == 37 then
        return "burned"
    elseif (w >= 22 and w <= 34) or w == 38 then
        return "shot"
    elseif w == 41 or w == 42 then
        return "sprayed"
    elseif w == 43 then
        return "camera"
    elseif w == 44 or w == 45 then
        return "goggles"
    end
    return "killed"
end

function wound.isExplosion(weaponId)
    return EXPLOSIONS[weaponId] == true
end

function wound.isEnvironmental(weaponId)
    return CAUSES[weaponId] ~= nil
end

function wound.cause(weaponId)
    return CAUSES[weaponId] or "killed"
end

return wound
