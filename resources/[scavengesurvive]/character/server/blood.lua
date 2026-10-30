-- The blood pools a bleeding character leaves (upstream core/char/bleed.pwn, shared/logic/bleeding.lua). The server
-- picks where each lands, as upstream's dynamic objects did, so every client draws the same trail, including players
-- who arrive or join after it was left; client/blood.lua draws them on the ground. POOLS per trail, round-robin.
-- A trail outlives its player: upstream's pools stayed until the slot was reused, so logging out never wipes the
-- trail a hunter follows; here it goes ORPHAN_MS after they left.
-- ctx = { bleeding, net }
return function(ctx)
    local bleeding, net = ctx.bleeding, ctx.net
    local ORPHAN_MS = 10 * 60 * 1000
    local trails = {} -- trail id -> { slot, pools = { [slot] = { x, y, z, rz, interior, dimension } } }
    local byPlayer = {} -- player -> trail id
    local lastId = 0
    local M = {}

    function M.drop(player)
        local id = byPlayer[player]
        if not id then
            lastId = lastId + 1
            id = lastId
            byPlayer[player] = id
            trails[id] = { slot = 0, pools = {} }
        end
        local trail = trails[id]
        trail.slot = bleeding.nextSlot(trail.slot, bleeding.POOLS)
        local x, y, z = getElementPosition(player)
        local dx, dy, rz = bleeding.poolOffset(math.random)
        local pool = { x + dx, y + dy, z, rz, getElementInterior(player), getElementDimension(player) }
        trail.pools[trail.slot] = pool
        triggerClientEvent(root, "bloodPoolDropped", resourceRoot, id, trail.slot, pool)
    end

    -- a client that just loaded draws the trails left before it
    net.handler("bloodPoolsRequested", function(player)
        local all = {}
        for id, trail in pairs(trails) do
            all[#all + 1] = { id = id, pools = trail.pools }
        end
        triggerClientEvent(player, "bloodPoolsSynced", resourceRoot, all)
    end, { rate = 1 })

    addEventHandler("onPlayerQuit", root, function()
        local id = byPlayer[source]
        byPlayer[source] = nil
        if id then
            setTimer(function()
                trails[id] = nil
                triggerClientEvent(root, "bloodPoolsCleared", resourceRoot, id)
            end, ORPHAN_MS, 1)
        end
    end)

    return M
end
