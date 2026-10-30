-- Crafting: upstream's craft sets (data/generated/recipes.lua, init.pwn) used three ways.
--   combine    craft.inc: items picked with "Combine..." in the inventory, bag or an open container (or with the
--              item in hand) and crafted once they are exactly a set; the result takes their place
--   construct  craft-construct.pwn: the interact key with the set's tool in hand next to exactly its ingredients
--              on the ground; a hold, then the result stands where they lay. Its removal tool takes it apart again.
--   workbench  workbench.pwn: the interact key with the set's tool at a workbench holding exactly its ingredients;
--              a hold of 3.6 s per item, then the result sits on the workbench
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
local net = assert(loadstring(exports.lib:getModule("net"), "=lib/net.lua"))()
local util = assert(loadstring(exports.lib:getModule("util"), "=lib/util.lua"))()
db.connect("crafting")

local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
local book = craft.book(exports.data:recipes())
local MAX_SELECTION = 8 -- CRAFT_MAX_CRAFT_SET_ITEMS
local NEARBY_RADIUS = 2.5
local activeHold = {} -- player -> { timer, anim }

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function toast(player, code)
    triggerClientEvent(player, "toastShown", player, code)
end

local function itemType(uname)
    return exports.data:itemType(uname)
end

-- upstream's language line for this player (CONSTRUCTIN, DECONSTRUCT, ...)
local function text(player, key)
    local lang = resourceRunning("auth") and exports.auth:getLanguage(player) or "en"
    return exports.data:t(lang or "en", key)
end

local function typeName(uname)
    local t = itemType(uname)
    return t and t.name ~= "" and t.name or uname
end

local function decode(data)
    if type(data) == "string" and data ~= "" then
        return fromJSON(data)
    end
    return type(data) == "table" and data or nil
end

local function cancelHold(player)
    local h = activeHold[player]
    if h then
        if isTimer(h.timer) then
            killTimer(h.timer)
        end
        activeHold[player] = nil
        if isElement(player) then
            setPedAnimation(player, nil)
            triggerClientEvent(player, "craftHoldStopped", player)
        end
    end
end

-- label: the action text; fn(player) runs when the hold ends with the player still there
local function startHold(player, label, ms, anim, fn)
    cancelHold(player)
    setPedAnimation(player, anim[1], anim[2], -1, true, false, false, false)
    triggerClientEvent(player, "craftHoldStarted", player, label, ms)
    local timer = setTimer(function(pl)
        activeHold[pl] = nil
        if isElement(pl) then
            setPedAnimation(pl, nil)
            fn(pl)
        end
    end, ms, 1, player)
    activeHold[player] = { timer = timer }
end

-- the client walked off or died mid-hold (client/main.lua): upstream stops the hold when the key is let go
net.handler("craftHoldCancelled", function(player)
    cancelHold(player)
end)

addEventHandler("onPlayerQuit", root, function()
    cancelHold(source)
end)

addEventHandler("characterDied", root, function()
    cancelHold(source)
end)

local function heldUname(player)
    local held = exports.items:getHeld(player)
    return held and held.uname or nil
end

-- 1. Combine ----------------------------------------------------------------------------------------------------

-- upstream's Bottle + Bottle set keeps both bottles and creates a third, empty one (liquid-container.pwn left the
-- pouring as a TODO): the port pours the second into the first instead and creates nothing (intentional deviation)
local function pourBottles(player, items)
    local into, from = items[1], items[2]
    local t = itemType(into.uname)
    local capacity = t and t.categoryData and t.categoryData.capacity
    local a, b, code = craft.pour(decode(into.data), decode(from.data), capacity)
    if not a then
        return toast(player, code)
    end
    local rows, held = {}, exports.items:getHeld(player)
    for _, pair in ipairs({ { into, a }, { from, b } }) do
        if held and held.id == pair[1].id then
            exports.items:updateHeldData(player, pair[2])
        else
            rows[#rows + 1] = { id = pair[1].id, data = toJSON(pair[2], true) }
        end
    end
    if #rows == 0 then
        return toast(player, "LIQUID_POURED")
    end
    db.call("item_data_flush", { toJSON(rows) }, function(res, c)
        if isElement(c.player) then
            exports.items:sendInventory(c.player)
            toast(c.player, res and res.ok and "LIQUID_POURED" or "DB_ERROR")
        end
    end, { player = player })
end

local function combineResultData(recipe)
    -- locksmith.pwn OnPlayerCrafted: a Lock and Chain combined with a Locksmith Kit is cut
    if recipe.result == "WheelLock" then
        return toJSON({ cut = true }, true)
    end
    return nil
end

local function finishCombine(player, recipe, items)
    local consumed, kept = craft.split(recipe, items)
    local consumeIds, keepIds = {}, {}
    local held = exports.items:getHeld(player)
    local heldConsumed, into = false, nil
    for _, it in ipairs(consumed) do
        consumeIds[#consumeIds + 1] = it.id
        if held and it.id == held.id then
            heldConsumed = true
        else
            into = into or it.container_id
        end
    end
    for _, it in ipairs(kept) do
        keepIds[#keepIds + 1] = it.id
        into = into or it.container_id
    end
    if heldConsumed then
        into = nil -- the result takes the hand the consumed item left
    end
    local cid = charId(player)
    db.call("craft_combine", {
        cid,
        exports.items:openContainerId(player) or nil,
        toJSON(consumeIds),
        #keepIds > 0 and toJSON(keepIds) or nil,
        recipe.result,
        combineResultData(recipe),
        into,
        n = 7,
    }, function(res, c)
        if not isElement(c.player) then
            return
        end
        if not res or not res.ok then
            triggerClientEvent(c.player, "combineFinished", c.player, false)
            exports.items:sendInventory(c.player)
            return toast(c.player, res and res.code or "DB_ERROR")
        end
        local newId = tonumber(res.payload and res.payload.item_id)
        if res.payload.held == 1 or res.payload.held == true then
            db.one(
                "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                { newId },
                function(row, c2)
                    if row and isElement(c2.player) then
                        row.data = decode(row.data)
                        exports.items:setHeld(c2.player, row)
                        exports.items:sendInventory(c2.player)
                    end
                end,
                { player = c.player }
            )
        else
            exports.items:sendInventory(c.player)
        end
        triggerEvent("itemCreated", resourceRoot, newId)
        triggerClientEvent(c.player, "combineFinished", c.player, true)
        toast(c.player, "CRAFTED:" .. typeName(c.result))
    end, { player = player, result = recipe.result })
end

-- ids: the item ids picked with "Combine..." in the order picked; withHeld adds the item in hand
net.handler("combineRequested", function(player, ids, withHeld)
    if not charId(player) or type(ids) ~= "table" then
        return
    end
    local list, seen = {}, {}
    for _, v in ipairs(ids) do
        local id = tonumber(v)
        if id and not seen[id] and #list < MAX_SELECTION then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    local held = withHeld and exports.items:getHeld(player)
    if withHeld and not held then
        return toast(player, "NOT_HELD")
    end
    if #list == 0 then
        return
    end
    local marks = string.rep("?, ", #list):sub(1, -3)
    db.query(
        "SELECT id, type_uname AS uname, container_id, data FROM items WHERE container_id IS NOT NULL AND id IN ("
            .. marks
            .. ")",
        list,
        function(rows, c)
            if not isElement(c.player) then
                return
            end
            local byId = {}
            for _, r in ipairs(rows or {}) do
                byId[r.id] = r
            end
            local items, unames = {}, {}
            if c.held and not seen[c.held.id] then
                items[1] = { id = c.held.id, uname = c.held.uname, data = c.held.data }
            end
            for _, id in ipairs(c.list) do
                if not byId[id] then
                    exports.items:sendInventory(c.player)
                    return toast(c.player, "NOT_IN_CONTAINER")
                end
                items[#items + 1] = byId[id]
            end
            for i, it in ipairs(items) do
                unames[i] = it.uname
            end
            local recipe = craft.find(book, unames)
            if not recipe then
                triggerClientEvent(c.player, "combineFinished", c.player, false)
                return toast(c.player, "COMBINE_NO_MATCH")
            end
            -- craft-construct.pwn OnPlayerCraft: the sets built with a tool cannot be combined by hand
            if recipe.kind ~= "combine" then
                triggerClientEvent(c.player, "combineFinished", c.player, false)
                return toast(c.player, recipe.kind == "workbench" and "NEEDWORKBE" or "CONSTRUCT_ON_GROUND")
            end
            if recipe.result == "Bottle" then
                triggerClientEvent(c.player, "combineFinished", c.player, true)
                return pourBottles(c.player, items)
            end
            finishCombine(c.player, recipe, items)
        end,
        { player = player, list = list, held = held }
    )
end, { rate = 3 })

-- 2. Construct ----------------------------------------------------------------------------------------------------

local NEARBY_SQL = "SELECT i.id, i.type_uname AS uname, i.data, i.x, i.y, i.z FROM world_items_pos p "
    .. "JOIN items i ON i.id = p.item_id "
    .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= ? AND i.container_id IS NULL AND i.holder_char_id IS NULL "
    .. "AND IFNULL(i.interior, 0) = ? AND IFNULL(i.dimension, 0) = ?"

local function keyCode(it)
    local d = decode(it.data)
    d = type(d) == "table" and (type(d[1]) == "table" and d[1] or d) or nil
    return d and tonumber(d.code) and tonumber(d.code) ~= 0 and d or nil
end

-- locksmith.pwn OnPlayerConstructed: the copy takes the cut key's code and vehicle; the cut key is the kept one
local function keyCopy(items)
    table.sort(items, function(a, b)
        return (keyCode(a) and 1 or 0) > (keyCode(b) and 1 or 0)
    end)
    for _, it in ipairs(items) do
        local code = it.uname == "Key" and keyCode(it)
        if code then
            return toJSON({ code = code.code, model = code.model }, true)
        end
    end
    return nil
end

local function finishBuild(player, recipe, items, sourceContainer, pos, after)
    local resultData = nil
    if recipe.result == "Key" then
        resultData = keyCopy(items)
    end
    local consumed, kept = craft.split(recipe, items)
    local consumeIds, keepIds = {}, {}
    for _, it in ipairs(consumed) do
        consumeIds[#consumeIds + 1] = it.id
    end
    for _, it in ipairs(kept) do
        keepIds[#keepIds + 1] = it.id
    end
    db.call("craft_build", {
        charId(player),
        sourceContainer,
        toJSON(consumeIds),
        #keepIds > 0 and toJSON(keepIds) or nil,
        recipe.result,
        resultData,
        pos.x,
        pos.y,
        pos.z,
        pos.rz,
        getElementInterior(player),
        getElementDimension(player),
        n = 12,
    }, function(res, c)
        if res and res.ok then
            for _, id in ipairs(c.consumeIds) do
                exports.items:forgetWorldItem(id)
            end
            triggerEvent("itemCreated", resourceRoot, tonumber(res.payload.item_id))
        end
        if not isElement(c.player) then
            return
        end
        if not res or not res.ok then
            return toast(c.player, res and res.code or "DB_ERROR")
        end
        exports.items:refreshPlayer(c.player)
        exports.character:gainSkill(c.player, c.result)
        toast(c.player, "CRAFTED:" .. typeName(c.result))
        if after then
            after(c.player, tonumber(res.payload.item_id))
        end
    end, { player = player, result = recipe.result, consumeIds = consumeIds })
end

local function constructed(recipe)
    return function(player, itemId)
        if not itemId or not resourceRunning("building") then
            return
        end
        if recipe.defence then
            -- craft-construct.pwn: ConvertItemToDefenceItem(itemid, 0) lays it down built, then the tweak follows
            exports.building:buildConstructedDefence(player, itemId)
        elseif recipe.tweak then
            exports.building:tweakItem(player, itemId)
        end
    end
end

-- quiet: say nothing when the items around are no set (the interact key had other things to try)
local function tryConstruct(player, quiet)
    local px, py = getElementPosition(player)
    local tool = heldUname(player)
    db.query(
        NEARBY_SQL,
        { px, py, NEARBY_RADIUS, getElementInterior(player), getElementDimension(player) },
        function(rows, c)
            if not isElement(c.player) then
                return
            end
            rows = rows or {}
            local unames = {}
            for i, r in ipairs(rows) do
                unames[i] = r.uname
            end
            local recipe = craft.find(book, unames)
            if not recipe or recipe.kind == "combine" then
                return not c.quiet and toast(c.player, "NO_RECIPE")
            end
            if recipe.kind == "workbench" then
                return toast(c.player, "NEEDWORKBE") -- workbench.pwn OnPlayerConstruct
            end
            if recipe.tool ~= c.tool then
                return not c.quiet and toast(c.player, "NEED_TOOL")
            end
            if recipe.result == "Key" and not keyCopy(rows) then
                return toast(c.player, "LOCKKEYNCUT")
            end
            local ms = exports.character:skillTimeModifier(c.player, recipe.buildTime, recipe.result)
            startHold(c.player, text(c.player, "CONSTRUCTIN"), ms, { "BOMBER", "BOM_Plant_Loop" }, function(pl)
                if heldUname(pl) ~= recipe.tool then
                    return toast(pl, "NEED_TOOL")
                end
                local x, y, z = craft.averagePos(rows)
                local _, _, rz = getElementRotation(pl)
                finishBuild(pl, recipe, rows, nil, { x = x, y = y, z = z, rz = rz }, constructed(recipe))
            end)
        end,
        { player = player, tool = tool, quiet = quiet }
    )
end

-- 3. Deconstruct --------------------------------------------------------------------------------------------------

local function tryDeconstruct(player)
    local tool = heldUname(player)
    local targets = tool and craft.removable(book, tool) or {}
    if #targets == 0 then
        return
    end
    local px, py = getElementPosition(player)
    local marks = string.rep("?, ", #targets):sub(1, -3)
    local args = { px, py, NEARBY_RADIUS, getElementInterior(player), getElementDimension(player) }
    for _, u in ipairs(targets) do
        args[#args + 1] = u
    end
    args[#args + 1] = px
    args[#args + 1] = py
    db.one(
        NEARBY_SQL .. " AND i.type_uname IN (" .. marks .. ") ORDER BY ST_Distance(p.pos, POINT(?, ?)) ASC LIMIT 1",
        args,
        function(target, c)
            if not isElement(c.player) or not target then
                return
            end
            local recipe = craft.removal(book, target.uname, c.tool)
            if not recipe then
                return
            end
            -- removal time shortened by the skill of the item being taken apart, no gain (craft-construct.pwn)
            local ms = exports.character:skillTimeModifier(c.player, recipe.removalTime, recipe.result)
            startHold(c.player, text(c.player, "DECONSTRUCT"), ms, { "BOMBER", "BOM_Plant_Loop" }, function(pl)
                if heldUname(pl) ~= recipe.removalTool then
                    return toast(pl, "NEED_TOOL")
                end
                local back = {}
                for _, uname in ipairs(craft.returned(recipe)) do
                    back[#back + 1] = {
                        uname = uname,
                        x = target.x + math.random() * 0.6,
                        y = target.y + math.random() * 0.6,
                        z = target.z,
                        rz = math.random() * 360,
                    }
                end
                db.call("craft_deconstruct", {
                    target.id,
                    target.uname,
                    toJSON(back),
                    getElementInterior(pl),
                    getElementDimension(pl),
                }, function(res, c2)
                    if res and res.ok then
                        exports.items:forgetWorldItem(c2.id)
                        triggerEvent("itemDestroyed", resourceRoot, c2.id)
                    end
                    if isElement(c2.player) then
                        exports.items:refreshPlayer(c2.player)
                        toast(c2.player, res and res.ok and "DECONSTRUCTED" or (res and res.code or "DB_ERROR"))
                    end
                end, { player = pl, id = target.id })
            end)
        end,
        { player = player, tool = tool }
    )
end

-- 4. Workbench ----------------------------------------------------------------------------------------------------

-- row: the workbench's world item row from items' interact key ({ id, uname, x, y, z, rz, ... }). Opens it when
-- its contents are no set for the tool in hand, as upstream's OnPlayerUseItemWithItem does.
local function tryWorkbench(player, row)
    db.query(
        "SELECT i.id, i.type_uname AS uname, i.container_id FROM containers c "
            .. "JOIN items i ON i.container_id = c.id WHERE c.owner_item_id = ? ORDER BY i.slot",
        { row.id },
        function(rows, c)
            if not isElement(c.player) then
                return
            end
            rows = rows or {}
            local unames = {}
            for i, r in ipairs(rows) do
                unames[i] = r.uname
            end
            local recipe = craft.find(book, unames)
            local tool = heldUname(c.player)
            if not recipe or recipe.kind ~= "workbench" or recipe.tool ~= tool then
                return exports.items:openWorldContainer(c.player, c.row)
            end
            local ms = exports.character:skillTimeModifier(c.player, craft.workbenchTime(#rows), recipe.result)
            exports.items:closeContainer(c.player)
            local px, py = getElementPosition(c.player)
            setElementRotation(c.player, 0, 0, (-math.deg(math.atan2(c.row.x - px, c.row.y - py))) % 360)
            startHold(c.player, "Crafting " .. typeName(recipe.result), ms, { "INT_SHOP", "SHOP_CASHIER" }, function(pl)
                if heldUname(pl) ~= recipe.tool then
                    return toast(pl, "NEED_TOOL")
                end
                -- workbench.pwn _wb_CreateResult: on top of the bench, turned to face across it
                local pos = {
                    x = c.row.x,
                    y = c.row.y,
                    z = c.row.z + 0.95,
                    rz = ((c.row.rz or 0) - 95 + math.random() * 10) % 360,
                }
                finishBuild(pl, recipe, rows, rows[1].container_id, pos)
            end)
        end,
        { player = player, row = row }
    )
end

-- Exports -------------------------------------------------------------------------------------------------------

function groundCraft(player)
    if not charId(player) then
        return false
    end
    tryConstruct(player)
    return true
end

function deconstruct(player)
    if not charId(player) then
        return false
    end
    tryDeconstruct(player)
    return true
end

function workbenchCraft(player, row)
    if not charId(player) or type(row) ~= "table" or not tonumber(row.id) then
        return false
    end
    tryWorkbench(player, row)
    return true
end

-- items' interact key: a tool of a construct set in hand builds from the items on the ground (#116)
function isConstructionTool(uname)
    return book.constructTools[tostring(uname)] == true
end

util.log("crafting", "info", "crafting engine initialized with %d craft sets", #book.list)
