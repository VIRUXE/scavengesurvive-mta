-- Server side of item tweaking (upstream core/world/item-tweak.pwn): one item per player, the build position as the
-- origin, every click re-read from the row and written back as one autocommitted UPDATE (the items triggers keep
-- world_items_pos in step), the world item re-sent to the clients that see it. The tweak ends with Done, or when
-- the builder quits, dies, gets into a vehicle or starts anything that moves an item (hud/client/keys.lua ends it
-- before dropping, putting away or opening the inventory, as upstream's hooks did).
-- ctx = { db, net, util, defences, tweak, decodeData, toast, DEFENCE_ROW }
return function(ctx)
    local db, net, util = ctx.db, ctx.net, ctx.util
    local defences, tweak = ctx.defences, ctx.tweak
    local decodeData, toast = ctx.decodeData, ctx.toast
    local tweaks = {} -- player -> { id, uname, ox, oy, oz, interior, dimension, arrow }
    local M = {}

    local function lang(player)
        return exports.auth:getLanguage(player) or "en"
    end

    local function text(player, key)
        return exports.data:t(lang(player), key)
    end

    local function itemType(uname)
        return exports.data:itemType(uname)
    end

    -- the heading of a row's front (the arrow's direction), from the stored rz less its built pose
    local function headingOf(row)
        local t = itemType(row.type_uname)
        local st = defences.state(decodeData(row.data))
        return tweak.heading(row.rz, t and t.defence, st and st.pose)
    end

    function M.isTweaking(player)
        return tweaks[player] ~= nil
    end

    -- Starts tweaking row (DEFENCE_ROW fields) for its builder; arrow marks a built defence (upstream's arrow
    -- object shows the front and the vulnerable sides). An earlier tweak of the player's ends first.
    function M.start(player, row, arrow)
        if not isElement(player) or not row then
            return false
        end
        if tweaks[player] then
            M.commit(player)
        end
        tweaks[player] = {
            id = row.id,
            uname = row.type_uname,
            ox = row.x,
            oy = row.y,
            oz = row.z,
            interior = row.interior or 0,
            dimension = row.dimension or 0,
            arrow = arrow == true,
        }
        util.log("building", "info", "[TWEAK] %s tweaks item %d (%s)", getPlayerName(player), row.id, row.type_uname)
        local labels = { move = text(player, "ITEMTWKBTNM"), edit = text(player, "ITEMTWKBTNE") }
        triggerClientEvent(
            player,
            "itemTweakStarted",
            player,
            row.id,
            row.x,
            row.y,
            row.z,
            headingOf(row),
            arrow == true,
            labels
        )
        exports.ui:showTip(player, text(player, arrow and "TIPTWEAKDEF" or "TIPTWEAKITM"), false, 10000)
        return true
    end

    -- Ends the player's tweak (upstream _twk_Commit); quiet skips the toast and tip for a player who is leaving.
    function M.commit(player, quiet)
        local tw = tweaks[player]
        if not tw then
            return false
        end
        tweaks[player] = nil
        if not isElement(player) then
            return true
        end
        util.log(
            "building",
            "info",
            "[TWEAK] %s finished tweaking item %d (%s)",
            getPlayerName(player),
            tw.id,
            tw.uname
        )
        triggerClientEvent(player, "itemTweakFinished", player, tw.id)
        if not quiet then
            exports.ui:hideTip(player)
            toast(player, "ITEMTWKFINI")
        end
        return true
    end

    -- Players inside the item's no-go sphere: the tweaker is told to step away, the others that they are in the way.
    local function blocked(player, tw, row)
        local any = false
        for _, p in ipairs(getElementsByType("player")) do
            if getElementInterior(p) == tw.interior and getElementDimension(p) == tw.dimension then
                local px, py, pz = getElementPosition(p)
                if tweak.blocks(px, py, pz, row.x, row.y, row.z) then
                    any = true
                    if p ~= player then
                        toast(p, "ITEMTWKBLOC")
                    end
                end
            end
        end
        if any then
            toast(player, "ITEMTWKMOVE")
        end
        return any
    end

    local function step(player, tw, row, action)
        if blocked(player, tw, row) then
            return
        end
        local heading = headingOf(row)
        local nx, ny, nh = tweak.apply(action, row.x, row.y, heading)
        if not tweak.inRange(nx, ny, tw.ox, tw.oy) then
            return toast(player, "ITEMTWKTFAR")
        end
        local nrz = ((row.rz or 0) + (nh - heading)) % 360
        db.exec(
            "UPDATE items SET x = ?, y = ?, rz = ? WHERE id = ? AND x IS NOT NULL "
                .. "AND container_id IS NULL AND holder_char_id IS NULL",
            { nx, ny, nrz, row.id },
            function(ok, c)
                if not ok then
                    return M.commit(c.player)
                end
                exports.items:resendWorldItem(c.id)
                if isElement(c.player) and tweaks[c.player] and tweaks[c.player].id == c.id then
                    triggerClientEvent(c.player, "itemTweakUpdated", c.player, c.id, c.x, c.y, c.z, c.heading)
                end
            end,
            { player = player, id = row.id, x = nx, y = ny, z = row.z, heading = nh }
        )
    end

    net.handler("itemTweakRequested", function(player, action)
        local tw = tweaks[player]
        if not tw then
            return
        end
        if action == "done" then
            return M.commit(player)
        end
        if not tweak.ACTIONS[action] then
            return
        end
        db.one(ctx.DEFENCE_ROW, { tw.id }, function(row, c)
            if not isElement(c.player) or tweaks[c.player] ~= c.tw then
                return
            end
            if not row then
                return M.commit(c.player) -- picked up, taken down or destroyed meanwhile
            end
            local px, py, pz = getElementPosition(c.player)
            if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > tweak.REACH then
                return M.commit(c.player)
            end
            step(c.player, c.tw, row, c.action)
        end, { player = player, tw = tw, action = action })
    end, { rate = 20 })

    addEventHandler("onPlayerQuit", root, function()
        M.commit(source, true)
    end)

    addEventHandler("characterDied", root, function()
        M.commit(source)
    end)

    addEventHandler("onPlayerVehicleEnter", root, function()
        M.commit(source)
    end)

    return M
end
