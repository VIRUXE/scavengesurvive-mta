-- File scope: only Items.net.handler registrations (busted loads this file under the MTA mock).
-- What a player carries is published as protected element data ("items.held" / "items.bag" = type uname or
-- false); every client draws its own bone-attached objects from it (client/attach.lua).
local VANILLA_MELEE_MAX = 15

local function baseWeapon(t)
    local w = t and t.category == "weapon" and t.categoryData and t.categoryData.baseWeapon
    return w and w > 0 and w or nil
end

-- The MVP has no ammo or reload model, so a firearm without data.mag is held with a full magazine
-- (GTA will not fire a weapon given with 0 rounds). Vanilla melee ids always get 1.
local function ammoFor(t, data)
    local mag = tonumber(data and data.mag)
    if mag and mag > 0 then
        return mag
    end
    local w = baseWeapon(t)
    if w and w <= VANILLA_MELEE_MAX then
        return 1
    end
    local size = tonumber(t and t.categoryData and t.categoryData.magSize)
    return (size and size > 0) and size or 1
end
Items.ammoFor = ammoFor

local function decodeData(data)
    if data and data ~= false and data ~= "" then
        return fromJSON(data) or {}
    end
    return {}
end
Items.decodeData = decodeData

local function publish(player, key, item)
    if isElement(player) then
        setElementData(player, key, item and item.uname or false, "broadcast", "deny")
    end
end
Items.publish = publish

-- item = { id, uname, hp, data } or nil: the bag worn on the back
function Items.setWorn(player, item)
    Items.worn[player] = item
    publish(player, "items.bag", item)
end

function Items.clearHeld(player)
    publish(player, "items.held", nil)
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
        publish(player, "items.held", item)
        local t = Items.type(item.uname)
        local w = baseWeapon(t)
        if w then
            giveWeapon(player, w, ammoFor(t, item.data), true)
        end
    end
    triggerClientEvent(
        player,
        "onClientItemsHeld",
        player,
        item and { id = item.id, uname = item.uname, hp = item.hp } or false
    )
end

-- Restores the held item and the worn bag from the DB (spawn and resource restart).
function Items.rebuildCarried(player)
    local charId = Items.charId(player)
    if not charId then
        return
    end
    Items.db.query(
        "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind FROM items "
            .. "WHERE holder_char_id = ? AND holder_kind IN ('held', 'bag')",
        { charId },
        function(rows, ctx)
            if not isElement(ctx.player) or rows == false then
                return
            end
            local held, bag
            for _, row in ipairs(rows) do
                row.data = decodeData(row.data)
                if row.kind == "bag" then
                    bag = row
                else
                    held = row
                end
            end
            Items.setHeld(ctx.player, held)
            Items.setWorn(ctx.player, bag)
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
