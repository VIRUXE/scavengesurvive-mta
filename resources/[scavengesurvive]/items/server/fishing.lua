-- Server side of fishing (#141, shared/logic/fishing.lua): the hud holds the interact key with a Fishing Rod in
-- hand and sends how long it was held (fishCastRequested); the line lands that far ahead, the spot has to be water
-- (getWaterLevel, server-side), then the wait runs, shortened by the Fishing skill; at its end the roll either
-- tugs the line (the catch lands at the player's feet a moment later, Fishing experience) or says "Unlucky!".
-- The key, dropping the rod, dying or leaving cancel.
-- ctx = { db, net, state, toast, world, fishing } built by server/main.lua.
return function(ctx)
    local db, net, state, toast, fishing = ctx.db, ctx.net, ctx.state, ctx.toast, ctx.fishing
    local active = {} -- player -> { rodId, dist, timer, landing }
    local M = {}

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    function M.cancel(player, quiet)
        local a = active[player]
        if not a then
            return
        end
        active[player] = nil
        if isTimer(a.timer) then
            killTimer(a.timer)
        end
        if isElement(player) then
            setPedAnimation(player)
            if not quiet then
                triggerClientEvent(player, "fishingStopped", player)
            end
        end
    end

    local function land(player, a)
        if not isElement(player) or active[player] ~= a then
            return
        end
        local x, y, z = getElementPosition(player)
        local params = { fishing.CATCH, 3, encode({ cooked = 0 }), x, y, z - 0.9, 90 }
        params[8], params[9], params[10], params[11], params.n =
            getElementInterior(player), getElementDimension(player), nil, nil, 11
        db.call("item_create", params, function(res, c)
            if res and res.ok then
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
            end
            if isElement(c.player) then
                ctx.world.syncPlayer(c.player)
            end
        end, { player = player })
        M.cancel(player)
    end

    local function lineMoves(player, a)
        if not isElement(player) or active[player] ~= a then
            return
        end
        local held = state.held[player]
        if not held or held.id ~= a.rodId then
            return M.cancel(player)
        end
        local miss = exports.character:skillTimeModifier(player, fishing.MISS_PER_MILLE, "Fishing")
        if not fishing.caught(math.random(0, 999), miss) then
            toast(player, "FISHUNLUCKY")
            return M.cancel(player)
        end
        toast(player, "FISHLINETUG")
        setPedAnimation(player, "SWORD", "sword_block", -1, true, false, false, false)
        exports.character:gainSkill(player, "Fishing")
        a.landing = true
        a.timer = setTimer(land, math.max(50, fishing.catchDelayMs(a.dist)), 1, player, a)
    end

    net.handler("fishCastRequested", function(player, heldMs)
        local held = state.held[player]
        if not held or held.uname ~= fishing.ROD or isPedDead(player) or getPedOccupiedVehicle(player) then
            return
        end
        M.cancel(player, true)
        local dist = fishing.castDistance(heldMs)
        local px, py, pz = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        local lx, ly = fishing.castPoint(px, py, rz, dist)
        local level = getWaterLevel(lx, ly, pz)
        if not level or level > pz + 1.0 then
            return toast(player, "FISHNCLOSER")
        end
        local wait = exports.character:skillTimeModifier(player, fishing.waitMs(), "Fishing")
        local a = { rodId = held.id, dist = dist }
        a.timer = setTimer(lineMoves, wait, 1, player, a)
        active[player] = a
        triggerClientEvent(player, "fishingStarted", player)
        toast(player, "FISHFISHING")
    end, { rate = 3 })

    net.handler("fishCancelRequested", function(player)
        M.cancel(player)
    end, { rate = 5 })

    addEventHandler("itemMoved", root, function(_, from)
        if from == "held" and active[source] then
            M.cancel(source)
        end
    end)

    addEventHandler("characterDied", root, function()
        M.cancel(source, true)
    end)

    addEventHandler("onPlayerQuit", root, function()
        M.cancel(source, true)
    end)

    return M
end
