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
local ammo = loadFile("shared/logic/ammo.lua")
local apparel = loadFile("shared/logic/apparel.lua")
local skins = loadFile("shared/logic/skins.lua")
apparel.skins = skins
local clothes = loadFile("shared/logic/clothes.lua")

-- export: whether a ped model is a woman (staff picks the duty skin from it)
function isFemaleSkin(skin)
    return skins.isFemale(skin)
end

-- export: a new character's skin, upstream's clothes roll limited to one gender (character picks the gender)
function rollSpawnSkin(female)
    return clothes.roll(math.random, math.random, female and clothes.FEMALE or clothes.MALE)
end

-- Per-player item state, shared with the server modules (they capture this table).
local state = {
    settings = {}, -- gamemode settings map (db.settings)
    sent = {}, -- player -> set of world item ids the client shows; nil until the character spawned
    held = {}, -- player -> { id, uname, hp, data } in hand
    worn = {}, -- player -> { id, uname, hp, data } bag on the back
    hat = {}, -- player -> { id, uname, hp, data } worn hat
    mask = {}, -- player -> { id, uname, hp, data } worn mask
    armour = {}, -- player -> { id, uname, hp, data } worn armour
    holster = {}, -- player -> { id, uname, hp, data } holstered weapon
    typeCache = {}, -- uname -> item type or false
}

local function itemType(uname)
    if state.typeCache[uname] == nil then
        state.typeCache[uname] = exports.data:itemType(uname) or false
    end
    return state.typeCache[uname] or nil
end

local function defaultAmmo(calibre)
    local list = calibre and exports.data:ammoTypesForCalibre(calibre)
    return list and list[1] or nil
end

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "toastShown", player, code)
    end
end

local world =
    loadFile("server/world.lua")({ db = db, state = state, geometry = geometry, diff = diff, charId = charId })
local hands

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
            triggerEvent("itemDestroyed", resourceRoot, ctx.itemId)
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

local function isKnockedOut(player)
    return exports.character:isKnockedOut(player) == true
end

local function isPlayerCuffed(player)
    return exports.character:isPlayerCuffed(player) == true
end

local function setPlayerCuffed(player, toggle)
    return exports.character:setPlayerCuffed(player, toggle)
end

local function isIncapacitated(player)
    return isKnockedOut(player) or isPlayerCuffed(player)
end

hands = loadFile("server/hands.lua")({
    db = db,
    net = net,
    state = state,
    geometry = geometry,
    ammo = ammo,
    apparel = apparel,
    type = itemType,
    defaultAmmo = defaultAmmo,
    charId = charId,
    toast = toast,
    world = world,
    destroy = destroy,
    isIncapacitated = isIncapacitated,
    isKnockedOut = isKnockedOut,
    isPlayerCuffed = isPlayerCuffed,
    setPlayerCuffed = setPlayerCuffed,
})

local containers = loadFile("server/containers.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    hands = hands,
    apparel = apparel,
    world = world,
    refreshPlayer = refreshPlayer,
})
hands.setContainers(containers)
-- the held items' ammo, batched (hands.queueData)
setTimer(hands.flushData, 5000, 0)
loadFile("server/use.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    destroy = destroy,
    sendInventory = containers.sendInventory,
    decodeData = hands.decodeData,
    clothes = loadFile("server/clothes.lua")({
        db = db,
        state = state,
        clothes = clothes,
        skins = skins,
        charId = charId,
        toast = toast,
        sendInventory = containers.sendInventory,
    }),
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

addEventHandler("characterSpawned", root, function()
    -- keep an existing sent-set: the client still shows those objects, the diff stays exact
    state.sent[source] = state.sent[source] or {}
    hands.rebuildCarried(source)
end)

addEventHandler("characterDied", root, function()
    -- character_death_drop already moved everything to the world; the next sync projects it
    hands.setHeld(source, nil)
    hands.setWorn(source, nil)
    hands.clearGear(source)
end)

-- /dropall (character, character_drop_all) put everything on the ground; the next world sync shows it
addEventHandler("characterItemsDropped", root, function()
    hands.setHeld(source, nil)
    hands.setWorn(source, nil)
    hands.clearGear(source)
    exports.ui:hideTip(source)
end)

-- Help tips (upstream ui/tool-tip.pwn): an item picked up shows its "<first 9 letters of the uname>_T" text for
-- 20 s with upstream's English footer; dropping one hides it. Types without a text show nothing.
local TIP_FOOTER = "Type /tooltips to toggle these messages"

addEventHandler("itemMoved", root, function(_, from, to)
    local item = state.held[source]
    if from == "world" and to == "held" and item then
        local key = item.uname:sub(1, 9) .. "_T"
        local text = exports.data:t(exports.auth:getLanguage(source), key)
        if text ~= key then
            exports.ui:showTip(source, text, TIP_FOOTER, 20000)
        end
    elseif from == "held" and to == "world" then
        exports.ui:hideTip(source)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    hands.clearHeld(source)
    hands.setWorn(source, nil)
    hands.clearGear(source)
    state.sent[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    hands.flushData(nil, true)
    for p in pairs(state.held) do
        hands.clearHeld(p)
    end
    for p in pairs(state.worn) do
        hands.setWorn(p, nil)
    end
end)

function getHeld(player)
    local item = state.held[player]
    return item and { id = item.id, uname = item.uname, hp = item.hp, data = item.data } or false
end

function refreshPlayer(player)
    if not isElement(player) then
        return false
    end
    state.sent[player] = state.sent[player] or {}
    world.syncPlayer(player)
    return true
end

-- A world item's row changed in place (door swung, tent pitched): every client that shows it gets it again.
function resendWorldItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end
    world.resendEverywhere(itemId)
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
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
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

function destroyWorldItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end
    db.exec(
        "DELETE FROM items WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { itemId },
        function(ok)
            if ok then
                world.forgetEverywhere(itemId)
                triggerEvent("itemDestroyed", resourceRoot, itemId)
            end
        end
    )
    return true
end

function destroyContainerItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end
    db.one("SELECT container_id, slot FROM items WHERE id = ?", { itemId }, function(row)
        if not row then
            return
        end
        local contId, slot = row.container_id, row.slot
        db.exec("DELETE FROM items WHERE id = ?", { itemId }, function(ok)
            if ok and contId and slot then
                db.exec(
                    "UPDATE items SET slot = slot - 1 WHERE container_id = ? AND slot > ? ORDER BY slot ASC",
                    { contId, slot },
                    function() end
                )
            end
        end)
    end)
    return true
end

function getHeld(player)
    if not isElement(player) then
        return false
    end
    return state.held[player] or false
end

function setHeld(player, item)
    if not isElement(player) then
        return false
    end
    hands.setHeld(player, item)
    return true
end

function clearHeld(player)
    if not isElement(player) then
        return false
    end
    hands.clearHeld(player)
    return true
end

function openTrunkContainer(player, vehicle, containerId, trunkTitle, trunkSize)
    if not isElement(player) or not isElement(vehicle) then
        return false
    end
    containers.openTrunk(player, vehicle, containerId, trunkTitle, trunkSize)
    return true
end

function closeTrunk(player)
    if not isElement(player) then
        return false
    end
    containers.closeTrunk(player)
    return true
end

function openWorldContainer(player, itemRow)
    if not isElement(player) or not itemRow then
        return false
    end
    containers.openWorldContainer(player, itemRow)
    return true
end

function openSupplyContainer(player, containerId, title, size, x, y, z)
    return containers.openSupplyContainer(player, containerId, title, size, x, y, z) == true
end

function closeContainer(player)
    if not isElement(player) then
        return false
    end
    containers.closeContainer(player)
    return true
end

function updateHeldData(player, nextData)
    if not isElement(player) then
        return false
    end
    local item = state.held[player]
    if not item then
        return false
    end
    item.data = nextData
    hands.publishAmmo(player, item)
    hands.queueData(item)
    triggerClientEvent(player, "heldItemChanged", player, item)
    return true
end
