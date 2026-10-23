-- Death: the character_death_drop procedure, the kill animation and the death screen.
-- ctx = { db, util, state } built by server/main.lua; state.byPlayer / state.byId are shared with it.
return function(ctx)
    local db, util, state = ctx.db, ctx.util, ctx.state
    local M = {}

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
        local params = { st.id, x, y, z, getElementInterior(player), getElementDimension(player) }
        db.call("character_death_drop", params, function(res, c)
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
        end, { player = player, st = st, charId = st.id, cause = cause, killer = killer })
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

    return M
end
