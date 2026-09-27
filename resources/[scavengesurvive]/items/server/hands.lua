-- File scope: only Items.net.handler registrations (busted loads this file under the MTA mock).
local HAND_OFFSET = { 0.1, 0.35, 0.15 }
local BACK_OFFSET = { 0, -0.2, 0.25, 0, 0, 180 }
local FALLBACK_MODEL = 1271

local function baseWeapon(t)
    local w = t and t.category == "weapon" and t.categoryData and t.categoryData.baseWeapon
    return w and w > 0 and w or nil
end

-- MVP has no ammo model: an item without a stored magazine is given a full one (vanilla melee 1..15 always 1)
local function startingAmmo(t, w, data)
    local mag = tonumber(data.mag)
    if mag then
        return mag
    end
    if w <= 15 then
        return 1
    end
    return math.max(1, tonumber(t.categoryData.magSize) or 1)
end

local function decodeData(data)
    if data and data ~= false and data ~= "" then
        return fromJSON(data) or {}
    end
    return {}
end
Items.decodeData = decodeData

-- offset = { x, y, z, rx, ry, rz } relative to the player's root
local function makeAttachedObject(player, uname, offset)
    local t = Items.type(uname)
    local obj = createObject(t and t.mtaModel or FALLBACK_MODEL, 0, 0, 0)
    if not obj then
        obj = createObject(FALLBACK_MODEL, 0, 0, 0)
    end
    if not obj then
        return nil
    end
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(player))
    setElementDimension(obj, getElementDimension(player))
    attachElements(obj, player, unpack(offset))
    return obj
end

local function makeHeldObject(player, item)
    local t = Items.type(item.uname)
    local o = HAND_OFFSET
    return makeAttachedObject(
        player,
        item.uname,
        { o[1], o[2], o[3], t and t.attrx or 0, t and t.attry or 0, t and t.attrz or 0 }
    )
end

-- The worn bag is shown on the player's back (root-attached, so it does not follow the spine in animations).
function Items.setWorn(player, uname)
    local obj = Items.wornObject[player]
    if obj and isElement(obj) then
        destroyElement(obj)
    end
    Items.wornObject[player] = nil
    if uname and isElement(player) then
        Items.wornObject[player] = makeAttachedObject(player, uname, BACK_OFFSET)
    end
end

function Items.rebuildWorn(player)
    local charId = Items.charId(player)
    if not charId then
        return
    end
    Items.db.one(
        "SELECT type_uname AS uname FROM items WHERE holder_char_id = ? AND holder_kind = 'bag'",
        { charId },
        function(row, ctx)
            if not isElement(ctx.player) or row == false then
                return
            end
            Items.setWorn(ctx.player, row and row.uname or nil)
        end,
        { player = player }
    )
end

function Items.clearHeld(player)
    local obj = Items.heldObject[player]
    if obj and isElement(obj) then
        destroyElement(obj)
    end
    Items.heldObject[player] = nil
    local item = Items.held[player]
    if item and isElement(player) then
        local w = baseWeapon(Items.type(item.uname))
        if w then
            takeWeapon(player, w)
        end
    end
    Items.held[player] = nil
end

-- item = { id, uname, hp, data } or nil; the client only ever sees { id, uname, hp }
function Items.setHeld(player, item)
    Items.clearHeld(player)
    if not isElement(player) then
        return
    end
    if item then
        Items.held[player] = item
        Items.heldObject[player] = makeHeldObject(player, item)
        local t = Items.type(item.uname)
        local w = baseWeapon(t)
        if w then
            giveWeapon(player, w, startingAmmo(t, w, item.data or {}), true)
        end
    end
    triggerClientEvent(
        player,
        "onClientItemsHeld",
        player,
        item and { id = item.id, uname = item.uname, hp = item.hp } or false
    )
end

function Items.rebuildHeld(player)
    local charId = Items.charId(player)
    if not charId then
        return
    end
    Items.db.one(
        "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items "
            .. "WHERE holder_char_id = ? AND holder_kind = 'held'",
        { charId },
        function(row, ctx)
            if not isElement(ctx.player) or row == false then
                return
            end
            if row then
                row.data = decodeData(row.data)
            end
            Items.setHeld(ctx.player, row)
        end,
        { player = player }
    )
end

Items.net.handler("onItemsRequestPickup", function(player)
    local charId = Items.charId(player)
    if not charId then
        return
    end
    if Items.held[player] then
        return Items.toast(player, "HANDS_FULL")
    end
    local x, y = getElementPosition(player)
    local r = tonumber(Items.settings["items.pickup_radius"]) or 2.0
    local sql = Items.findNearestSql(x, y, r, getElementInterior(player), getElementDimension(player))
    Items.db.one(sql, {}, function(row, ctx)
        if not isElement(ctx.player) or not row then
            return
        end
        Items.db.call("item_pickup", { row.id, ctx.charId }, function(res, c)
            if res and res.ok then
                Items.forgetEverywhere(c.row.id)
            end
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return Items.toast(c.player, res and res.code or "DB_ERROR")
            end
            Items.setHeld(
                c.player,
                { id = c.row.id, uname = c.row.uname, hp = c.row.hp, data = decodeData(c.row.data) }
            )
            triggerEvent("onItemMoved", c.player, c.row.id, "world", "held")
        end, { player = ctx.player, row = row })
    end, { player = player, charId = charId })
end, { rate = 5 })

Items.net.handler("onItemsRequestDrop", function(player)
    local charId, item = Items.charId(player), Items.held[player]
    if not charId then
        return
    end
    if not item then
        return Items.toast(player, "NOT_HELD")
    end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local dx, dy = Items.geometry.dropPosition(x, y, rz, 1.0)
    local params = { item.id, charId, dx, dy, z - 0.9, rz, getElementInterior(player), getElementDimension(player) }
    Items.db.call("item_drop", params, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        if not res or not res.ok then
            return Items.toast(ctx.player, res and res.code or "DB_ERROR")
        end
        Items.setHeld(ctx.player, nil)
        Items.syncPlayer(ctx.player) -- the dropped item appears without waiting for the next tick
        triggerEvent("onItemMoved", ctx.player, ctx.itemId, "held", "world")
    end, { player = player, itemId = item.id })
end, { rate = 5 })
