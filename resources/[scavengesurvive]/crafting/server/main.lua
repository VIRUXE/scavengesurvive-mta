-- Crafting system: in-hand combine, ground construction, deconstruction, and workbench crafting.
-- Ported from upstream Scavenge & Survive (core/world/craft-construct.pwn, core/item/workbench.pwn).
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
local net = assert(loadstring(exports.lib:getModule("net"), "=lib/net.lua"))()
local util = assert(loadstring(exports.lib:getModule("util"), "=lib/util.lua"))()
local lang = assert(loadstring(exports.lib:getModule("lang"), "=lib/lang.lua"))()
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
            if alreadyDone(r, c.held, row) then
                return toast(c.player, r.result.uname == "WheelLock" and "LOCKCHCUT" or "NO_RECIPE")
            end
            local resultJson = r.result.data and toJSON(r.result.data)
            -- Check consume logic
            local invContId = row.container_id
            if match.consumeB then
                exports.items:destroyItem(row.id, c.player)
            end
            if match.consumeA then
                exports.items:destroyItem(c.held.id, c.player, function(ok)
                    if not ok or not isElement(c.player) then
                        return
                    end
                    -- Created item becomes held once the previous held item has been removed from DB
                    db.call("item_create_held", { r.result.uname, c.cid }, function(res, c2)
                        if not isElement(c2.player) then
                            return
                        end
                        if res and res.ok then
                            local newId = res.payload and res.payload.item_id
                            if newId and resultJson then
                                db.exec("UPDATE items SET data = ? WHERE id = ?", { resultJson, newId })
                            end
                            if newId then
                                db.one(
                                    "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                                    { newId },
                                    function(nRow, c3)
                                        if nRow and isElement(c3.player) then
                                            if r.result.data then
                                                nRow.data = r.result.data
                                            end
                                            exports.items:setHeld(c3.player, nRow)
                                            exports.items:sendInventory(c3.player)
                                            toast(c3.player, "CRAFTED")
                                        end
                                    end,
                                    { player = c2.player }
                                )
                            end
                        else
                            toast(c2.player, res and res.code or "DB_ERROR")
                        end
                    end, { player = c.player })
                end)
            else
                -- Held tool is kept, created item goes to inventory container
                db.call("item_create_in_container", { r.result.uname, invContId }, function(res, c2)
                    if not isElement(c2.player) then
                        return
                    end
                    if res and res.ok then
                        local newId = res.payload and res.payload.item_id
                        if not (newId and resultJson) then
                            exports.items:sendInventory(c2.player)
                            return toast(c2.player, "CRAFTED")
                        end
                        -- the inventory is sent once the result's data is written, so it shows the new state
                        db.exec("UPDATE items SET data = ? WHERE id = ?", { resultJson, newId }, function(_, c3)
                            if isElement(c3.player) then
                                exports.items:sendInventory(c3.player)
                                toast(c3.player, "CRAFTED")
                            end
                        end, { player = c2.player })
                    else
                        toast(c2.player, res and res.code or "DB_ERROR")
                    end
                end, { player = c.player })
            end
        end,
        { player = player, held = held, cid = cid }
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
        local function finish(pl, rec, crz, cint, cdim, src)
            -- Destroy ingredients
            for _, it in ipairs(consumed) do
                exports.items:destroyWorldItem(it.id)
            end
            local args = { rec.result.uname, nil, nil, mx, my, mz, crz, cint, cdim, nil, nil, n = 11 }
            local ctx = { player = pl, skill = rec.result.uname, tweak = rec.tweak ~= false, defence = rec.defence }
            ctx.source = src
            local function onCreated(res, c2)
                if not isElement(c2.player) then
                    return
                end
                if res and res.ok then
                    local newId = res.payload and tonumber(res.payload.item_id)
                    if c2.source and newId then
                        db.exec("UPDATE items SET data = ? WHERE id = ?", { c2.source, newId })
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
                else
                    toast(c2.player, res and res.code or "DB_ERROR")
                end
            end
            db.call("item_create", args, onCreated, ctx)
        end
        -- the parts that get used up, as placeholders for the still-on-the-ground check
        local ids, marks = {}, {}
        for i, it in ipairs(consumed) do
            ids[i], marks[i] = tonumber(it.id), "?"
        end
        ids.n = #ids
        local stillThere = "SELECT COUNT(*) AS n FROM items WHERE container_id IS NULL AND holder_char_id IS NULL "
            .. "AND id IN ("
            .. table.concat(marks, ", ")
            .. ")"
        local timer = setTimer(function(pl)
            activeHold[pl] = nil
            if not isElement(pl) then
                return
            end
            clearHoldAnim(pl)
            local curHeld = exports.items:getHeld(pl)
            if recipe.tool and (not curHeld or curHeld.uname ~= recipe.tool) then
                return toast(pl, "NEED_TOOL")
            end
            if ids.n == 0 then
                return finish(pl, recipe, rz, int, dim, source)
            end
            -- upstream: every part must still lie in the world, or nothing is built (a part picked up mid-build
            -- would otherwise come out twice)
            db.one(stillThere, ids, function(row, c2)
                if not isElement(c2.player) or not row or tonumber(row.n) ~= ids.n then
                    return
                end
                finish(c2.player, recipe, rz, int, dim, source)
            end, { player = pl })
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
            exports.items:destroyWorldItem(tgt.id)
            -- upstream: each part at x + frandom(0.6), y + frandom(0.6), a random heading
            for _, ing in ipairs(dInfo.ingredients) do
                local x, y, prz = tgt.x + math.random() * 0.6, tgt.y + math.random() * 0.6, math.random() * 360
                local args = { ing.uname, nil, nil, x, y, tgt.z, prz, cint, cdim, nil, nil, n = 11 }
                db.call("item_create", args, function() end)
            end
            exports.items:refreshPlayer(pl)
            toast(pl, "DECONSTRUCTED")
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
                        return
                    end
                    -- upstream _wb_ClearWorkbench + _wb_CreateResult: the bench is emptied and the result lies on top
                    -- of it, z + 0.95, turned rz - 95 give or take 5 degrees. All or nothing in one statement: another
                    -- player with the bench open taking one of these meanwhile cancels the craft instead of keeping
                    -- their item and getting the result made as well
                    local ids = {}
                    for i, it in ipairs(now) do
                        ids[i] = string.format("%d", it.id)
                    end
                    local list = table.concat(ids, ",")
                    local clear = "DELETE FROM items WHERE container_id = ? AND id IN ("
                        .. list
                        .. ") AND (SELECT COUNT(*) FROM items b WHERE b.container_id = ? AND b.id IN ("
                        .. list
                        .. ")) = ?"
                    db.exec(clear, { contId, contId, #ids }, function(ok, c4, affected)
                        if not isElement(c4.player) then
                            return
                        end
                        if not ok or (tonumber(affected) or 0) ~= #ids then
                            return toast(c4.player, "NO_RECIPE")
                        end
                        exports.items:containerChanged(contId) -- whoever else has the bench open sees it empty
                        local rot = ((tonumber(wb.rz) or 0) - 95 + math.random() * 10) % 360
                        local args =
                            { recipe.result.uname, nil, nil, bx, by, bz + 0.95, rot, int, dim, nil, nil, n = 11 }
                        db.call("item_create", args, function(res, c5)
                            if not isElement(c5.player) then
                                return
                            end
                            if res and res.ok then
                                exports.items:refreshPlayer(c5.player)
                                exports.character:gainSkill(c5.player, recipe.result.uname)
                                toast(c5.player, "CRAFTED")
                            else
                                toast(c5.player, res and res.code or "DB_ERROR")
                            end
                        end, { player = c4.player })
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
