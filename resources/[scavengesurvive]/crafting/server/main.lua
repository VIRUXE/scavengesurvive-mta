-- Crafting system: in-hand combine, ground construction, deconstruction, and workbench crafting.
-- Ported from upstream Scavenge & Survive (core/world/craft-construct.pwn, core/item/workbench.pwn).
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
local net = assert(loadstring(exports.lib:getModule("net"), "=lib/net.lua"))()
local util = assert(loadstring(exports.lib:getModule("util"), "=lib/util.lua"))()
local lang = assert(loadstring(exports.lib:getModule("lang"), "=lib/lang.lua"))()
local log = assert(loadstring(exports.lib:getModule("log"), "=lib/log.lua"))()
db.connect("crafting")

local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
local activeHold = {} -- player -> { timer = timer, action = string }

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function toast(player, code)
    triggerClientEvent(player, "toastShown", player, code)
end

-- the end of a craft that asked the database for its result: crafting.finished or crafting.failed with the recipe,
-- the input unames and the output, plus the item.created of the result. fields: recipe, mode, inputs, input_ids,
-- output_uname and optionally x y z int dim; ok, code and output_id come from the db.call result (false = DB failure)
local function logCraft(player, res, fields)
    local ok = res and res.ok or false
    fields.player = player
    fields.ok = ok
    fields.code = res and res.code or "DB_ERROR"
    fields.output_id = ok and res.payload and tonumber(res.payload.item_id) or nil
    log.event(ok and "crafting.finished" or "crafting.failed", fields, fields.code == "DB_ERROR" and "warn" or "info")
    log.event("item.created", {
        player = player,
        item_id = fields.output_id,
        uname = fields.output_uname,
        source = "craft",
        recipe = fields.recipe,
        ok = ok,
        code = fields.code,
        x = fields.x,
        y = fields.y,
        z = fields.z,
        int = fields.int,
        dim = fields.dim,
    })
end

-- a craft that stopped before the database was asked (missing tool, parts moved, set changed)
local function logCraftRefused(player, code, fields)
    fields.player = player
    fields.ok = false
    fields.code = code
    log.event("crafting.failed", fields)
end

-- a Key row's cut code (data as the vehicles resource writes it, toJSON({ code, model })), or nil for a blank key
local function keyCode(data)
    local t = type(data) == "string" and fromJSON(data)
    if type(t) == "table" and type(t[1]) == "table" then
        t = t[1]
    end
    return type(t) == "table" and tonumber(t.code) or nil
end

-- an item's data as a table (a row's JSON string or the held item's table, either JSON shape)
local function dataTable(data)
    local t = type(data) == "string" and fromJSON(data) or data
    if type(t) == "table" and type(t[1]) == "table" then
        t = t[1]
    end
    return type(t) == "table" and t or {}
end

-- how many of each type a list of item rows holds: { uname = n }
local function rowCounts(rows)
    local out = {}
    for _, r in ipairs(rows) do
        out[r.type_uname] = (out[r.type_uname] or 0) + 1
    end
    return out
end

-- a recipe whose result has data (the Lock and Chain's cut) refuses an ingredient of the result's type that already
-- has it: cutting a cut lock would only burn the kit
local function alreadyDone(r, a, b)
    local want = r.result.data
    if not want then
        return false
    end
    for _, it in ipairs({ a, b }) do
        if it.uname == r.result.uname then
            local d = dataTable(it.data)
            for k, v in pairs(want) do
                if d[k] == v then
                    return true
                end
            end
        end
    end
    return false
end

-- upstream craft-construct.pwn plays BOMBER/BOM_Plant_Loop while a construction or removal holds and clears it after
local function playHoldAnim(player)
    setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
end

local function clearHoldAnim(player)
    if isElement(player) then
        setPedAnimation(player)
    end
end

local function cancelHold(player)
    local h = activeHold[player]
    if h then
        if isTimer(h.timer) then
            killTimer(h.timer)
        end
        activeHold[player] = nil
        if h.anim then
            clearHoldAnim(player)
        end
        triggerClientEvent(player, "craftHoldStopped", player)
    end
end

addEventHandler("onPlayerQuit", root, function()
    cancelHold(source)
end)

addEventHandler("characterDied", root, function()
    cancelHold(source)
end)

-- 1. In-Hand Combine: Combine held item with an inventory item
net.handler("combineRequested", function(player, invItemId)
    local cid = charId(player)
    invItemId = tonumber(invItemId)
    if not cid or not invItemId then
        return
    end
    local held = exports.items:getHeld(player)
    if not held then
        return toast(player, "NOT_HELD")
    end
    local openId = exports.items:getOpenContainerId(player) or -1
    -- only an item in the character's own inventory or worn bag: item_destroy cannot consume one from a trunk, box
    -- or crate (the result was made and the item stayed), and a stale list or forged id must not reach anyone else's
    db.one(
        "SELECT i.id, i.type_uname AS uname, i.container_id, i.data FROM items i "
            .. "JOIN containers c ON c.id = i.container_id LEFT JOIN items owner ON owner.id = c.owner_item_id "
            .. "WHERE i.id = ? AND (c.owner_char_id = ? OR owner.holder_char_id = ?)",
        { invItemId, cid, cid },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local match = craft.matchCombine(c.held.uname, row.uname)
            if not match then
                local heldType = exports.data:itemType(c.held.uname)
                local invType = exports.data:itemType(row.uname)
                local heldExp = heldType and heldType.explosive
                local invExp = invType and invType.explosive
                if
                    (c.held.uname == "MobilePhone" and invExp and invExp.trigger == "RADIO")
                    or (row.uname == "MobilePhone" and heldExp and heldExp.trigger == "RADIO")
                then
                    local expRes = getResourceFromName("explosives")
                    if expRes and getResourceState(expRes) == "running" then
                        return exports.explosives:linkPhoneBomb(c.player, c.held, row)
                    end
                end
                return toast(c.player, "NO_RECIPE")
            end
            local r = match.recipe
            local inputs = { c.held.uname, row.uname }
            if alreadyDone(r, c.held, row) then
                logCraftRefused(c.player, "ALREADY_DONE", {
                    recipe = r.name,
                    mode = "combine",
                    inputs = inputs,
                    input_ids = { c.held.id, row.id },
                    output_uname = r.result.uname,
                })
                return toast(c.player, r.result.uname == "WheelLock" and "LOCKCHCUT" or "NO_RECIPE")
            end
            local logFields = {
                recipe = r.name,
                mode = "combine",
                inputs = inputs,
                input_ids = { c.held.id, row.id },
                output_uname = r.result.uname,
                character_id = c.cid,
            }
            local resultJson = r.result.data and toJSON(r.result.data) or nil
            -- one craft_combine call: the used-up inputs go and the result appears (in the hand when the held one
            -- is used up, else in the other's container) together, or nothing changes; two separate destroys and a
            -- create could leave one input gone with no result, or a result with an input kept
            local params = {
                c.cid,
                c.held.id,
                row.id,
                c.openId > 0 and c.openId or nil,
                match.consumeA and 1 or 0,
                match.consumeB and 1 or 0,
                r.result.uname,
                resultJson,
                n = 8,
            }
            db.call("craft_combine", params, function(res, c2)
                logCraft(c2.player, res, logFields)
                if not isElement(c2.player) then
                    return
                end
                if not res or not res.ok then
                    return toast(c2.player, res and res.code or "DB_ERROR")
                end
                local p = res.payload or {}
                local newId = tonumber(p.item_id)
                if match.consumeA then
                    triggerEvent("itemDestroyed", resourceRoot, c.held.id)
                end
                if match.consumeB then
                    triggerEvent("itemDestroyed", resourceRoot, row.id)
                end
                if newId then
                    triggerEvent("itemCreated", resourceRoot, newId)
                end
                if tonumber(p.held) == 1 and newId then
                    local def = exports.data:itemType(r.result.uname)
                    exports.items:setHeld(c2.player, {
                        id = newId,
                        uname = r.result.uname,
                        hp = def and def.maxHitpoints or 5,
                        data = r.result.data or {},
                    })
                end
                exports.items:sendInventory(c2.player)
                toast(c2.player, "CRAFTED")
            end, { player = c.player })
        end,
        { player = player, held = held, cid = cid, openId = openId }
    )
end, { rate = 3 })

-- 2. Ground Construction: Combine ground ingredients with held tool
-- furnitureId (items, #148): the desk or table the interact key was on; with nothing to build the tool goes on it
local function tryGroundCraft(player, _cid, held, px, py, pz, rz, int, dim, quiet, furnitureId)
    local toolUname = held and held.uname
    local query = "SELECT i.id, i.type_uname, i.x, i.y, i.z, i.data FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= 2.5 "
        .. "AND i.container_id IS NULL AND i.holder_char_id IS NULL "
        .. "AND IFNULL(i.interior, 0) = ? AND IFNULL(i.dimension, 0) = ?"
    db.query(query, { px, py, int or 0, dim or 0 }, function(rows, c)
        if not isElement(c.player) then
            return
        end
        if not rows or #rows == 0 then
            if c.furnitureId then
                exports.items:placeOnFurniture(c.player, c.furnitureId)
            end
            return
        end
        local counts = {}
        local itemsByUname = {}
        for _, r in ipairs(rows) do
            counts[r.type_uname] = (counts[r.type_uname] or 0) + 1
            itemsByUname[r.type_uname] = itemsByUname[r.type_uname] or {}
            table.insert(itemsByUname[r.type_uname], r)
        end
        local matches = craft.matchGround(counts, c.toolUname)
        if #matches == 0 then
            if c.furnitureId then
                return exports.items:placeOnFurniture(c.player, c.furnitureId)
            end
            if c.quiet then
                return
            end
            -- upstream workbench.pwn OnPlayerConstruct: a workbench set on the ground with its tool says so
            if craft.matchNeedsWorkbench(counts, c.toolUname) then
                local code = exports.auth:getLanguage(c.player) or "en"
                return toast(c.player, exports.data:t(code, "NEEDWORKBE"))
            end
            return toast(c.player, "NO_RECIPE")
        end
        local recipe = matches[1]
        -- a key copy uses up a blank key first and keeps the cut one, whose data the copy then takes
        local source
        if recipe.copyData then
            local list = itemsByUname[recipe.copyData]
            table.sort(list, function(a, b)
                return (keyCode(a.data) and 1 or 0) < (keyCode(b.data) and 1 or 0)
            end)
            source = keyCode(list[#list].data) and list[#list].data or nil
        end
        -- the rows the set takes: consumed ones from the front of each type's list (the blank keys), kept ones from
        -- the back (the cut key)
        local used, consumed = {}, {}
        for _, ing in ipairs(recipe.ingredients) do
            local list = itemsByUname[ing.uname] or {}
            for i = 1, ing.count do
                local it = ing.keep and list[#list + 1 - i] or list[i]
                if it then
                    used[#used + 1] = it
                    if not ing.keep then
                        consumed[#consumed + 1] = it
                    end
                end
            end
        end
        local inputNames, consumedIds = {}, {}
        for i, it in ipairs(used) do
            inputNames[i] = it.type_uname
        end
        for i, it in ipairs(consumed) do
            consumedIds[i] = it.id
        end
        -- upstream craft-construct.pwn OnHoldActionFinish: the result stands at the mean position of the parts
        local sx, sy, sz, n = 0, 0, 0, 0
        for _, it in ipairs(used) do
            local ix, iy, iz = tonumber(it.x), tonumber(it.y), tonumber(it.z)
            if ix and iy and iz then
                sx, sy, sz, n = sx + ix, sy + iy, sz + iz, n + 1
            end
        end
        local mx, my, mz = px, py, pz - 0.8
        if n > 0 then
            mx, my, mz = sx / n, sy / n, sz / n
        end
        cancelHold(c.player)
        -- upstream craft-construct.pwn: the skill is the result's uniqueid, its value shortens the build time
        local ms = exports.character:skillTimeModifier(c.player, recipe.buildTime, recipe.result.uname)
        local label = lang.formatFor(c.player, "Constructing %s", lang.itemName(recipe.result.uname, c.player))
        triggerClientEvent(c.player, "craftHoldStarted", c.player, label, ms)
        playHoldAnim(c.player)
        -- the parts that get used up, as the JSON array craft_ground takes
        local idsJson = "[" .. table.concat(consumedIds, ",") .. "]"
        local function finish(pl, rec, crz, cint, cdim, src)
            -- one craft_ground call: upstream's rule that every part must still lie there, or nothing is built (a
            -- part picked up mid-build would otherwise come out twice), checked and acted on in one transaction
            local args = { idsJson, rec.result.uname, src, mx, my, mz, crz, cint, cdim, n = 9 }
            local ctx = { player = pl, skill = rec.result.uname, tweak = rec.tweak ~= false, defence = rec.defence }
            ctx.logFields = {
                recipe = rec.name,
                mode = "ground",
                inputs = inputNames,
                input_ids = consumedIds,
                output_uname = rec.result.uname,
                tool = rec.tool,
                x = math.floor(mx),
                y = math.floor(my),
                z = math.floor(mz),
                int = cint,
                dim = cdim,
            }
            local function onCreated(res, c2)
                logCraft(c2.player, res, c2.logFields)
                if not isElement(c2.player) then
                    return
                end
                if res and res.ok then
                    local newId = res.payload and tonumber(res.payload.item_id)
                    for _, id in ipairs(consumedIds) do
                        exports.items:forgetWorldItem(id)
                        triggerEvent("itemDestroyed", resourceRoot, id)
                    end
                    if newId then
                        triggerEvent("itemCreated", resourceRoot, newId)
                    end
                    exports.items:refreshPlayer(c2.player)
                    exports.character:gainSkill(c2.player, c2.skill)
                    toast(c2.player, "CRAFTED")
                    -- upstream: the builder nudges the new item into place (building, #133), a set marked
                    -- .defence = true becoming a defence lying flat first (ConvertItemToDefenceItem, pose 0)
                    local building = c2.tweak and newId and getResourceFromName("building")
                    if building and getResourceState(building) == "running" then
                        exports.building:tweakItem(c2.player, newId, c2.defence)
                    end
                elseif res and res.code == "PARTS_MOVED" then
                    return -- a part left the ground during the hold: nothing is built, nothing is lost
                else
                    toast(c2.player, res and res.code or "DB_ERROR")
                end
            end
            db.call("craft_ground", args, onCreated, ctx)
        end
        local timer = setTimer(function(pl)
            activeHold[pl] = nil
            if not isElement(pl) then
                return
            end
            clearHoldAnim(pl)
            local curHeld = exports.items:getHeld(pl)
            if recipe.tool and (not curHeld or curHeld.uname ~= recipe.tool) then
                logCraftRefused(pl, "NEED_TOOL", {
                    recipe = recipe.name,
                    mode = "ground",
                    inputs = inputNames,
                    output_uname = recipe.result.uname,
                    tool = recipe.tool,
                })
                return toast(pl, "NEED_TOOL")
            end
            finish(pl, recipe, rz, int, dim, source)
        end, ms, 1, c.player)
        activeHold[c.player] = { timer = timer, action = "construct", anim = true }
    end, { player = player, toolUname = toolUname, quiet = quiet, furnitureId = furnitureId })
end

-- 3. Deconstruction: Dismantle world item with Crowbar
local CROWBAR_TARGETS = "'" .. table.concat(craft.deconstructables("Crowbar"), "', '") .. "'"

local function tryDeconstruct(player, _cid, held, px, py, _pz, _rz, int, dim)
    if not held or held.uname ~= "Crowbar" then
        return
    end
    local query = "SELECT i.id, i.type_uname, i.x, i.y, i.z FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= 2.5 "
        .. "AND i.type_uname IN ("
        .. CROWBAR_TARGETS
        .. ") AND i.container_id IS NULL AND i.holder_char_id IS NULL "
        .. "AND IFNULL(i.interior, 0) = ? AND IFNULL(i.dimension, 0) = ? "
        .. "ORDER BY ST_Distance(p.pos, POINT(?, ?)) ASC LIMIT 1"
    db.one(query, { px, py, int or 0, dim or 0, px, py }, function(target, c)
        if not isElement(c.player) or not target then
            return
        end
        local info = craft.getDeconstructInfo(target.type_uname, "Crowbar")
        if not info then
            return
        end
        cancelHold(c.player)
        -- upstream craft-construct.pwn: removal time shortened by the skill of the item being taken apart, no gain
        local ms = exports.character:skillTimeModifier(c.player, info.duration, target.type_uname)
        local label = lang.formatFor(c.player, "Deconstructing %s", lang.itemName(target.type_uname, c.player))
        triggerClientEvent(c.player, "craftHoldStarted", c.player, label, ms)
        playHoldAnim(c.player)
        local timer = setTimer(function(pl, tgt, dInfo, cint, cdim)
            activeHold[pl] = nil
            if not isElement(pl) then
                return
            end
            clearHoldAnim(pl)
            local curHeld = exports.items:getHeld(pl)
            if not curHeld or curHeld.uname ~= "Crowbar" then
                return toast(pl, "NEED_TOOL")
            end
            -- upstream: each part at x + frandom(0.6), y + frandom(0.6), a random heading; one craft_deconstruct
            -- call takes the item down and lays the parts out together, and refuses a bench, locker or machine
            -- that still holds something (what it holds would go with it) or one carried off during the hold
            local parts, spots = {}, {}
            for _, ing in ipairs(dInfo.ingredients) do
                parts[#parts + 1] = ing.uname
                spots[#spots + 1] = {
                    u = ing.uname,
                    x = tgt.x + math.random() * 0.6,
                    y = tgt.y + math.random() * 0.6,
                    z = tgt.z,
                    rz = math.random() * 360,
                    int = cint,
                    dim = cdim,
                }
            end
            local partsJson = #spots > 0 and toJSON(spots, true):sub(2, -2) or "[]"
            db.call("craft_deconstruct", { tgt.id, partsJson }, function(res)
                local ok = res and res.ok or false
                local payload = ok and res.payload or {}
                log.event("crafting.finished", {
                    player = isElement(pl) and pl or nil,
                    recipe = dInfo.recipe.name,
                    mode = "deconstruct",
                    inputs = { tgt.type_uname },
                    input_ids = { tgt.id },
                    output_uname = parts,
                    tool = "Crowbar",
                    ok = ok,
                    code = res and res.code or "DB_ERROR",
                }, ok and "info" or "warn")
                if not ok then
                    if isElement(pl) and res and res.code == "CONTAINER_NOT_EMPTY" then
                        toast(pl, "CONTAINER_NOT_EMPTY")
                    end
                    return
                end
                log.event("item.created", {
                    player = isElement(pl) and pl or nil,
                    first_id = tonumber(payload.first) or nil,
                    count = tonumber(payload.count) or 0,
                    uname = parts,
                    source = "deconstruct",
                    ok = true,
                    code = "OK",
                    x = math.floor(tgt.x),
                    y = math.floor(tgt.y),
                    z = math.floor(tgt.z),
                })
                exports.items:forgetWorldItem(tgt.id)
                triggerEvent("itemDestroyed", resourceRoot, tgt.id)
                if isElement(pl) then
                    exports.items:refreshPlayer(pl)
                    toast(pl, "DECONSTRUCTED")
                end
            end)
        end, ms, 1, c.player, target, info, int, dim)
        activeHold[c.player] = { timer = timer, action = "deconstruct", anim = true }
    end, { player = player })
end

-- 4. Workbench Crafting: Craft from what lies in a Workbench's 16-slot container
-- onMiss(player, why) runs when there is nothing to build (no bench, an empty one, or why == "recipe": contents no
-- recipe takes); the default tells `items` through workbenchRecipeMissed, which opens the container as upstream does
local function tryWorkbenchCraft(player, _cid, held, px, py, onMiss)
    onMiss = onMiss or function(pl)
        triggerEvent("workbenchRecipeMissed", pl)
    end
    local query = "SELECT i.id, i.x, i.y, i.z, i.rz, c.id AS cont_id FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "JOIN containers c ON c.owner_item_id = i.id "
        .. "WHERE i.type_uname = 'Workbench' AND ST_Distance(p.pos, POINT(?, ?)) <= 2.5 "
        .. "AND IFNULL(i.interior, 0) = ? AND IFNULL(i.dimension, 0) = ? LIMIT 1"
    local int, dim = getElementInterior(player), getElementDimension(player)
    db.one(query, { px, py, int, dim }, function(wb, c)
        if not isElement(c.player) then
            return
        end
        if not wb then
            return onMiss(c.player)
        end
        local contId = wb.cont_id
        local contents = "SELECT id, type_uname FROM items WHERE container_id = ?"
        db.query(contents, { contId }, function(cRows, c2)
            if not isElement(c2.player) then
                return
            end
            if not cRows or #cRows == 0 then
                return onMiss(c2.player)
            end
            local toolUname = c2.held and c2.held.uname
            local recipe = craft.matchWorkbench(rowCounts(cRows), toolUname)[1]
            if not recipe then
                return onMiss(c2.player, "recipe")
            end
            cancelHold(c2.player)
            -- upstream workbench.pwn: 3.6 s per item on the bench, shortened by the skill of the result's uniqueid
            local ms = exports.character:skillTimeModifier(c2.player, craft.workbenchTime(recipe), recipe.result.uname)
            local label = lang.formatFor(c2.player, "Crafting %s", lang.itemName(recipe.result.uname, c2.player))
            triggerClientEvent(c2.player, "craftHoldStarted", c2.player, label, ms)
            -- upstream _wb_StartWorking: the player turns to the bench and works the till (INT_SHOP/SHOP_CASHIER)
            local bx, by, bz = tonumber(wb.x) or px, tonumber(wb.y) or py, tonumber(wb.z) or 0
            local wpx, wpy = getElementPosition(c2.player)
            setElementRotation(c2.player, 0, 0, (-math.deg(math.atan2(bx - wpx, by - wpy))) % 360)
            setPedAnimation(c2.player, "INT_SHOP", "SHOP_CASHIER", -1, true, false, false, false)
            local timer = setTimer(function(pl)
                activeHold[pl] = nil
                if not isElement(pl) then
                    return
                end
                clearHoldAnim(pl)
                -- the bench must still hold that very set: an item taken out mid-craft cancels it
                db.query(contents, { contId }, function(now, c3)
                    if not isElement(c3.player) or not now then
                        return
                    end
                    if craft.matchWorkbench(rowCounts(now), toolUname)[1] ~= recipe then
                        logCraftRefused(c3.player, "SET_CHANGED", {
                            recipe = recipe.name,
                            mode = "workbench",
                            workbench_id = wb.id,
                            output_uname = recipe.result.uname,
                        })
                        return
                    end
                    -- upstream _wb_ClearWorkbench + _wb_CreateResult: the bench is emptied and the result lies on top
                    -- of it, z + 0.95, turned rz - 95 give or take 5 degrees; one craft_workbench call takes that
                    -- very set out and lays the result down together, SET_CHANGED (nothing touched) when a part
                    -- left the bench between this read and the call
                    local inputNames, inputIds = {}, {}
                    for i, it in ipairs(now) do
                        inputNames[i], inputIds[i] = it.type_uname, string.format("%d", it.id)
                    end
                    local rot = ((tonumber(wb.rz) or 0) - 95 + math.random() * 10) % 360
                    local idsJson = "[" .. table.concat(inputIds, ",") .. "]"
                    local args = { contId, idsJson, recipe.result.uname, bx, by, bz + 0.95, rot, int, dim }
                    db.call("craft_workbench", args, function(res, c4)
                        logCraft(c4.player, res, {
                            recipe = recipe.name,
                            mode = "workbench",
                            inputs = inputNames,
                            input_ids = inputIds,
                            output_uname = recipe.result.uname,
                            workbench_id = wb.id,
                            x = math.floor(bx),
                            y = math.floor(by),
                            z = math.floor(bz + 0.95),
                            int = int,
                            dim = dim,
                        })
                        if res and res.ok then
                            exports.items:refreshContainerViewers(contId) -- the bench shows empty to whoever looks
                            if res.payload and tonumber(res.payload.item_id) then
                                triggerEvent("itemCreated", resourceRoot, tonumber(res.payload.item_id))
                            end
                        end
                        if not isElement(c4.player) then
                            return
                        end
                        if res and res.ok then
                            exports.items:refreshPlayer(c4.player)
                            exports.character:gainSkill(c4.player, recipe.result.uname)
                            toast(c4.player, "CRAFTED")
                        elseif res and res.code == "SET_CHANGED" then
                            return -- a part left the bench after the read: nothing is made, nothing is lost
                        else
                            toast(c4.player, res and res.code or "DB_ERROR")
                        end
                    end, { player = c3.player })
                end, { player = pl })
            end, ms, 1, c2.player)
            activeHold[c2.player] = { timer = timer, action = "workbench", anim = true }
        end, { player = c.player, held = c.held })
    end, { player = player, held = held })
end

net.handler("groundCraftRequested", function(player)
    local cid = charId(player)
    if not cid then
        return
    end
    local held = exports.items:getHeld(player)
    local px, py, pz = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    tryGroundCraft(player, cid, held, px, py, pz, rz, int, dim)
end, { rate = 3 })

net.handler("deconstructRequested", function(player)
    local cid = charId(player)
    if not cid then
        return
    end
    local held = exports.items:getHeld(player)
    local px, py, pz = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    tryDeconstruct(player, cid, held, px, py, pz, rz, int, dim)
end, { rate = 3 })

net.handler("workbenchCraftRequested", function(player)
    local cid = charId(player)
    if not cid then
        return
    end
    local held = exports.items:getHeld(player)
    local px, py = getElementPosition(player)
    tryWorkbenchCraft(player, cid, held, px, py)
end, { rate = 3 })

addCommandHandler("craft", function(player)
    local cid = charId(player)
    if not cid then
        return
    end
    local held = exports.items:getHeld(player)
    local px, py, pz = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    if held and held.uname == "Crowbar" then
        return tryDeconstruct(player, cid, held, px, py, pz, rz, int, dim)
    end
    tryWorkbenchCraft(player, cid, held, px, py, function(pl, why)
        if why == "recipe" then
            toast(pl, "NO_RECIPE")
        end
    end)
    tryGroundCraft(player, cid, held, px, py, pz, rz, int, dim, true) -- the workbench path already said NO_RECIPE
end)

function groundCraft(player, furnitureId)
    local cid = charId(player)
    if not cid then
        return false
    end
    local held = exports.items:getHeld(player)
    local px, py, pz = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    tryGroundCraft(player, cid, held, px, py, pz, rz, int, dim, false, tonumber(furnitureId))
    return true
end

function deconstruct(player)
    local cid = charId(player)
    if not cid then
        return false
    end
    local held = exports.items:getHeld(player)
    local px, py, pz = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    tryDeconstruct(player, cid, held, px, py, pz, rz, int, dim)
    return true
end

function workbenchCraft(player)
    local cid = charId(player)
    if not cid then
        return false
    end
    local held = exports.items:getHeld(player)
    local px, py = getElementPosition(player)
    tryWorkbenchCraft(player, cid, held, px, py)
    return true
end

-- items' interact key: a tool of a ground recipe in hand builds from the items on the ground (#116)
local GROUND_TOOLS = craft.groundTools()
function isConstructionTool(uname)
    return GROUND_TOOLS[tostring(uname)] == true
end

util.log("crafting", "info", "crafting engine initialized with %d recipes", #craft.RECIPES)
