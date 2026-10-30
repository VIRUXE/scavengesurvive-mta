local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
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
local settings = {} -- gamemode settings map (db.settings): vehicles.damage_bleed_mult, vehicles.damage_knock_mult

addEventHandler("onResourceStart", resourceRoot, function()
    if db.connect("weapons") then
        db.settings(function(map)
            settings = map
        end)
    end
end)

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
    triggerClientEvent(victim, "woundInflicted", victim, bleed, hp, bodypart)
end

-- the wound's knockout roll (upstream damage.pwn:130-153) from the stats after the wound: the body part scales
-- knockMult, a hat softens a headshot's chance, duration and chance grow with the wound count and the total bleed
local function rollKnockout(victim, knockMult, bodypart)
    knockMult = tonumber(knockMult) or 0
    if knockMult <= 0 then
        return
    end
    local st = exports.character:getStats(victim)
    if not st or st.hp <= 0 then
        return
    end
    local km = knockMult
    if bodypart == 9 and getElementData(victim, "items.hat") then
        km = km * 0.4
    end
    local chance = wound.knockoutChance(km, bodypart, st.wounds, st.bleed)
    if math.random() * 100 < chance then
        local koMs = wound.knockoutDuration(knockMult, bodypart, st.wounds, st.bleed, st.hp)
        if koMs > 0 then
            exports.character:knockOutPlayer(victim, koMs)
        end
    end
end

-- the vehicle behind a ram or run-over report: MTA names the vehicle as the attacker, a player when it is the driver
local function rammingVehicle(attacker)
    if not isElement(attacker) then
        return nil
    end
    local kind = getElementType(attacker)
    if kind == "vehicle" then
        return attacker
    elseif kind == "player" then
        return getPedOccupiedVehicle(attacker)
    end
    return nil
end

-- a player the wound is credited to (kill, combat window): alive, in the game, not the victim, not staff on duty,
-- not knocked out (upstream PlayerInflictWound drops a knocked-out issuer)
local function creditable(victim, player)
    if not isPlayer(player) or player == victim then
        return nil
    end
    if not exports.character:getCharacterId(player) or isPedDead(player) then
        return nil
    end
    if getElementData(player, "staff.duty") == true or exports.character:isKnockedOut(player) then
        return nil
    end
    return player
end

-- Damage no held item is behind (upstream damage-world.pwn, damage-vehicle.pwn, damage-explosive.pwn): a fall,
-- drowning, fire, a vehicle ram and an explosion. The ram is the driver's wound (its speed, their kill), an
-- explosion its creator's when MTA names a player; everything else only hurts the reporter.
local function nonFirearm(victim, attacker, weapon, loss)
    -- staff on duty are out of the game (upstream IsPlayerOnAdminDuty returns before any of these)
    if getElementData(victim, "staff.duty") == true then
        return
    end
    local ctx = {}
    local credit
    if weapon == 49 or weapon == 50 then
        local veh = rammingVehicle(attacker)
        ctx.velocity = wound.velocity(getElementVelocity(veh or victim))
        ctx.bleedMult = tonumber(settings["vehicles.damage_bleed_mult"])
        ctx.knockMult = tonumber(settings["vehicles.damage_knock_mult"])
        credit = veh and creditable(victim, getVehicleController(veh)) or nil
    elseif wound.isExplosion(weapon) then
        credit = creditable(victim, attacker)
    end
    local w = wound.nonFirearm(weapon, loss, ctx)
    if not w then
        return
    end
    if w.knockoutMs and w.knockoutMs > 0 then
        exports.character:knockOutPlayer(victim, w.knockoutMs)
    end
    if w.hp <= 0 and w.bleed <= 0 then
        return
    end
    exports.character:applyWound(victim, w.bleed, w.hp, credit or false, w.cause)
    rollKnockout(victim, w.knockMult, w.bodypart)
    report(victim, w.bleed, w.hp, w.bodypart)
    if credit then
        util.log(
            "weapons",
            "info",
            "%s %s %s at %.0f km/h bleed %.4f hp %.1f",
            getPlayerName(credit),
            w.cause == "vehicle" and "rammed" or "blew up",
            getPlayerName(victim),
            ctx.velocity or 0,
            w.bleed,
            w.hp
        )
    end
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
            return cd.bleed, tonumber(cd.knockout) or 1.0
        end
        return wound.FIST_BLEED, wound.FIST_KNOCK
    end
    if not cd or cd.melee or cd.baseWeapon ~= weapon then
        return nil
    end
    if wound.isMeleeWeapon(weapon) then
        return cd.muzzleVelocity, (tonumber(cd.magSize) or 0) / 10.0
    end
    local mag = held.data and held.data.mag
    if mag ~= nil and (tonumber(mag) or 0) <= 0 then
        return nil
    end
    local calibreBleed = exports.data:calibreBleed(cd.calibre) or 0.25
    local ammoUname = held.data and held.data.ammoItem
    local ammoDef = ammoUname and itemType(ammoUname) or nil
    local ammoBleedMult = (ammoDef and ammoDef.categoryData and tonumber(ammoDef.categoryData.bleedMult)) or 1.0
    local ammoKoMult = (ammoDef and ammoDef.categoryData and tonumber(ammoDef.categoryData.koMult)) or 1.0
    return wound.firearm(cd.muzzleVelocity, dist, calibreBleed, ammoBleedMult),
        wound.firearmKnock(cd.muzzleVelocity, dist, ammoKoMult)
end

net.handler("weaponHitReported", function(victim, attacker, weapon, bodypart, loss)
    weapon, bodypart, loss = tonumber(weapon), tonumber(bodypart) or 3, tonumber(loss) or 0
    if not weapon or loss < 0 or loss > MAX_LOSS then
        return
    end
    if not exports.character:getCharacterId(victim) or isPedDead(victim) then
        return
    end
    -- a fall, drowning, fire, a ram or an explosion: no held item justifies them, so they take their own path
    -- (nonFirearm), where only a ram's driver or an explosion's creator gets the kill
    if not isPlayer(attacker) or attacker == victim or wound.isEnvironmental(weapon) then
        return nonFirearm(victim, attacker, weapon, loss)
    end
    if
        not exports.character:getCharacterId(attacker)
        or isPedDead(attacker)
        or exports.character:isKnockedOut(attacker)
        or exports.character:isPlayerCuffed(attacker)
    then
        return
    end
    if getElementDimension(attacker) ~= getElementDimension(victim) then
        return
    end
    -- staff on duty (staff resource, upstream TogglePlayerAdminDuty) are out of the game: no wounds from players
    if getElementData(victim, "staff.duty") == true then
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
    -- a charged Stun Gun in hand knocks out instead of wounding (items/server/smallitems.lua, #136)
    if weapon == 0 and exports.items:meleeHit(attacker, victim) == true then
        pairs_[victim] = now
        return
    end

    local bleed, knockMult = hitBleed(attacker, weapon, dist)
    if not bleed or bleed <= 0 then
        return
    end
    -- a Shield in the victim's hand or on their back stops the shot (item/shield.pwn, #137)
    local where = getElementData(victim, "items.held") == "Shield" and "held"
        or getElementData(victim, "items.holster") == "Shield" and "holster"
    if where then
        local _, _, facing = getElementRotation(victim)
        if wound.shieldBlocks(where, bodypart, isPedDucked(attacker), facing, vx, vy, ax, ay) then
            pairs_[victim] = now
            return
        end
    end
    pairs_[victim] = now
    bleed = wound.bodypartBleed(bleed, bodypart)
    if bodypart == 3 and getElementData(victim, "items.armour") then
        bleed = bleed * 0.5
    end
    local hp = wound.hpLoss(bleed)
    exports.character:applyWound(victim, bleed, hp, attacker, wound.killCause(weapon)) -- the body's reason (#139)
    rollKnockout(victim, knockMult, bodypart)
    report(victim, bleed, hp, bodypart)
    if bodypart == 9 then
        exports.items:popHeadgear(victim) -- the hat and mask fall off (char/headgear-pop.pwn, #137)
    end
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
