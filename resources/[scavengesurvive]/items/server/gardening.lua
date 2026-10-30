-- Server side of gardening (#142, shared/logic/gardening.lua): Seeds, a bottle or a Knife used on a Plant Pot lying
-- there (hands.lua's held-with-world chain, through server/smallitems.lua), a growth step for every active pot on a
-- timer (one UPDATE each, re-sent to the clients that draw the plant), and the pot's status on a tap of F.
-- ctx = { db, net, type, toast, world, gardening, liquids, decodeData, updateHeldData } built by
-- server/main.lua.
return function(ctx)
    local db, net, toast = ctx.db, ctx.net, ctx.toast
    local gardening, liquids, itemType, decodeData = ctx.gardening, ctx.liquids, ctx.type, ctx.decodeData
    local POT_ROW = "SELECT id, data, x, y, z, rz, interior, dimension FROM items WHERE id = ? "
        .. "AND type_uname = 'PlantPot' AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local ACTIVE_POTS = "SELECT id, data FROM items WHERE type_uname = 'PlantPot' AND x IS NOT NULL "
        .. "AND JSON_VALUE(data, '$.pot.active') = 1"
    local REACH = 3.0
    local M = {}

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    local function writePot(row, pot, cb)
        local d = decodeData(row.data)
        d.pot = gardening.encodePot(pot)
        db.exec("UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL", { encode(d), row.id }, function(ok, c)
            if ok then
                ctx.world.resendEverywhere(c.id)
            end
            if cb then
                cb(ok)
            end
        end, { id = row.id })
    end

    local function plant(player, held, row)
        local pot = gardening.pot(decodeData(row.data))
        local seeds = gardening.seedsFor(held.id, held.data)
        local ok, nextPot, nextSeeds = gardening.plant(pot, seeds)
        if not ok then
            return true -- an empty bag does nothing, as upstream
        end
        ctx.updateHeldData(player, { seeds = nextSeeds })
        writePot(row, nextPot)
        toast(player, "POTADDSEEDS")
        return true
    end

    local function water(player, held, row)
        local pot = gardening.pot(decodeData(row.data))
        local ok, nextPot, nextData = gardening.water(pot, liquids, itemType(held.uname), held.data)
        if not ok then
            toast(player, nextPot)
            return true
        end
        ctx.updateHeldData(player, nextData)
        writePot(row, nextPot)
        toast(player, "POTADDWATER")
        return true
    end

    local function harvest(player, _, row)
        local pot = gardening.pot(decodeData(row.data))
        local ok, crop, nextPot = gardening.harvest(pot)
        if not ok then
            toast(player, crop)
            return true
        end
        writePot(row, nextPot)
        if crop then
            local params = { crop, 5, nil, row.x, row.y, row.z + 0.5, row.rz, row.interior, row.dimension }
            params[10], params[11], params.n = nil, nil, 11
            db.call("item_create", params, function(res, c)
                if res and res.ok then
                    triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
                end
                if isElement(c.player) then
                    ctx.world.syncPlayer(c.player)
                end
            end, { player = player })
        end
        toast(player, "POTHARVESTE")
        return true
    end

    -- hands.lua's held-with-world chain: true when a pot took the held item
    function M.interact(player, held, row)
        if row.uname ~= gardening.POT or not held then
            return false
        end
        local t = itemType(held.uname)
        if held.uname == gardening.BAG then
            return plant(player, held, row)
        elseif liquids.isContainer(t) then
            return water(player, held, row)
        elseif held.uname == "Knife" then
            return harvest(player, held, row)
        end
        return false
    end

    -- the world unames a held uname reaches for because of the pots
    function M.targets(uname)
        if uname == gardening.BAG or uname == "Knife" or liquids.isContainer(itemType(uname)) then
            return { gardening.POT }
        end
        return nil
    end

    net.handler("potInspectRequested", function(player, itemId)
        itemId = tonumber(itemId)
        if not itemId then
            return
        end
        db.one(POT_ROW, { itemId }, function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local px, py, pz = getElementPosition(c.player)
            if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > REACH then
                return
            end
            setPedAnimation(c.player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
            triggerClientEvent(
                c.player,
                "potInspected",
                c.player,
                gardening.status(gardening.pot(decodeData(row.data)))
            )
        end, { player = player })
    end, { rate = 5 })

    -- one growth step for every active pot in the world
    local function growAll()
        db.query(ACTIVE_POTS, {}, function(rows)
            for _, row in ipairs(rows or {}) do
                local pot = gardening.pot(decodeData(row.data))
                writePot(row, gardening.grow(pot))
            end
        end)
    end

    setTimer(growAll, gardening.GROW_MS, 0)

    return M
end
