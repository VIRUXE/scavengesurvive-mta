-- Crafting system: in-hand combine, ground construction, deconstruction, and workbench crafting.
-- Ported from upstream Scavenge & Survive (core/world/craft-construct.pwn, core/item/workbench.pwn).
local db = exports.lib:getModule("db")
local net = exports.lib:getModule("net")
local util = exports.lib:getModule("util")

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
    triggerClientEvent(player, "onClientItemsToast", player, code)
end

local function cancelHold(player)
    local h = activeHold[player]
    if h then
        if isTimer(h.timer) then
            killTimer(h.timer)
        end
        activeHold[player] = nil
        triggerClientEvent(player, "onClientCraftingStopHoldAction", player)
    end
end

addEventHandler("onPlayerQuit", root, function()
    cancelHold(source)
end)

addEventHandler("onCharacterDied", root, function()
    cancelHold(source)
end)

-- 1. In-Hand Combine: Combine held item with an inventory item
net.handler("onCraftingRequestCombine", function(player, invItemId)
    local cid = charId(player)
    invItemId = tonumber(invItemId)
    if not cid or not invItemId then
        return
    end
    local held = exports.items:getHeld(player)
    if not held then
        return toast(player, "NOT_HELD")
    end
    db.one(
        "SELECT id, type_uname AS uname, container_id FROM items WHERE id = ? AND container_id IS NOT NULL",
        { invItemId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local match = craft.matchCombine(c.held.uname, row.uname)
            if not match then
                return toast(c.player, "NO_RECIPE")
            end
            local r = match.recipe
            -- Check consume logic
            local invContId = row.container_id
            if match.consumeB then
                exports.items:destroyItem(row.id, c.player)
            end
            if match.consumeA then
                exports.items:destroyItem(c.held.id, c.player)
                -- Created item becomes held
                db.call("item_create_held", { r.result.uname, c.cid }, function(res, c2)
                    if not isElement(c2.player) then
                        return
                    end
                    if res and res.ok then
                        local newId = res.payload and res.payload.item_id
                        if newId then
                            db.one(
                                "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                                { newId },
                                function(nRow, c3)
                                    if nRow and isElement(c3.player) then
                                        exports.items:setHeld(c3.player, nRow)
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
            else
                -- Held tool is kept, created item goes to inventory container
                db.call("item_create_in_container", { r.result.uname, invContId }, function(res, c2)
                    if not isElement(c2.player) then
                        return
                    end
                    if res and res.ok then
                        toast(c2.player, "CRAFTED")
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
local function tryGroundCraft(player, _cid, held, px, py, pz, rz, int, dim)
    local toolUname = held and held.uname
    local query = "SELECT i.id, i.type_uname, i.x, i.y, i.z FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= 2.5 "
        .. "AND i.container_id IS NULL AND i.holder_char_id IS NULL"
    db.query(query, { px, py }, function(rows, c)
        if not isElement(c.player) or not rows or #rows == 0 then
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
            return
        end
        local recipe = matches[1]
        cancelHold(c.player)
        triggerClientEvent(
            c.player,
            "onClientCraftingHoldAction",
            c.player,
            "Constructing " .. recipe.name,
            recipe.buildTime
        )
        local timer = setTimer(function(pl, rec, byUname, cpx, cpy, cpz, crz, cint, cdim)
            activeHold[pl] = nil
            if not isElement(pl) then
                return
            end
            local curHeld = exports.items:getHeld(pl)
            if rec.tool and (not curHeld or curHeld.uname ~= rec.tool) then
                return toast(pl, "NEED_TOOL")
            end
            -- Destroy ingredients
            for _, ing in ipairs(rec.ingredients) do
                if not ing.keep then
                    local list = byUname[ing.uname] or {}
                    for i = 1, ing.count do
                        local it = list[i]
                        if it then
                            exports.items:destroyItem(it.id, pl)
                        end
                    end
                end
            end
            -- Spawn output object 1.2m ahead
            local rad = math.rad(crz or 0)
            local dropX = cpx + 1.2 * math.sin(-rad)
            local dropY = cpy + 1.2 * math.cos(rad)
            db.call(
                "item_create",
                { rec.result.uname, 5, nil, dropX, dropY, cpz - 0.8, crz, cint, cdim, nil, nil },
                function(res, c2)
                    if not isElement(c2.player) then
                        return
                    end
                    if res and res.ok then
                        exports.items:refreshPlayer(c2.player)
                        toast(c2.player, "CRAFTED")
                    else
                        toast(c2.player, res and res.code or "DB_ERROR")
                    end
                end,
                { player = pl }
            )
        end, recipe.buildTime, 1, c.player, recipe, itemsByUname, px, py, pz, rz, int, dim)
        activeHold[c.player] = { timer = timer, action = "construct" }
    end, { player = player, toolUname = toolUname })
end

-- 3. Deconstruction: Dismantle world item with Crowbar
local function tryDeconstruct(player, _cid, held, px, py, _pz, rz, int, dim)
    if not held or held.uname ~= "Crowbar" then
        return
    end
    local query = "SELECT i.id, i.type_uname, i.x, i.y, i.z FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= 2.5 "
        .. "AND i.container_id IS NULL AND i.holder_char_id IS NULL "
        .. "ORDER BY ST_Distance(p.pos, POINT(?, ?)) ASC LIMIT 1"
    db.one(query, { px, py, px, py }, function(target, c)
        if not isElement(c.player) or not target then
            return
        end
        local info = craft.getDeconstructInfo(target.type_uname, "Crowbar")
        if not info then
            return
        end
        cancelHold(c.player)
        triggerClientEvent(
            c.player,
            "onClientCraftingHoldAction",
            c.player,
            "Deconstructing " .. target.type_uname,
            info.duration
        )
        local timer = setTimer(function(pl, tgt, dInfo, crz, cint, cdim)
            activeHold[pl] = nil
            if not isElement(pl) then
                return
            end
            local curHeld = exports.items:getHeld(pl)
            if not curHeld or curHeld.uname ~= "Crowbar" then
                return toast(pl, "NEED_TOOL")
            end
            exports.items:destroyItem(tgt.id, pl)
            for i, ing in ipairs(dInfo.ingredients or {}) do
                local ox = (i % 2 == 0) and 0.3 or -0.3
                local oy = (i > 2) and 0.3 or -0.3
                db.call(
                    "item_create",
                    { ing.uname, 5, nil, tgt.x + ox, tgt.y + oy, tgt.z, crz, cint, cdim, nil, nil },
                    function() end
                )
            end
            exports.items:refreshPlayer(pl)
            toast(pl, "DECONSTRUCTED")
        end, info.duration, 1, c.player, target, info, rz, int, dim)
        activeHold[c.player] = { timer = timer, action = "deconstruct" }
    end, { player = player })
end

-- 4. Workbench Crafting: Craft inside Workbench's 16-slot container
local function tryWorkbenchCraft(player, _cid, held, px, py)
    local query = "SELECT i.id, c.id AS cont_id FROM world_items_pos p "
        .. "JOIN items i ON i.id = p.item_id "
        .. "JOIN containers c ON c.owner_item_id = i.id "
        .. "WHERE i.type_uname = 'Workbench' AND ST_Distance(p.pos, POINT(?, ?)) <= 2.5 LIMIT 1"
    db.one(query, { px, py }, function(wb, c)
        if not isElement(c.player) or not wb then
            return
        end
        local contId = wb.cont_id
        db.query("SELECT id, type_uname FROM items WHERE container_id = ?", { contId }, function(cRows, c2)
            if not isElement(c2.player) or not cRows or #cRows == 0 then
                return
            end
            local counts = {}
            local itemsByUname = {}
            for _, r in ipairs(cRows) do
                counts[r.type_uname] = (counts[r.type_uname] or 0) + 1
                itemsByUname[r.type_uname] = itemsByUname[r.type_uname] or {}
                table.insert(itemsByUname[r.type_uname], r)
            end
            local toolUname = c2.held and c2.held.uname
            local matches = craft.matchWorkbench(counts, toolUname)
            if #matches == 0 then
                return toast(c2.player, "NO_RECIPE")
            end
            local recipe = matches[1]
            cancelHold(c2.player)
            triggerClientEvent(
                c2.player,
                "onClientCraftingHoldAction",
                c2.player,
                "Crafting " .. recipe.name,
                recipe.buildTime
            )
            local timer = setTimer(function(pl, rec, byUname, wbContId)
                activeHold[pl] = nil
                if not isElement(pl) then
                    return
                end
                -- Destroy consumed ingredients
                for _, ing in ipairs(rec.ingredients) do
                    if not ing.keep then
                        local list = byUname[ing.uname] or {}
                        for i = 1, ing.count do
                            local it = list[i]
                            if it then
                                exports.items:destroyItem(it.id, pl)
                            end
                        end
                    end
                end
                -- Spawn product inside Workbench container
                db.call("item_create_in_container", { rec.result.uname, wbContId }, function(res, c3)
                    if not isElement(c3.player) then
                        return
                    end
                    if res and res.ok then
                        toast(c3.player, "CRAFTED")
                    else
                        toast(c3.player, res and res.code or "DB_ERROR")
                    end
                end, { player = pl })
            end, recipe.buildTime, 1, c2.player, recipe, itemsByUname, contId)
            activeHold[c2.player] = { timer = timer, action = "workbench" }
        end, { player = c.player, held = c.held })
    end, { player = player, held = held })
end

net.handler("onCraftingRequestGroundCraft", function(player)
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

net.handler("onCraftingRequestDeconstruct", function(player)
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

net.handler("onCraftingRequestWorkbenchCraft", function(player)
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
    tryWorkbenchCraft(player, cid, held, px, py)
    tryGroundCraft(player, cid, held, px, py, pz, rz, int, dim)
end)

util.log("crafting", "info", "crafting engine initialized with %d recipes", #craft.RECIPES)
