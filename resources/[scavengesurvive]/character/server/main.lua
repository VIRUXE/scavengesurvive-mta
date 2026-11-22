local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local rpc = loadstring(exports.lib:getModule("rpc"), "=lib/rpc.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=character/" .. path))()
end
local survival = loadFile("shared/logic/survival.lua")
local spawnpoints = loadFile("shared/logic/spawnpoints.lua")
local combatlog = loadFile("shared/logic/combatlog.lua")
local drop = loadFile("shared/logic/drop.lua")
local skills = loadFile("shared/logic/skills.lua")
local medical = loadFile("shared/logic/medical.lua")
local travel = loadFile("shared/logic/travel.lua")
local bodies = loadFile("shared/logic/bodies.lua")
local poses = loadFile("shared/logic/poses.lua")
local bleeding = loadFile("shared/logic/bleeding.lua")

-- Every spawned character, shared with the tick and death modules (they capture this table).
local state = {
    byPlayer = {}, -- player -> character stats, skills, inventory and persistence state
    byId = {}, -- character id -> player
    lastSpawn = {}, -- player -> last spawnpoint index (no two spawns in a row at the same place)
    creating = {}, -- players with a character_create in flight
    awaitingRespawn = {}, -- player -> true once the last death's character_death_drop committed
    settings = {}, -- gamemode settings map (db.settings)
    combat = combatlog.new(),
    knockout = {}, -- player -> { untilTick, timer }
    cuffed = {}, -- player -> true
}
-- online seconds of a life: its stored count plus this session's, frozen once it died. The clock runs only while
-- aliveTick is set: staff duty pauses it (st.aliveBase keeps what it had counted, fractions included).
function state.aliveSeconds(st)
    if st.aliveFinal then
        return st.aliveFinal
    end
    local running = st.aliveTick and (getTickCount() - st.aliveTick) / 1000 or 0
    return math.floor((st.aliveBase or 0) + running)
end

-- seconds counted since the last save, marked saved: the database adds them to alive_s rather than taking this
-- server's total, so a correction made there (staff) holds while the character is loaded
function state.aliveUnsaved(st)
    local now = state.aliveSeconds(st)
    local delta = math.max(0, now - (st.aliveSaved or now))
    st.aliveSaved = now
    return delta
end

-- pause (on duty) or resume the life clock
function state.aliveClock(st, run)
    if st.aliveFinal or (st.aliveTick ~= nil) == run then
        return
    end
    if run then
        st.aliveTick = getTickCount()
    else
        st.aliveBase = (st.aliveBase or 0) + (getTickCount() - st.aliveTick) / 1000
        st.aliveTick = nil
    end
end
local CUFF_CONTROLS = {
    "fire",
    "aim_weapon",
    "action",
    "jump",
    "sprint",
    "enter_exit",
    "enter_passenger",
    "next_weapon",
    "previous_weapon",
}

local function clearStatuses(player, restoreControls)
    local ko = state.knockout[player]
    if ko and isTimer(ko.timer) then
        killTimer(ko.timer)
    end
    state.knockout[player] = nil
    state.cuffed[player] = nil
    if state.byPlayer[player] then
        state.byPlayer[player].bleedShown = false
    end
    if isElement(player) then
        setElementData(player, "character.knockedOut", false, "broadcast", "deny")
        setElementData(player, "character.cuffed", false, "broadcast", "deny")
        setElementData(player, "character.bleeding", false, "broadcast", "deny")
        if restoreControls then
            toggleAllControls(player, true, true, false)
            if ko then
                triggerClientEvent(player, "knockedOut", player, 0)
            end
        end
    end
end
state.clearStatuses = clearStatuses
-- staff on duty (staff resource) are out of the game: their stats are frozen and nothing harms or kills them
local function onDuty(p)
    return isElement(p) and getElementData(p, "staff.duty") == true
end
local death = loadFile("server/death.lua")({
    db = db,
    net = net,
    util = util,
    log = log,
    drop = drop,
    state = state,
    bodies = bodies,
    onDuty = onDuty,
})
local tickCtx = { db = db, util = util, survival = survival, skills = skills, medical = medical, state = state }
tickCtx.onDuty = onDuty
tickCtx.bleeding = bleeding
tickCtx.blood = loadFile("server/blood.lua")({ bleeding = bleeding, net = net })
tickCtx.die = death.die
local tick = loadFile("server/tick.lua")(tickCtx)
loadFile("server/ground.lua")({ log = log, state = state, onDuty = onDuty }) -- under-map rescue on foot

-- Staff duty: full hp and no bleeding while it lasts (nothing harms an on-duty player, so it stays there). The
-- character's own hp and bleed are kept in st.dutyKeep, are what every save writes meanwhile (a quit or crash on duty
-- is no free heal) and come back when duty ends. Wounds stay as they were; the frozen tick leaves them alone.
local function dutyStats(player, st, on)
    if on and not st.dutyKeep then
        st.dutyKeep = { hp = st.hp, bleed = st.bleed }
        st.hp, st.bleed = 100, 0
    elseif not on and st.dutyKeep then
        st.hp, st.bleed = st.dutyKeep.hp, st.dutyKeep.bleed
        st.dutyKeep = nil
    else
        return
    end
    st.dirty = true
    setElementHealth(player, math.max(1, st.hp))
    tick.sendStats(player, false)
end
local medicalCtx = { medical = medical, survival = survival, state = state, sendStats = tick.sendStats }
medicalCtx.wake = function(p)
    return wakeUpPlayer(p)
end
medicalCtx.isKnockedOut = function(p)
    return isKnockedOut(p)
end
local treatment = loadFile("server/medical.lua")(medicalCtx)
tickCtx.treatment = treatment
-- sitting, hands up and the aim shout (#140)
local posesModule = loadFile("server/poses.lua")({
    net = net,
    state = state,
    poses = poses,
    isKnockedOut = function(p)
        return isKnockedOut(p)
    end,
    isPlayerCuffed = function(p)
        return isPlayerCuffed(p)
    end,
    lang = function(p, key, ...)
        return exports.data:t(exports.auth:getLanguage(p) or "en", key, ...)
    end,
})
state.clearPose = posesModule.clear
-- travel stats and the Endurance skill (#138)
tickCtx.travel = loadFile("server/travel.lua")({
    net = net,
    travel = travel,
    state = state,
    gainSkill = function(p, name)
        return gainSkill(p, name)
    end,
    isKnockedOut = function(p)
        return isKnockedOut(p)
    end,
    onDuty = onDuty,
})

-- The client's watch turns red while the combat-log window is open (upstream IsPlayerCombatLogging reads the
-- same damage clock); ms = 0 turns it white again.
local function sendCombatWindow(player, ms)
    if isElement(player) then
        triggerClientEvent(player, "combatWindowChanged", player, ms)
    end
end

local function combatWindowS()
    return tonumber(state.settings["player.combat_log_window"]) or combatlog.DEFAULT_WINDOW_S
end

local function rngInt(n)
    return math.random(1, n)
end

local function startingItems(charId, isNew)
    local key = isNew and "spawn.new_items" or "spawn.res_items"
    local unames = util.split(state.settings[key] or (isNew and "Knife" or "AntiSepBandage"), ",")
    local ok = rpc.call("items", "createStartingItems", charId, unames)
    if not ok then
        util.log("character", "warn", "items resource down; no starting items for %d", charId)
    end
end

-- characters.skills arrives as the column text; a new character has none (false/nil).
local function loadSkills(text)
    return skills.fromList(type(text) == "string" and fromJSON("[" .. text .. "]") or nil)
end

-- characters.drugs is the column text like skills; characters.infection a bit mask (shared/logic/medical.lua)
local function loadDrugs(text)
    return medical.decodeDrugs(type(text) == "string" and fromJSON("[" .. text .. "]") or nil)
end

local function sendSkills(player, st)
    triggerClientEvent(player, "characterSkillsSynced", player, skills.rows(st.skills))
end

local function spawnFromRow(player, row, isNew)
    local st = {
        id = row.id,
        accountId = row.account_id,
        hp = row.hp,
        food = row.food,
        thirst = tonumber(row.thirst) or 80,
        bleed = row.bleed,
        wounds = survival.decodeWounds(
            not isNew and type(row.wounds) == "string" and fromJSON("[" .. row.wounds .. "]") or nil,
            row.bleed,
            isNew
        ),
        skills = loadSkills(row.skills),
        infection = medical.decodeInfection(row.infection),
        drugs = loadDrugs(row.drugs),
        toxic = tonumber(row.toxic) or 0, -- poison level 0..100 (shared/logic/survival.lua)
        dirty = false,
        born = tonumber(row.born) or getRealTime().timestamp, -- unix time the character was created (death age)
        -- seconds this life spent online before this session (characters.alive_s) and the tick the session's count
        -- started at: the ranking counts a life only while its player is connected
        aliveBase = tonumber(row.alive_s) or 0,
        aliveSaved = tonumber(row.alive_s) or 0, -- the count as of the last save (state.aliveUnsaved)
        aliveTick = getTickCount(), -- nil while paused (staff duty, set right after the spawn below)
        inventoryContainerId = row.inventory_container_id,
        lastSent = { hp = -1, food = -1, thirst = -1, bleed = -1, wounds = -1 },
    }
    state.byPlayer[player], state.byId[row.id] = st, player
    state.aliveClock(st, not onDuty(player))
    combatlog.reset(state.combat, player)
    sendCombatWindow(player, 0)
    clearStatuses(player, true)
    -- A restart of this resource reloads everyone still playing. One already sitting in a vehicle (vehicles' own
    -- restart handoff may have seated them first) keeps the seat: spawnPlayer would pull them out onto the road.
    -- One not seated yet spawns as usual and the handoff seats them after.
    if isNew or isPedDead(player) or not getPedOccupiedVehicle(player) then
        spawnPlayer(player, row.x, row.y, row.z, row.rz, row.skin, row.interior or 0, row.dimension or 0)
    end
    if getElementData(player, "auth.reauthProtection") then
        setElementFrozen(player, true)
    end
    exports.staff:reapplyDutySkin(player)
    setElementHealth(player, math.max(1, st.hp))
    if onDuty(player) then
        dutyStats(player, st, true)
    end
    setCameraTarget(player, player)
    fadeCamera(player, true)
    triggerEvent("characterSpawned", player, row.id, isNew)
    log.event("character.spawned", {
        player = player,
        character_id = row.id,
        x = tonumber(row.x),
        y = tonumber(row.y),
        z = tonumber(row.z),
        int = row.interior or 0,
        dim = row.dimension or 0,
        fresh = isNew,
    })
    if isNew then
        startingItems(row.id, row.hp == survival.NEW.hp)
    end
    tick.sendStats(player, true)
    sendSkills(player, st)
end

local function createAndSpawn(player, accountId, stats)
    -- one character_create in flight per player (a second one would retire the first)
    if state.creating[player] then
        return
    end
    state.creating[player] = true
    local idx, x, y, z, rz = spawnpoints.pick(state.lastSpawn[player], rngInt)
    state.lastSpawn[player] = idx
    -- upstream spawn.pwn picked from seven skins per gender; the port rolls every clothes type of the gender with
    -- its spawn chance (items/shared/logic/clothes.lua, #76), so a rare SWAT or Morgan Freeman spawn is possible
    local skin = exports.items:rollSpawnSkin(rngInt(2) == 2)
    local params = { accountId, skin, x, y, z, rz, stats.hp, stats.food, stats.bleed, stats.thirst }
    db.call("character_create", params, function(res, ctx)
        state.creating[ctx.player] = nil
        if not isElement(ctx.player) then
            return
        end
        if not res or not res.ok then
            return log.event("character.created", {
                player = ctx.player,
                account_id = accountId,
                ok = false,
                code = res and res.code or "DB_ERROR",
            }, "error")
        end
        log.event("character.created", {
            player = ctx.player,
            account_id = accountId,
            character_id = res.payload.character_id,
            name = getPlayerName(ctx.player),
            skin = skin,
        })
        spawnFromRow(ctx.player, {
            id = res.payload.character_id,
            account_id = accountId,
            inventory_container_id = res.payload.inventory_container_id,
            hp = stats.hp,
            food = stats.food,
            thirst = stats.thirst,
            bleed = stats.bleed,
            x = x,
            y = y,
            z = z,
            rz = rz,
            skin = skin,
        }, true)
    end, { player = player })
end

local function loadOrCreate(player, accountId)
    -- An auth reload asks an already spawned player to log in again; keep their live character and vehicle seat.
    local current = state.byPlayer[player]
    if current and current.accountId == accountId and not current.dead then
        tick.sendStats(player, true)
        sendSkills(player, current)
        return
    end
    db.one(
        "SELECT id, account_id, hp, food, thirst, bleed, wounds, skills, infection, drugs, toxic, x, y, z, rz,"
            .. " skin,"
            .. " interior, dimension,"
            .. " inventory_container_id, alive_s, UNIX_TIMESTAMP(spawned_at) AS born"
            .. " FROM characters WHERE account_id = ? AND alive = 1",
        { accountId },
        function(row, ctx)
            if not isElement(ctx.player) then
                return
            end
            if row == false then
                return
            end
            if row then
                return spawnFromRow(ctx.player, row, false)
            end
            createAndSpawn(ctx.player, accountId, survival.NEW)
        end,
        { player = player }
    )
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("character") then
        return
    end
    setGameType("Scavenge & Survive")
    setMapName("San Andreas")
    db.settings(function(map)
        state.settings = map
    end)
    for _, p in ipairs(getElementsByType("player")) do
        local accountId = exports.auth:getAccountId(p)
        if accountId then
            loadOrCreate(p, accountId)
        end
    end
end)

addEventHandler("playerAuthenticated", root, function(accountId)
    loadOrCreate(source, accountId)
end)

-- a (re)started client asks for its skills: the ones sent at spawn are lost when the server side starts first
net.handler("characterSkillsRequested", function(player)
    local st = state.byPlayer[player]
    if st then
        sendSkills(player, st)
    end
end)

net.handler("respawnRequested", function(player)
    -- only after a committed death: character_create would retire a character that is still alive in the DB (still
    -- loading, or its death drop failed) without dropping its items
    if state.byPlayer[player] or state.creating[player] or not state.awaitingRespawn[player] then
        return
    end
    local accountId = exports.auth:getAccountId(player)
    if not accountId then
        return
    end
    state.awaitingRespawn[player] = nil
    triggerClientEvent(player, "deathScreenShown", player, false)
    createAndSpawn(player, accountId, survival.RESPAWN)
end, { rate = 1 })

-- A player who leaves (quit, timeout) within the combat-log window of being hurt, while the attacker is still
-- online, dies where they stood and drops everything (upstream accounts.pwn logout path). The character is still
-- in memory and the element still valid here, so death_drop runs with the real position.
local function combatLogged(player, st, quitReason)
    if st.dead or getElementData(player, "auth.reauthProtection") or not combatlog.countsAsLogout(quitReason) then
        return false
    end
    local window = combatWindowS()
    local attacker = combatlog.attackerOf(state.combat, player, getTickCount(), window, isElement)
    if not attacker then
        return false
    end
    local now = getTickCount()
    log.event("character.combatLogged", {
        player = player,
        character_id = st.id,
        attacker = attacker,
        window_s = window,
        since_damage_s = (now - (state.combat.lastDamage[player] or now)) / 1000,
        msg = string.format("%s combat-logged (last hit by %s)", getPlayerName(player), getPlayerName(attacker)),
    }, "warn")
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    for _, p in ipairs(getElementsByType("player")) do
        outputChatBox(lang.formatFor(p, "%s combat logged!", getPlayerName(player)), p, 255, 220, 0)
    end
    return death.die(player, "combatlog", attacker, true)
end

local function forget(player, quitReason)
    local st = state.byPlayer[player]
    if st then
        if not combatLogged(player, st, quitReason) then
            tick.flushOne(player, st)
        end
        state.byId[st.id] = nil
    end
    local released = combatlog.forget(state.combat, player)
    if released then
        sendCombatWindow(released, 0) -- the attacker left: the victim's watch turns white again
    end
    clearStatuses(player, false)
    state.byPlayer[player] = nil
    state.lastSpawn[player] = nil
    state.creating[player] = nil
    state.awaitingRespawn[player] = nil
end
-- auth's own onPlayerQuit handler runs first (it started first) and raises playerLoggedOut with the quit reason,
-- so that is where a quitting player is seen; the direct onPlayerQuit handler covers a player who never logged in.
addEventHandler("onPlayerQuit", root, function(reason)
    forget(source, reason)
end)
addEventHandler("playerLoggedOut", root, function(_, quitReason)
    forget(source, quitReason)
end)
addEventHandler("onResourceStop", resourceRoot, function()
    tick.flushAll(true)
end)

-- The tutorial ended: its character is already retired in the database (tutorial_cleanup); drop it from memory and
-- start the player on a new one, as upstream's PlayerCreateNewCharacter does.
function restartCharacter(player)
    local accountId = isElement(player) and exports.auth:getAccountId(player)
    if not accountId or state.creating[player] then
        return false
    end
    local st = state.byPlayer[player]
    if st then
        state.byId[st.id] = nil
        state.byPlayer[player] = nil
    end
    clearStatuses(player, true)
    createAndSpawn(player, accountId, survival.NEW)
    return true
end

function getCharacterId(player)
    local st = state.byPlayer[player]
    return st and st.id or false
end

-- Seconds the player's character has been alive while online and off staff duty, this session included; false
-- without one. Also returns whether it is dead (its count stopped at the death, st.aliveFinal) and whether its clock
-- is paused (on duty).
function getAliveSeconds(player)
    local st = state.byPlayer[player]
    if not st then
        return false
    end
    return state.aliveSeconds(st), st.dead == true, st.aliveTick == nil
end

-- staff duty takes the character out of the game: its time alive stops counting until duty ends
addEventHandler("onElementDataChange", root, function(key)
    if key ~= "staff.duty" or getElementType(source) ~= "player" then
        return
    end
    local st = state.byPlayer[source]
    if st and not st.dead then
        state.aliveClock(st, not onDuty(source))
        dutyStats(source, st, onDuty(source))
    end
end)

function getPlayerByCharacterId(id)
    return state.byId[id] or false
end

function getInventoryContainerId(player)
    local st = state.byPlayer[player]
    return st and st.inventoryContainerId or false
end

function getStats(player)
    local st = state.byPlayer[player]
    if not st then
        return false
    end
    return {
        hp = st.hp,
        food = st.food,
        thirst = st.thirst,
        bleed = st.bleed,
        wounds = #st.wounds,
        woundParts = survival.woundsPerPart(st.wounds),
        infection = st.infection,
    }
end

-- Treatment (#94): items calls treatPlayer at the end of a medical, pill or injector hold; returns
-- { used, consume, data } (data = the item's new data, nil to keep it).
function treatPlayer(healer, patient, uname, data)
    return treatment.treat(healer, patient, uname, data)
end

-- The hold a treatment item starts on patient (nil when uname is not one), shortened by the healer's skill.
function treatmentHold(healer, uname, patient)
    local ms, skill = medical.holdFor(uname, isKnockedOut(patient))
    if not ms then
        return false
    end
    return skill and skillTimeModifier(healer, ms, skill) or ms
end

-- Loot data for a Doctor's Bag, Pills or Injector (JSON text), false for anything else.
function medicalLootData(uname)
    return medical.lootData(uname, math.random) or false
end

-- The drugs, pills and injections a medical item can hold ({ drugs, pills, injections }), for dev's item picker.
function medicalChoices()
    return { drugs = medical.BAG_DRUGS, pills = medical.PILLS, injections = medical.INJECTIONS }
end

function setInfection(player, kind, on)
    local st = state.byPlayer[player]
    if on == true and onDuty(player) then
        return false
    end
    return st and not st.dead and treatment.setInfection(player, st, kind, on) or false
end

function applyDrug(player, name, ms)
    local st = state.byPlayer[player]
    return st and not st.dead and treatment.applyDrug(player, st, name, ms) or false
end

function hasDrug(player, name)
    local st = state.byPlayer[player]
    return st ~= nil and st.drugs[name] ~= nil
end

function modifyStat(player, key, delta)
    local st = state.byPlayer[player]
    if not st or (key ~= "hp" and key ~= "food" and key ~= "thirst" and key ~= "bleed") then
        return false
    end
    if getElementData(player, "auth.reauthProtection") then
        return st[key]
    end
    -- on duty only healing goes through: less bleed, more hp or food
    if onDuty(player) and ((key == "bleed" and delta > 0) or (key ~= "bleed" and delta < 0)) then
        return st[key]
    end
    local hi = key == "bleed" and 1 or 100
    st[key] = math.max(0, math.min(hi, st[key] + delta))
    st.dirty = true
    -- a stat edit is not a wound (upstream SetPlayerBleedRate), but bleeding with none stops on the next tick
    if key == "bleed" and delta > 0 and #st.wounds == 0 then
        survival.addWound(st.wounds, 3, delta, "stat", getRealTime().timestamp)
    end
    if key == "hp" then
        setElementHealth(player, math.max(1, st.hp))
    end
    tick.sendStats(player, false)
    if st.hp <= 0 then
        death.die(player, "stat", false)
    end
    return st[key]
end

-- Skills (#93, shared/logic/skills.lua): callers shorten an action with skillTimeModifier when it starts and call
-- gainSkill when it finishes. Skills belong to the character, so a respawn starts from none.
local function changeSkill(player, st, name, amount)
    st.skillsDirty, st.dirty = true, true
    triggerClientEvent(player, "skillGained", player, name, amount)
    sendSkills(player, st)
    return amount
end

-- nothing is learnt on staff duty (the character is out of the game); setSkill, a staff command, still works
function gainSkill(player, name, mult)
    local st = state.byPlayer[player]
    if not st or st.dead or onDuty(player) then
        return false
    end
    local amount = skills.gain(st.skills, name, mult)
    return amount and changeSkill(player, st, name, amount)
end

function setSkill(player, name, amount)
    local st = state.byPlayer[player]
    if not st or st.dead then
        return false
    end
    local v = skills.set(st.skills, name, amount)
    return v and changeSkill(player, st, name, v)
end

function getSkill(player, name)
    local st = state.byPlayer[player]
    return st and skills.value(st.skills, name) or 0
end

function skillTimeModifier(player, ms, name)
    local st = state.byPlayer[player]
    return st and skills.timeModifier(st.skills, ms, name) or ms
end

-- Breathed gas (the toxic resource, once a tick for a player in the cloud): amount is the dose after the mask and
-- the shelter; the character's Poison Resistance takes its share off, and grows by a step for every
-- TOXIC_SKILL_EVERY points taken. Returns the new poison level.
local TOXIC_SKILL, TOXIC_SKILL_EVERY = "PoisonResistance", 10
function addToxic(player, amount)
    local st = state.byPlayer[player]
    amount = tonumber(amount)
    if not st or st.dead or not amount or amount <= 0 then
        return st and st.toxic or 0
    end
    if onDuty(player) or getElementData(player, "auth.reauthProtection") then
        return st.toxic
    end
    local taken
    st.toxic, taken = survival.addToxic(st.toxic, amount, skills.value(st.skills, TOXIC_SKILL))
    st.dirty = true
    st.toxicLearnt = (st.toxicLearnt or 0) + taken
    while st.toxicLearnt >= TOXIC_SKILL_EVERY do
        st.toxicLearnt = st.toxicLearnt - TOXIC_SKILL_EVERY
        gainSkill(player, TOXIC_SKILL, 1)
    end
    return st.toxic
end

function getToxic(player)
    local st = state.byPlayer[player]
    return st and st.toxic or 0
end

function killCharacter(player, cause, killer)
    return death.die(player, cause, killer)
end

-- bodypart (GTA's 3-9) records a wound on the character (upstream PlayerInflictWound); without one the damage
-- (fire, drowning) only costs hp and bleed. A wound past survival.MAX_WOUNDS kills, as upstream did.
function applyWound(player, bleedAdd, hpLoss, killer, cause, bodypart)
    local st = state.byPlayer[player]
    if not st or st.dead or getElementData(player, "auth.reauthProtection") or onDuty(player) then
        return false
    end
    bleedAdd = math.max(0, tonumber(bleedAdd) or 0)
    hpLoss = math.max(0, tonumber(hpLoss) or 0)
    if bodypart then
        if not survival.addWound(st.wounds, bodypart, bleedAdd, cause, getRealTime().timestamp) then
            hpLoss = st.hp
        end
    elseif bleedAdd > 0 and #st.wounds == 0 then
        -- bleeding with no wound stops on the next tick (survival.tick)
        survival.addWound(st.wounds, 3, bleedAdd, cause, getRealTime().timestamp)
    end
    st.bleed = math.min(1.0, st.bleed + bleedAdd)
    st.hp = math.max(0, st.hp - hpLoss)
    st.dirty = true
    local byPlayer = isElement(killer) and getElementType(killer) == "player" and killer ~= player
    combatlog.damaged(state.combat, player, byPlayer and killer or nil, getTickCount())
    if byPlayer then
        sendCombatWindow(player, combatWindowS() * 1000)
    end
    setElementHealth(player, math.max(1, st.hp))
    tick.sendStats(player, true)
    if st.hp <= 0 then
        death.die(player, cause or "killed", isElement(killer) and killer or false)
    end
    return true
end

-- Staff /heal: full hp, no bleed, every wound removed at once (a Medkit or Doctor's Bag takes a few, the oldest first)
-- and no wound infection. On duty it heals the character's own hp and bleed kept in st.dutyKeep too, or duty's end
-- would put the old ones back. Returns how many wounds there were, or false without a living character.
function healCharacter(player)
    local st = state.byPlayer[player]
    if not st or st.dead then
        return false
    end
    local n = #st.wounds
    for i = n, 1, -1 do
        st.wounds[i] = nil
    end
    st.hp, st.bleed = 100, 0
    if st.dutyKeep then
        st.dutyKeep.hp, st.dutyKeep.bleed = 100, 0
    end
    st.infection.wound = false
    st.toxic = 0
    st.dirty = true
    setElementHealth(player, 100)
    tick.sendStats(player, true)
    return n
end

function wakeUpPlayer(player)
    local ko = state.knockout[player]
    if ko and isTimer(ko.timer) then
        killTimer(ko.timer)
    end
    state.knockout[player] = nil
    if not isElement(player) then
        return false
    end
    if ko then
        log.event("character.wokeUp", { player = player })
    end
    setElementData(player, "character.knockedOut", false, "broadcast", "deny")
    triggerClientEvent(player, "knockedOut", player, 0)
    local st = state.byPlayer[player]
    if st and not st.dead and not isPedDead(player) then
        toggleAllControls(player, true, true, false)
        if state.cuffed[player] then
            for _, ctrl in ipairs(CUFF_CONTROLS) do
                toggleControl(player, ctrl, false)
            end
        end
        setPedAnimation(player, "PED", "GETUP_FRONT", 1000, false, true, true, false)
    end
    return true
end

-- by: the player who caused it (optional, only logged)
function knockOutPlayer(player, durationMs, by)
    if
        not isElement(player)
        or isPedDead(player)
        or getElementData(player, "auth.reauthProtection")
        or onDuty(player)
    then
        return false
    end
    local st = state.byPlayer[player]
    if not st or st.dead then
        return false
    end
    if state.clearPose then
        state.clearPose(player) -- a sit or raised hands end with the knockout (#140)
    end
    local now = getTickCount()
    local cur = state.knockout[player]
    local rem = cur and math.max(0, cur.untilTick - now) or 0
    local total = survival.knockoutAdd(rem, durationMs)
    if total <= 0 then
        return false
    end
    if cur and isTimer(cur.timer) then
        killTimer(cur.timer)
    end
    local timer = setTimer(function(p)
        if isElement(p) then
            wakeUpPlayer(p)
        end
    end, total, 1, player)
    state.knockout[player] = { untilTick = now + total, timer = timer }
    setElementData(player, "character.knockedOut", true, "broadcast", "deny")
    toggleAllControls(player, false, true, false)
    if getPedOccupiedVehicle(player) then
        setPedAnimation(player, "PED", "CAR_DEAD_LHS", -1, false, false, false, true)
    else
        setPedAnimation(player, "PED", "KO_SHOT_STOM", -1, false, false, false, true)
    end
    triggerClientEvent(player, "knockedOut", player, total)
    log.event("character.knockedOut", {
        player = player,
        by = isElement(by) and getElementType(by) == "player" and getPlayerName(by) or nil,
        duration_ms = total,
    })
    return true
end

function isKnockedOut(player)
    local ko = state.knockout[player]
    return ko ~= nil and getTickCount() < ko.untilTick
end

function setPlayerCuffed(player, toggle)
    if not isElement(player) then
        return false
    end
    local st = state.byPlayer[player]
    if not st or st.dead then
        return false
    end
    local flag = toggle == true
    if flag and state.clearPose then
        state.clearPose(player) -- raised hands give back their controls before the cuffs take theirs (#140)
    end
    state.cuffed[player] = flag or nil
    setElementData(player, "character.cuffed", flag, "broadcast", "deny")
    if not isKnockedOut(player) then
        for _, ctrl in ipairs(CUFF_CONTROLS) do
            toggleControl(player, ctrl, not flag)
        end
    end
    return true
end

function isPlayerCuffed(player)
    return state.cuffed[player] == true
end

function isHandsUp(player)
    return posesModule.isHandsUp(player)
end
