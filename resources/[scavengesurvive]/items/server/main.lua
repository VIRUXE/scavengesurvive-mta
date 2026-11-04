local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
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
local armourLogic = loadFile("shared/logic/armour.lua")
local skins = loadFile("shared/logic/skins.lua")
apparel.skins = skins
local clothes = loadFile("shared/logic/clothes.lua")
local cooking = loadFile("shared/logic/cooking.lua")
local liquids = loadFile("shared/logic/liquids.lua")
local gas = loadFile("shared/logic/gas.lua")
local small = loadFile("shared/logic/smallitems.lua")
local fishing = loadFile("shared/logic/fishing.lua")
local gardening = loadFile("shared/logic/gardening.lua")
local machines = loadFile("shared/logic/machines.lua")
local furniture = loadFile("shared/logic/furniture.lua")

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
    parachute = {}, -- player -> { id, uname, hp, data } worn parachute (server/parachute.lua)
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

-- one event per procedure callback: ok and code come from the db.call result (res == false: the query itself failed)
local function logProc(kind, player, res, fields)
    fields.player = player
    fields.ok = res and res.ok or false
    fields.code = res and res.code or "DB_ERROR"
    log.event(kind, fields)
end

-- the resource that called an exported function, for the destroy events of exports with no reason of their own
local function callerName()
    return sourceResource and getResourceName(sourceResource) or nil
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "toastShown", player, code)
    end
end

-- an item the character owns: held, in the inventory, in the worn bag, or in the side container they have open
local OWNED_SQL = "SELECT i.type_uname AS uname, i.data, i.container_id FROM items i "
    .. "LEFT JOIN containers c ON c.id = i.container_id LEFT JOIN items owner ON owner.id = c.owner_item_id "
    .. "WHERE i.id = ? AND (i.holder_char_id = ? OR c.owner_char_id = ? OR owner.holder_char_id = ? "
    .. "OR i.container_id = ?)"

local world =
    loadFile("server/world.lua")({ db = db, state = state, geometry = geometry, diff = diff, charId = charId })
local hands
local armourDurability

-- Deletes an item the player owns (held, in their inventory or worn bag). cb(ok) runs only while the player exists.
-- reason is the item.destroyed log reason (used, broken, ...); by names the calling resource of an export.
local function destroy(itemId, player, cb, reason, by)
    local cid = charId(player)
    if not cid then
        return false
    end
    local held = state.held[player]
    local uname = held and held.id == itemId and held.uname or nil
    db.call("item_destroy", { itemId, cid }, function(res, ctx)
        local ok = res and res.ok or false
        logProc("item.destroyed", ctx.player, res, {
            item_id = ctx.itemId,
            uname = ctx.uname,
            reason = ctx.reason or "unknown",
            by = ctx.by,
            character_id = cid,
        })
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
    end, { player = player, itemId = itemId, cb = cb, uname = uname, reason = reason, by = by })
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

-- upstream player/disallow-actions.pwn IsBadInteract: cuffed, on staff duty, knocked out or hands up; such a player
-- picks nothing up, opens no inventory or container, takes nothing out of one and uses nothing
local function isBadInteract(player)
    if isIncapacitated(player) or exports.character:isHandsUp(player) then
        return true
    end
    local staffRes = getResourceFromName("staff")
    return staffRes ~= false and getResourceState(staffRes) == "running" and exports.staff:isOnDuty(player) == true
end

hands = loadFile("server/hands.lua")({
    db = db,
    net = net,
    state = state,
    geometry = geometry,
    ammo = ammo,
    liquids = liquids,
    apparel = apparel,
    armour = armourLogic,
    type = itemType,
    defaultAmmo = defaultAmmo,
    charId = charId,
    toast = toast,
    world = world,
    destroy = destroy,
    isIncapacitated = isIncapacitated,
    isBadInteract = isBadInteract,
    isKnockedOut = isKnockedOut,
    isPlayerCuffed = isPlayerCuffed,
    setPlayerCuffed = setPlayerCuffed,
})

local containers = loadFile("server/containers.lua")({
    small = small,
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
    isIncapacitated = isIncapacitated,
    isBadInteract = isBadInteract,
})
hands.setContainers(containers)
local armourCtx = { state = state, hands = hands, destroy = destroy, world = world, armour = armourLogic }
armourCtx.sendInventory = function(player)
    return sendInventory(player)
end
armourDurability = loadFile("server/armour.lua")(armourCtx)
local fixed = loadFile("server/fixed.lua")({ db = db, world = world, log = util.log })
local cookingCtx = { db = db, state = state, type = itemType, toast = toast, world = world, hands = hands }
cookingCtx.cooking = cooking
local cookers = loadFile("server/cooking.lua")(cookingCtx)
hands.setCooking(cookers)
-- the held items' ammo, batched (hands.queueData)
setTimer(hands.flushData, 5000, 0)
local medical = loadFile("server/medical.lua")({ db = db, state = state, destroy = destroy })
local function isOnDuty(player)
    local staffRes = getResourceFromName("staff")
    return staffRes ~= false and getResourceState(staffRes) == "running" and exports.staff:isOnDuty(player) == true
end
local cuffsCtx = { db = db, state = state, hands = hands, destroy = destroy, charId = charId, toast = toast }
cuffsCtx.isPlayerCuffed, cuffsCtx.setPlayerCuffed, cuffsCtx.isOnDuty = isPlayerCuffed, setPlayerCuffed, isOnDuty
local cuffs = loadFile("server/cuffs.lua")(cuffsCtx)
hands.setCuffs(cuffs)
-- a held item's data rewritten in place (a sip from a container): the row, the hand and the client
local function writeHeldData(player, itemId, data)
    db.exec("UPDATE items SET data = ? WHERE id = ?", { toJSON(data):sub(2, -2), itemId })
    local held = state.held[player]
    if held and held.id == itemId then
        held.data = data
        triggerClientEvent(player, "heldItemChanged", player, held)
    end
end
local drinking = loadFile("server/drinking.lua")({
    state = state,
    liquids = liquids,
    type = itemType,
    toast = toast,
    writeHeldData = writeHeldData,
})
-- the interact key released during a treatment or a drink (items/client/main.lua)
net.handler("treatmentCancelRequested", function(player)
    medical.cancel(player)
    drinking.cancel(player)
    cuffs.cancel(player)
end)
local clothesInstance = loadFile("server/clothes.lua")({
    db = db,
    state = state,
    clothes = clothes,
    skins = skins,
    charId = charId,
    toast = toast,
    sendInventory = containers.sendInventory,
    openContainerId = containers.openContainerId,
})
containers.setClothes(clothesInstance)
-- seed bags and plant pots (#142)
local garden = loadFile("server/gardening.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    toast = toast,
    world = world,
    gardening = gardening,
    liquids = liquids,
    decodeData = hands.decodeData,
    updateHeldData = function(player, data)
        return updateHeldData(player, data)
    end,
})
-- notes, signs, dice, the locator, the stun gun and the molotov (#136)
local smallItems = loadFile("server/smallitems.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    destroy = destroy,
    destroyWorldItem = function(id, reason)
        return destroyWorldItem(id, reason)
    end,
    world = world,
    updateHeldData = function(player, data)
        return updateHeldData(player, data)
    end,
    decodeData = hands.decodeData,
    small = small,
    firework = loadFile("shared/logic/firework.lua"),
    liquids = liquids,
    sendInventory = containers.sendInventory,
    ownedSql = OWNED_SQL,
    dropHeld = function(player, opts)
        return hands.dropHeld(player, opts)
    end,
    garden = garden,
})
hands.setSmall(smallItems)
-- the Parachute: worn, it is GTA's parachute weapon
local parachute = loadFile("server/parachute.lua")({
    db = db,
    net = net,
    state = state,
    charId = charId,
    toast = toast,
    destroy = destroy,
    hands = hands,
    small = small,
})
hands.setParachute(parachute)
containers.setParachute(parachute)
-- the Fishing Rod (#141)
loadFile("server/fishing.lua")({ db = db, net = net, state = state, toast = toast, world = world, fishing = fishing })
-- the scrap machine, the refining machine and the water purifier (#145)
local machinesSrv = loadFile("server/machines.lua")({
    db = db,
    net = net,
    state = state,
    type = itemType,
    toast = toast,
    world = world,
    hands = hands,
    containers = containers,
    machines = machines,
    liquids = liquids,
    decodeData = hands.decodeData,
    charId = charId,
})
hands.setMachines(machinesSrv)
containers.setMachines(machines, liquids)
-- desks, tables, the gun case and the cupboard (#148)
local furnitureCtx = { db = db, state = state, type = itemType, toast = toast, world = world, hands = hands }
furnitureCtx.furniture, furnitureCtx.decodeData, furnitureCtx.charId = furniture, hands.decodeData, charId
local furnitureSrv = loadFile("server/furniture.lua")(furnitureCtx)
hands.setFurniture(furnitureSrv)

loadFile("server/use.lua")({
    isBadInteract = isBadInteract,
    medical = medical,
    drinking = drinking,
    db = db,
    net = net,
    state = state,
    type = itemType,
    charId = charId,
    toast = toast,
    destroy = destroy,
    sendInventory = containers.sendInventory,
    decodeData = hands.decodeData,
    cooking = cooking,
    cookers = cookers,
    world = world,
    openContainerId = containers.openContainerId,
    clothes = clothesInstance,
    small = smallItems,
    parachute = parachute,
    garden = garden,
    ownedSql = OWNED_SQL,
    apparel = apparel,
    wear = containers.wear,
})

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("items") then
        return
    end
    db.settings(function(map)
        state.settings = map
    end)
    fixed.start()
    machinesSrv.start()
    -- restart: every spawned character gets its held item and worn bag back and a fresh world projection
    for _, p in ipairs(getElementsByType("player")) do
        if charId(p) then
            state.sent[p] = {}
            hands.rebuildCarried(p)
        end
    end
end)

-- MTA drops a client event the client has not added yet: a sync sent before this player's items scripts ran
-- (`restart items`, a slow download) marked ids as sent that the client never drew. Once they run, start the
-- projection from scratch.
addEventHandler("onPlayerResourceStart", root, function(res)
    if res ~= getThisResource() or not charId(source) then
        return
    end
    state.sent[source] = {}
    world.syncPlayer(source)
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
-- lang:begin
local TIP_FOOTER = "Type /tooltips to toggle these messages"
-- lang:end

addEventHandler("itemMoved", root, function(_, from, to)
    local item = state.held[source]
    if from == "world" and to == "held" and item then
        if item.uname == "Battery" then
            local level = math.floor(small.carBatteryCharge(item.id, item.data) + 0.5)
            -- a loot battery keeps the level it showed from here on: the vehicle reads it from the item's data
            if not small.hasCarBatteryCharge(item.data) then
                hands.syncHeldData(source, item, { charge = level })
            end
            triggerClientEvent(source, "toastShown", source, string.format("BATTERY_LEVEL:%d", level))
        end
        local key = item.uname:sub(1, 9) .. "_T"
        local text = exports.data:t(exports.auth:getLanguage(source), key)
        if text ~= key then
            exports.ui:showTip(source, text, lang.textFor(source, TIP_FOOTER), 20000)
        end
    elseif from == "held" and (to == "world" or to == "parachute") then
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

-- crafting: a construction tool on furniture with nothing to build goes on the furniture (#148)
function placeOnFurniture(player, furnitureId)
    furnitureId = tonumber(furnitureId)
    if not isElement(player) or not furnitureId then
        return false
    end
    return furnitureSrv.placeOn(player, furnitureId)
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
            logProc("item.created", ctx.player, res, {
                item_id = res and res.ok and res.payload.item_id or nil,
                uname = ctx.uname,
                source = "starting",
                container_id = containerId,
                character_id = cid,
            })
        end, { uname = uname, player = player })
    end
    return true
end

function destroyItem(itemId, player, cb, reason)
    itemId = tonumber(itemId)
    if not itemId or not isElement(player) then
        if cb then
            cb(false, "INVALID_ARGS")
        end
        return false
    end
    return destroy(itemId, player, cb, reason or "external", callerName())
end

function sendInventory(player)
    if isElement(player) then
        containers.sendInventory(player)
    end
end

function destroyWorldItem(itemId, reason)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end
    local by = callerName()
    db.exec(
        "DELETE FROM items WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { itemId },
        function(ok)
            if ok then
                world.forgetEverywhere(itemId)
                triggerEvent("itemDestroyed", resourceRoot, itemId)
            end
            log.event("item.destroyed", {
                item_id = itemId,
                reason = reason or "external",
                by = by,
                ok = ok,
                code = ok and "OK" or "DB_ERROR",
                where = "world",
            })
        end
    )
    return true
end

-- Staff /di: deletes every loose world item within radius of a point (one SELECT, one batched DELETE), then
-- calls cb(count). Items in containers or on characters are never touched.
function destroyWorldItemsNear(x, y, z, radius, interior, dimension, cb)
    x, y, z, radius = tonumber(x), tonumber(y), tonumber(z), tonumber(radius)
    if not x or not y or not z or not radius or radius <= 0 then
        return false
    end
    local by = callerName()
    local sql = "SELECT id FROM items WHERE x IS NOT NULL AND interior <=> ? AND dimension <=> ?"
        .. " AND x BETWEEN ? AND ? AND y BETWEEN ? AND ? AND POW(x - ?, 2) + POW(y - ?, 2) + POW(z - ?, 2) <= ?"
    local box = { x - radius, x + radius, y - radius, y + radius, x, y, z, radius * radius }
    local params = { interior, dimension, unpack(box) }
    params.n = 10
    db.query(sql, params, function(rows)
        if not rows or #rows == 0 then
            return cb and cb(0)
        end
        local ids = {}
        for _, row in ipairs(rows) do
            ids[#ids + 1] = tonumber(row.id)
        end
        local delete = "DELETE FROM items WHERE container_id IS NULL AND holder_char_id IS NULL AND id IN"
            .. " (SELECT id FROM JSON_TABLE(?, '$[*]' COLUMNS (id INT PATH '$')) j)"
        local json = toJSON(ids, true):sub(2, -2)
        db.exec(delete, { json }, function(ok)
            if not ok then
                return cb and cb(0)
            end
            for _, id in ipairs(ids) do
                world.forgetEverywhere(id)
                triggerEvent("itemDestroyed", resourceRoot, id)
            end
            log.event("item.destroyed", {
                count = #ids,
                reason = "staff",
                by = by,
                x = math.floor(x),
                y = math.floor(y),
                z = math.floor(z),
                radius = radius,
                int = interior,
                dim = dimension,
                where = "world",
            })
            if cb then
                cb(#ids)
            end
        end)
    end)
    return true
end

function forgetWorldItem(itemId)
    if world and world.forgetEverywhere then
        world.forgetEverywhere(tonumber(itemId))
    end
end

function dropHeld(player)
    if hands and hands.dropHeld then
        return hands.dropHeld(player)
    end
    return false
end

function destroyContainerItem(itemId, reason)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end
    local by = callerName()
    db.one("SELECT container_id, slot FROM items WHERE id = ?", { itemId }, function(row)
        if not row then
            return
        end
        local contId, slot = row.container_id, row.slot
        db.exec("DELETE FROM items WHERE id = ?", { itemId }, function(ok)
            log.event("item.destroyed", {
                item_id = itemId,
                container_id = contId or nil,
                reason = reason or "external",
                by = by,
                ok = ok,
                code = ok and "OK" or "DB_ERROR",
                where = "container",
            })
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

-- A Gas Bottle's gas (shared/logic/gas.lua): a random fill for one found lying about, and the kg an item's data holds.
-- A trailer's mounted bottles (vehicles/server/gasbottles.lua) keep the same {gas = kg} per mount.
function rollGasBottle()
    return { gas = gas.roll(math.random), hp = 3 }
end

function gasBottleKg(data)
    return gas.of(data)
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

-- export: a chest hit on the player's worn Armour; returns the bleed that gets through (upstream armour.pwn)
function armourHit(player, bleed, penetration)
    if not isElement(player) then
        return bleed
    end
    return armourDurability.hit(player, bleed, tonumber(penetration) or 0)
end

-- weapons: a headshot knocks the hat and mask off (hands.popGear, #137)
function popHeadgear(player)
    if not isElement(player) then
        return false
    end
    local any = false
    for _, slot in ipairs({ "hat", "mask" }) do
        if hands.popGear(player, slot) then
            any = true
        end
    end
    return any
end

-- weapons: a fist hit while holding a stun gun (server/smallitems.lua); true when the stun gun took the hit
function meleeHit(attacker, victim)
    if not isElement(attacker) or not isElement(victim) then
        return false
    end
    return smallItems.meleeHit(attacker, victim) == true
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
