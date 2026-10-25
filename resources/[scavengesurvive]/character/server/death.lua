-- Death and /dropall: the character_death_drop / character_drop_all procedures, the kill animation and the death
-- screen. ctx = { db, net, util, drop, state } built by server/main.lua; state.byPlayer / state.byId are shared
-- with it. Both drops put items on the ground the player's client measured under each spot (drop.lua).
return function(ctx)
    local db, net, util, drop, state = ctx.db, ctx.net, ctx.util, ctx.drop, ctx.state
    local M = {}
    local GROUND_WAIT_MS = 1000

    -- Ground under the drop spots: the client answers groundHeightsReported, or after GROUND_WAIT_MS (or at once
    -- when measure is false) every spot takes the fallback height. One question per player at a time.
    local pending = {} -- player -> { id, spots, z, cb, timer }
    local nextId = 0

    local function answer(player, heights)
        local q = pending[player]
        if not q then
            return
        end
        pending[player] = nil
        if isTimer(q.timer) then
            killTimer(q.timer)
        end
        q.cb(drop.settle(q.spots, heights, q.z))
    end

    local function groundSpots(player, x, y, z, measure, cb)
        answer(player, nil)
        local spots = drop.spots(x, y)
        if not measure or not isElement(player) then
            return cb(drop.settle(spots, nil, z))
        end
        nextId = nextId + 1
        local q = { id = nextId, spots = spots, z = z, cb = cb }
        q.timer = setTimer(answer, GROUND_WAIT_MS, 1, player, nil)
        pending[player] = q
        triggerClientEvent(player, "groundHeightsRequested", player, q.id, spots, z)
    end

    net.handler("groundHeightsReported", function(player, id, heights)
        local q = pending[player]
        if q and q.id == id and type(heights) == "table" then
            answer(player, heights)
        end
    end)

    addEventHandler("onPlayerQuit", root, function()
        answer(source, nil)
    end)

    -- silent: the player is leaving (combat log); no kill animation and no death screen, only the drop
    function M.die(player, cause, killer, silent)
        local st = state.byPlayer[player]
        if not st or st.dead then
            return false
        end
        st.dead, st.hp = true, 0
        if state.clearStatuses then
            state.clearStatuses(player, not silent)
        end
        local x, y, z = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        -- a dev tool holding the ped somewhere else (the studio) records where the character really is: drop there,
        -- on the fallback heights (the client's collision is around the ped, not there)
        local measure = not silent
        local real = getElementData(player, "character.realPosition")
        if type(real) == "table" then
            x, y, z, int, dim = real[1], real[2], real[3], real[4], real[5]
            measure = false
        end
        local c = { player = player, st = st, charId = st.id, cause = cause, killer = killer }
        groundSpots(player, x, y, z, measure, function(spots)
            local ring, clothes = drop.split(spots)
            local params = { c.charId, x, y, z, int, dim, toJSON(ring, true), clothes[3] }
            db.call("character_death_drop", params, function(res)
                if not isElement(c.player) then
                    return
                end
                if not res or not res.ok then
                    util.log("character", "error", "death_drop failed for %d", c.charId)
                end
                triggerEvent("characterDied", c.player, c.charId, c.cause, c.killer)
                if state.byId[c.charId] == c.player then
                    state.byId[c.charId] = nil
                end
                -- a respawn may already have installed the next character; only drop the dead one
                if state.byPlayer[c.player] == c.st then
                    state.byPlayer[c.player] = nil
                end
            end)
        end)
        if silent then
            return true
        end
        if not isPedDead(player) then
            killPed(player, isElement(killer) and killer or nil)
        end
        setTimer(function(p)
            if isElement(p) then
                triggerClientEvent(p, "deathScreenShown", p, true, cause)
            end
        end, 1500, 1, player)
        return true
    end

    addEventHandler("onPlayerWasted", root, function(_, killer, weapon)
        local st = state.byPlayer[source]
        if not st or st.dead then
            return
        end
        local cause = weapon == 53 and "drowned" or weapon == 54 and "fall" or weapon == 37 and "burned" or "killed"
        M.die(source, cause, isElement(killer) and getElementType(killer) == "player" and killer or false)
    end)

    -- /dropall (upstream commands.pwn): hands up and everything carried, worn and in the inventory on the ground,
    -- the death drop without dying; characterItemsDropped lets items clear the hands and gear.
    addCommandHandler("dropall", function(player)
        local st = getElementType(player) == "player" and state.byPlayer[player]
        if not st or st.dead then
            return
        end
        local x, y, z = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        groundSpots(player, x, y, z, true, function(spots)
            local params = { st.id, toJSON((drop.split(spots)), true), int, dim }
            db.call("character_drop_all", params, function(res)
                if not isElement(player) or not res or not res.ok then
                    return
                end
                triggerEvent("characterItemsDropped", player, st.id)
                setPedAnimation(player, "ROB_BANK", "SHP_HandsUp_Scr", -1, false, false, true, true)
            end)
        end)
    end)

    return M
end
