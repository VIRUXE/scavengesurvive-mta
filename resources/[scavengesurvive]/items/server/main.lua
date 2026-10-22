local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=items/" .. path))()
end
local geometry = loadFile("shared/logic/geometry.lua")
local diff = loadFile("shared/logic/diff.lua")

-- Per-player item state, shared with the server modules (they capture this table).
local state = {
    settings = {}, -- gamemode settings map (db.settings)
    sent = {}, -- player -> set of world item ids the client shows; nil until the character spawned
    held = {}, -- player -> { id, uname, hp, data } in hand
    worn = {}, -- player -> { id, uname, hp, data } bag on the back
    typeCache = {}, -- uname -> item type or false
}

local function itemType(uname)
    if state.typeCache[uname] == nil then
        state.typeCache[uname] = exports.data:itemType(uname) or false
    end
    return state.typeCache[uname] or nil
end

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "onClientItemsToast", player, code)
    end
end

local world =
    loadFile("server/world.lua")({ db = db, state = state, geometry = geometry, diff = diff, charId = charId })
local hands = loadFile("server/hands.lua")({
    db = db,
    net = net,
    state = state,
    geometry = geometry,
    type = itemType,
    charId = charId,
    toast = toast,
    world = world,
})

-- Deletes an item the player owns (held, in their inventory or worn bag). cb(ok) runs only while the player exists.
local function destroy(itemId, player, cb)
    local cid = charId(player)
    if not cid then
        return false
    end
    db.call("item_destroy", { itemId, cid }, function(res, ctx)
        local ok = res and res.ok or false
        if ok then
            world.forgetEverywhere(ctx.itemId)
            triggerEvent("onItemDestroyed", resourceRoot, ctx.itemId)
        end
        if not isElement(ctx.player) then
            return
        end
        if ok and state.held[ctx.player] and state.held[ctx.player].id == ctx.itemId then
            hands.setHeld(ctx.player, nil)
        end
        if ctx.cb then
            ctx.cb(ok, res and res.code or "DB_ERROR")
        end
    end, { player = player, itemId = itemId, cb = cb })
    return true
end

local containers = loadFile("server/containers.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    hands = hands,
})
loadFile("server/use.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    destroy = destroy,
    sendInventory = containers.sendInventory,
})

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("items") then
        return
    end
    db.settings(function(map)
        state.settings = map
    end)
    -- restart: every spawned character gets its held item and worn bag back and a fresh world projection
    for _, p in ipairs(getElementsByType("player")) do
        if charId(p) then
            state.sent[p] = {}
            hands.rebuildCarried(p)
        end
    end
end)

addEventHandler("onCharacterSpawned", root, function()
    -- keep an existing sent-set: the client still shows those objects, the diff stays exact
    state.sent[source] = state.sent[source] or {}
    hands.rebuildCarried(source)
end)

addEventHandler("onCharacterDied", root, function()
    -- character_death_drop already moved everything to the world; the next sync projects it
    hands.setHeld(source, nil)
    hands.setWorn(source, nil)
end)

addEventHandler("onPlayerQuit", root, function()
    hands.clearHeld(source)
    hands.setWorn(source, nil)
    state.sent[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(state.held) do
        hands.clearHeld(p)
    end
    for p in pairs(state.worn) do
        hands.setWorn(p, nil)
    end
end)

function getHeld(player)
    local item = state.held[player]
    return item and { id = item.id, uname = item.uname, hp = item.hp } or false
end

function refreshPlayer(player)
    if not isElement(player) then
        return false
    end
    state.sent[player] = state.sent[player] or {}
    world.syncPlayer(player)
    return true
end

function createStartingItems(cid, unames)
    local player = exports.character:getPlayerByCharacterId(cid)
    local containerId = player and exports.character:getInventoryContainerId(player)
    if not containerId then
        return false
    end
    for _, uname in ipairs(unames) do
        db.call("item_create_in_container", { uname, containerId }, function(res, ctx)
            if res and res.ok then
                triggerEvent("onItemCreated", resourceRoot, res.payload.item_id)
            else
                util.log("items", "warn", "starting item %s: %s", ctx.uname, res and res.code or "DB_ERROR")
            end
        end, { uname = uname })
    end
    return true
end

function destroyItem(itemId, player)
    itemId = tonumber(itemId)
    if not itemId or not isElement(player) then
        return false
    end
    return destroy(itemId, player)
end
