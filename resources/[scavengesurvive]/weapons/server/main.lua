local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local wound
do
    local f = fileOpen("shared/logic/wound.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    wound = assert(loadstring(src, "=weapons/shared/logic/wound.lua"))()
end

local MAX_LOSS = 200
local typeCache = {}
local lastHit = {} -- lastHit[attacker][victim] = tick of the last accepted hit

local function itemType(uname)
    if typeCache[uname] == nil then
        typeCache[uname] = exports.data:itemType(uname) or false
    end
    return typeCache[uname] or nil
end

local function isPlayer(e)
    return isElement(e) and getElementType(e) == "player"
end

local function report(victim, bleed, hp, bodypart)
    triggerClientEvent(victim, "onClientWeaponsWound", victim, bleed, hp, bodypart)
end

local function environmental(victim, weapon, bodypart, loss)
    local hp, bleed = wound.environmental(weapon, loss)
    if hp <= 0 and bleed <= 0 then
        return
    end
    exports.character:applyWound(victim, bleed, hp, false, wound.cause(weapon))
    report(victim, bleed, hp, bodypart)
end

-- bleed for a player hit, or nil when the attacker's held item does not justify the reported weapon.
-- Three melee shapes exist in the converted item types:
--   * custom melee (Wrench, Crowbar, ...): melee = true, baseWeapon = 0, bleed in categoryData.bleed;
--     GTA reports weapon 0 (fist), so any fist hit while holding one uses its bleed;
--   * vanilla GTA melee (Knife, Bat, Katana, ... baseWeapon 1..15): upstream stores the bleed rate in
--     muzzleVelocity (knockout in magSize) with melee = false and calibre = nil; GTA reports the
--     baseWeapon id, so they are matched like a firearm (getPedWeapon == baseWeapon == weapon) but take
--     the melee bleed path (no distance falloff);
--   * firearms: calibre bleed x muzzle-velocity falloff over distance.
local function hitBleed(attacker, weapon, dist)
    local held = exports.items:getHeld(attacker)
    local t = held and itemType(held.uname)
    local cd = t and t.category == "weapon" and t.categoryData or nil
    if weapon == 0 then
        if cd and cd.melee then
            return cd.bleed
        end
        return wound.FIST_BLEED
    end
    if not cd or cd.melee or cd.baseWeapon ~= weapon then
        return nil
    end
    if wound.isMeleeWeapon(weapon) then
        return cd.muzzleVelocity
    end
    local calibreBleed = exports.data:calibreBleed(cd.calibre) or 0.25
    return wound.firearm(cd.muzzleVelocity, dist, calibreBleed, 1.0)
end

net.handler("onWeaponsRequestHit", function(victim, attacker, weapon, bodypart, loss)
    weapon, bodypart, loss = tonumber(weapon), tonumber(bodypart) or 3, tonumber(loss) or 0
    if not weapon or loss < 0 or loss > MAX_LOSS then
        return
    end
    if not exports.character:getCharacterId(victim) or isPedDead(victim) then
        return
    end
    -- vehicle rams / explosions / fire can name a player attacker, but no held item can justify them:
    -- treat them as environmental (only hurts the reporter, no kill credit)
    if not isPlayer(attacker) or attacker == victim or wound.isEnvironmental(weapon) then
        return environmental(victim, weapon, bodypart, loss)
    end
    if not exports.character:getCharacterId(attacker) or isPedDead(attacker) then
        return
    end
    if getElementDimension(attacker) ~= getElementDimension(victim) then
        return
    end

    local now = getTickCount()
    local pairs_ = lastHit[attacker]
    if not pairs_ then
        pairs_ = {}
        lastHit[attacker] = pairs_
    end
    if pairs_[victim] and now - pairs_[victim] < wound.cooldown(weapon) then
        return
    end

    local ax, ay, az = getElementPosition(attacker)
    local vx, vy, vz = getElementPosition(victim)
    local dist = getDistanceBetweenPoints3D(ax, ay, az, vx, vy, vz)
    if not wound.inRange(weapon, dist) then
        return util.log(
            "weapons",
            "warn",
            "%s reported hit by %s weapon %d at %.1f m (range %d)",
            getPlayerName(victim),
            getPlayerName(attacker),
            weapon,
            dist,
            wound.range(weapon)
        )
    end
    if weapon > 0 and getPedWeapon(attacker) ~= weapon then
        return
    end

    local bleed = hitBleed(attacker, weapon, dist)
    if not bleed or bleed <= 0 then
        return
    end
    pairs_[victim] = now
    bleed = wound.bodypartBleed(bleed, bodypart)
    local hp = wound.hpLoss(bleed)
    exports.character:applyWound(victim, bleed, hp, attacker, "killed")
    report(victim, bleed, hp, bodypart)
    util.log(
        "weapons",
        "info",
        "%s hit %s weapon %d part %d dist %.1f bleed %.4f hp %.1f",
        getPlayerName(attacker),
        getPlayerName(victim),
        weapon,
        bodypart,
        dist,
        bleed,
        hp
    )
end, { rate = 15 })

addEventHandler("onPlayerQuit", root, function()
    lastHit[source] = nil
    for _, victims in pairs(lastHit) do
        victims[source] = nil
    end
end)
