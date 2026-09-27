function Character.die(player, cause, killer)
    local st = Character.byPlayer[player]
    if not st or st.dead then
        return false
    end
    st.dead, st.hp = true, 0
    local x, y, z = getElementPosition(player)
    -- items rest on the ground like a dropped item (the ped position is ~1 m above it)
    local params = { st.id, x, y, z - 0.9, getElementInterior(player), getElementDimension(player) }
    Character.db.call("character_death_drop", params, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        if not res or not res.ok then
            -- the character stays alive in the DB; a reconnect loads it again instead of orphaning its items
            Character.util.log("character", "error", "death_drop failed for %d", ctx.charId)
        else
            Character.awaitingRespawn[ctx.player] = true
        end
        triggerEvent("onCharacterDied", ctx.player, ctx.charId, ctx.cause, ctx.killer)
        if Character.byId[ctx.charId] == ctx.player then
            Character.byId[ctx.charId] = nil
        end
        -- a respawn may already have installed the next character; only drop the dead one
        if Character.byPlayer[ctx.player] == ctx.st then
            Character.byPlayer[ctx.player] = nil
        end
    end, { player = player, st = st, charId = st.id, cause = cause, killer = killer })
    if not isPedDead(player) then
        killPed(player, isElement(killer) and killer or nil)
    end
    setTimer(function(p)
        if isElement(p) then
            triggerClientEvent(p, "onClientCharacterDeathScreen", p, true, cause)
        end
    end, 1500, 1, player)
    return true
end

addEventHandler("onPlayerWasted", root, function(_, killer, weapon)
    local st = Character.byPlayer[source]
    if not st or st.dead then
        return
    end
    local cause = weapon == 53 and "drowned" or weapon == 54 and "fall" or weapon == 37 and "burned" or "killed"
    Character.die(source, cause, isElement(killer) and getElementType(killer) == "player" and killer or false)
end)
