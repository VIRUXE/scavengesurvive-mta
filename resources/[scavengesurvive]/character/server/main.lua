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

Character = {
    db = db,
    net = net,
    util = util,
    survival = survival,
    spawnpoints = spawnpoints,
    byPlayer = {},
    byId = {},
    lastSpawn = {},
    creating = {},
    settings = {},
}

local function rngInt(n)
    return math.random(1, n)
end

local function startingItems(charId, isNew)
    local key = isNew and "spawn.new_items" or "spawn.res_items"
    local unames = util.split(Character.settings[key] or (isNew and "Knife" or "AntiSepBandage"), ",")
    local ok = rpc.call("items", "createStartingItems", charId, unames)
    if not ok then
        util.log("character", "warn", "items resource down; no starting items for %d", charId)
    end
end

local function spawnFromRow(player, row, isNew)
    local st = {
        id = row.id,
        hp = row.hp,
        food = row.food,
        bleed = row.bleed,
        wounds = survival.woundsOnLoad(row.bleed),
        dirty = false,
        inventoryContainerId = row.inventory_container_id,
        lastSent = { hp = -1, food = -1, bleed = -1 },
    }
    Character.byPlayer[player], Character.byId[row.id] = st, player
    spawnPlayer(player, row.x, row.y, row.z, row.rz, row.skin, row.interior or 0, row.dimension or 0)
    setElementHealth(player, math.max(1, st.hp))
    setCameraTarget(player, player)
    fadeCamera(player, true)
    setPlayerHudComponentVisible(player, "all", false)
    setPlayerHudComponentVisible(player, "radar", true)
    setPlayerHudComponentVisible(player, "crosshair", true)
    triggerEvent("onCharacterSpawned", player, row.id, isNew)
    if isNew then
        startingItems(row.id, row.hp == survival.NEW.hp)
    end
    Character.sendStats(player, true)
end

function Character.createAndSpawn(player, accountId, stats)
    -- one character_create in flight per player (a second one would retire the first)
    if Character.creating[player] then
        return
    end
    Character.creating[player] = true
    local idx, x, y, z, rz = spawnpoints.pick(Character.lastSpawn[player], rngInt)
    Character.lastSpawn[player] = idx
    local skin = spawnpoints.randomSkin(rngInt)
    local params = { accountId, skin, x, y, z, rz, stats.hp, stats.food, stats.bleed }
    db.call("character_create", params, function(res, ctx)
        Character.creating[ctx.player] = nil
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
        "SELECT id, hp, food, bleed, x, y, z, rz, skin, interior, dimension, inventory_container_id"
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
            Character.createAndSpawn(ctx.player, accountId, survival.NEW)
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
        Character.settings = map
    end)
    for _, p in ipairs(getElementsByType("player")) do
        local accountId = exports.auth:getAccountId(p)
        if accountId then
            loadOrCreate(p, accountId)
        end
    end
end)

addEventHandler("onPlayerAuthenticated", root, function(accountId)
    loadOrCreate(source, accountId)
end)

net.handler("onCharacterRequestRespawn", function(player)
    local st = Character.byPlayer[player]
    if st and st.hp > 0 then
        return
    end
    local accountId = exports.auth:getAccountId(player)
    if not accountId then
        return
    end
    triggerClientEvent(player, "onClientCharacterDeathScreen", player, false)
    Character.createAndSpawn(player, accountId, survival.RESPAWN)
end, { rate = 1 })

local function forget(player)
    local st = Character.byPlayer[player]
    if st then
        Character.flushOne(player, st)
        Character.byId[st.id] = nil
    end
    Character.byPlayer[player] = nil
    Character.lastSpawn[player] = nil
    Character.creating[player] = nil
end
addEventHandler("onPlayerQuit", root, function()
    forget(source)
end)
addEventHandler("onPlayerLoggedOut", root, function()
    forget(source)
end)
addEventHandler("onResourceStop", resourceRoot, function()
    Character.flushAll(true)
end)

function getCharacterId(player)
    local st = Character.byPlayer[player]
    return st and st.id or false
end

function getPlayerByCharacterId(id)
    return Character.byId[id] or false
end

function getInventoryContainerId(player)
    local st = Character.byPlayer[player]
    return st and st.inventoryContainerId or false
end

function getStats(player)
    local st = Character.byPlayer[player]
    return st and { hp = st.hp, food = st.food, bleed = st.bleed, wounds = st.wounds } or false
end

function modifyStat(player, key, delta)
    local st = Character.byPlayer[player]
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
    Character.sendStats(player, false)
    if st.hp <= 0 then
        Character.die(player, "stat", false)
    end
    return st[key]
end

function killCharacter(player, cause, killer)
    return Character.die(player, cause, killer)
end

function applyWound(player, bleedAdd, hpLoss, killer, cause)
    local st = Character.byPlayer[player]
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
    setElementHealth(player, math.max(1, st.hp))
    Character.sendStats(player, true)
    if st.hp <= 0 then
        Character.die(player, cause or "killed", isElement(killer) and killer or false)
    end
    return true
end
