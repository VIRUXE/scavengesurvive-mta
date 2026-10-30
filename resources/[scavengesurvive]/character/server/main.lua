local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local rpc = loadstring(exports.lib:getModule("rpc"), "=lib/rpc.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
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
    byPlayer = {}, -- player -> { id, hp, food, bleed, wounds, infection, drugs, skills, skillsDirty, dirty, dead, ... }
    byId = {}, -- character id -> player
    lastSpawn = {}, -- player -> last spawnpoint index (no two spawns in a row at the same place)
    creating = {}, -- players with a character_create in flight
    awaitingRespawn = {}, -- player -> true once the last death's character_death_drop committed
    settings = {}, -- gamemode settings map (db.settings)
    combat = combatlog.new(),
    knockout = {}, -- player -> { untilTick, timer }
    cuffed = {}, -- player -> true
}
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
local death =
    loadFile("server/death.lua")({ db = db, net = net, util = util, drop = drop, state = state, bodies = bodies })
local tickCtx = { db = db, util = util, survival = survival, skills = skills, medical = medical, state = state }
tickCtx.bleeding = bleeding
tickCtx.die = death.die
local tick = loadFile("server/tick.lua")(tickCtx)
local medicalCtx = { medical = medical, state = state, sendStats = tick.sendStats }
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
        hp = row.hp,
        food = row.food,
        bleed = row.bleed,
        wounds = survival.loadWounds(row.bleed, isNew),
        skills = loadSkills(row.skills),
        infection = medical.decodeInfection(row.infection),
        drugs = loadDrugs(row.drugs),
        dirty = false,
        inventoryContainerId = row.inventory_container_id,
        lastSent = { hp = -1, food = -1, bleed = -1 },
    }
    state.byPlayer[player], state.byId[row.id] = st, player
    combatlog.reset(state.combat, player)
    sendCombatWindow(player, 0)
    clearStatuses(player, true)
    spawnPlayer(player, row.x, row.y, row.z, row.rz, row.skin, row.interior or 0, row.dimension or 0)
    setElementHealth(player, math.max(1, st.hp))
    setCameraTarget(player, player)
    fadeCamera(player, true)
    triggerEvent("characterSpawned", player, row.id, isNew)
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
    local params = { accountId, skin, x, y, z, rz, stats.hp, stats.food, stats.bleed }
    db.call("character_create", params, function(res, ctx)
        state.creating[ctx.player] = nil
        if not isElement(ctx.player) then
            return
        end
        if not res or not res.ok then
            return util.log("character", "error", "character_create failed: %s", res and res.code or "db")
        end
        spawnFromRow(ctx.player, {
            id = res.payload.character_id,
            inventory_container_id = res.payload.inventory_container_id,
            hp = stats.hp,
            food = stats.food,
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
    db.one(
        "SELECT id, hp, food, bleed, skills, infection, drugs, x, y, z, rz, skin, interior, dimension,"
            .. " inventory_container_id"
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
    if st.dead or not combatlog.countsAsLogout(quitReason) then
        return false
    end
    local window = combatWindowS()
    local attacker = combatlog.attackerOf(state.combat, player, getTickCount(), window, isElement)
    if not attacker then
        return false
    end
    util.log("character", "info", "%s combat-logged (last hit by %s)", getPlayerName(player), getPlayerName(attacker))
    outputChatBox(string.format("%s combat logged!", getPlayerName(player)), root, 255, 220, 0)
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

function getCharacterId(player)
    local st = state.byPlayer[player]
    return st and st.id or false
end

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
    return { hp = st.hp, food = st.food, bleed = st.bleed, wounds = st.wounds, infection = st.infection }
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

function setInfection(player, kind, on)
    local st = state.byPlayer[player]
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
    if not st or (key ~= "hp" and key ~= "food" and key ~= "bleed") then
        return false
    end
    local hi = key == "bleed" and 1 or 100
    st[key] = math.max(0, math.min(hi, st[key] + delta))
    st.dirty = true
    if key == "bleed" and delta > 0 then
        st.wounds = st.wounds + 1
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

function gainSkill(player, name, mult)
    local st = state.byPlayer[player]
    if not st or st.dead then
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

function killCharacter(player, cause, killer)
    return death.die(player, cause, killer)
end

function applyWound(player, bleedAdd, hpLoss, killer, cause)
    local st = state.byPlayer[player]
    if not st or st.dead then
        return false
    end
    bleedAdd = math.max(0, tonumber(bleedAdd) or 0)
    hpLoss = math.max(0, tonumber(hpLoss) or 0)
    -- only a bleeding wound counts: the survival tick stops bleeding at wounds == 0
    if bleedAdd > 0 then
        st.bleed = math.min(1.0, st.bleed + bleedAdd)
        st.wounds = st.wounds + 1
    end
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

function wakeUpPlayer(player)
    local ko = state.knockout[player]
    if ko and isTimer(ko.timer) then
        killTimer(ko.timer)
    end
    state.knockout[player] = nil
    if not isElement(player) then
        return false
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

function knockOutPlayer(player, durationMs)
    if not isElement(player) or isPedDead(player) then
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
