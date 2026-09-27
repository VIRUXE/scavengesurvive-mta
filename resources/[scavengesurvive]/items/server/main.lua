local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
Items = {
    db = db,
    net = net,
    util = util,
    settings = {},
    sent = {},
    held = {},
    heldObject = {},
    wornObject = {},
    typeCache = {},
}

function Items.type(uname)
    if Items.typeCache[uname] == nil then
        Items.typeCache[uname] = exports.data:itemType(uname) or false
    end
    return Items.typeCache[uname] or nil
end

function Items.charId(player)
    return exports.character:getCharacterId(player)
end

function Items.toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "onClientItemsToast", player, code)
    end
end

-- Deletes an item the player owns (held, in their inventory or worn bag). cb(ok) runs only while the player exists.
function Items.destroy(itemId, player, cb)
    local charId = Items.charId(player)
    if not charId then
        return false
    end
    db.call("item_destroy", { itemId, charId }, function(res, ctx)
        local ok = res and res.ok or false
        if ok then
            Items.forgetEverywhere(ctx.itemId)
            triggerEvent("onItemDestroyed", resourceRoot, ctx.itemId)
        end
        if not isElement(ctx.player) then
            return
        end
        if ok and Items.held[ctx.player] and Items.held[ctx.player].id == ctx.itemId then
            Items.setHeld(ctx.player, nil)
        end
        if ctx.cb then
            ctx.cb(ok, res and res.code or "DB_ERROR")
        end
    end, { player = player, itemId = itemId, cb = cb })
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("items") then
        return
    end
    db.settings(function(map)
        Items.settings = map
    end)
    -- restart: every spawned character gets its held item back and a fresh world projection
    for _, p in ipairs(getElementsByType("player")) do
        if Items.charId(p) then
            Items.sent[p] = {}
            Items.rebuildHeld(p)
            Items.rebuildWorn(p)
        end
    end
end)

addEventHandler("onCharacterSpawned", root, function()
    -- keep an existing sent-set: the client still shows those objects, the diff stays exact
    Items.sent[source] = Items.sent[source] or {}
    Items.rebuildHeld(source)
    Items.rebuildWorn(source)
end)

addEventHandler("onCharacterDied", root, function()
    -- character_death_drop already moved everything to the world; the next sync projects it
    Items.setHeld(source, nil)
    Items.setWorn(source, nil)
end)

addEventHandler("onPlayerQuit", root, function()
    Items.clearHeld(source)
    Items.setWorn(source, nil)
    Items.sent[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(Items.heldObject) do
        Items.clearHeld(p)
    end
    for p in pairs(Items.wornObject) do
        Items.setWorn(p, nil)
    end
end)

function getHeld(player)
    local item = Items.held[player]
    return item and { id = item.id, uname = item.uname, hp = item.hp } or false
end

function refreshPlayer(player)
    if not isElement(player) then
        return false
    end
    Items.sent[player] = Items.sent[player] or {}
    Items.syncPlayer(player)
    return true
end

function createStartingItems(charId, unames)
    local player = exports.character:getPlayerByCharacterId(charId)
    local cid = player and exports.character:getInventoryContainerId(player)
    if not cid then
        return false
    end
    for _, uname in ipairs(unames) do
        db.call("item_create_in_container", { uname, cid }, function(res, ctx)
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
    return Items.destroy(itemId, player)
end
