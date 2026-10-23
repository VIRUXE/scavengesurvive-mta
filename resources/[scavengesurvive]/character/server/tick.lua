-- Survival tick, stat sync to the owning client and the periodic DB flush of every spawned character.
-- ctx = { db, util, survival, state, die } built by server/main.lua; die comes from server/death.lua.
return function(ctx)
    local db, util, survival, state = ctx.db, ctx.util, ctx.survival, ctx.state
    local FLUSH_MS = 10000
    local M = {}

    function M.sendStats(player, force)
        local st = state.byPlayer[player]
        if not st then
            return
        end
        local changed = force
            or math.abs(st.hp - st.lastSent.hp) >= 0.5
            or math.abs(st.food - st.lastSent.food) >= 0.5
            or math.abs(st.bleed - st.lastSent.bleed) >= 0.01
        if not changed then
            return
        end
        local payload = { hp = st.hp, food = st.food, bleed = st.bleed, wounds = st.wounds }
        st.lastSent = payload
        triggerClientEvent(player, "onClientCharacterStats", player, payload)
        triggerEvent("onCharacterStatsChanged", player, payload)
    end

    setTimer(function()
        for player, st in pairs(state.byPlayer) do
            if isElement(player) and st.hp > 0 and not st.dead then
                local vx, vy, vz = getElementVelocity(player)
                local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                local mult = survival.movementMultiplier(speed, getPedOccupiedVehicle(player) ~= false)
                local s, events = survival.tick(st, mult, math.random)
                st.hp, st.food, st.bleed, st.dirty = s.hp, s.food, s.bleed, true
                setElementHealth(player, math.max(1, st.hp))
                M.sendStats(player, false)
                for _, e in ipairs(events) do
                    if e == "died" then
                        ctx.die(player, st.food <= 0 and "starvation" or "bleeding", false)
                    end
                end
            end
        end
    end, 1000, 0)

    function M.flushOne(player, st)
        if not st.dirty or st.dead then
            return
        end
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        db.exec(
            "UPDATE characters SET hp = ?, food = ?, bleed = ?, x = ?, y = ?, z = ?, rz = ?,"
                .. " interior = ?, dimension = ? WHERE id = ? AND alive = 1",
            { st.hp, st.food, st.bleed, x, y, z, rz, getElementInterior(player), getElementDimension(player), st.id }
        )
        st.dirty = false
    end

    function M.flushAll(force)
        local rows = {}
        for player, st in pairs(state.byPlayer) do
            if isElement(player) and (st.dirty or force) and st.hp > 0 and not st.dead then
                local x, y, z = getElementPosition(player)
                local _, _, rz = getElementRotation(player)
                rows[#rows + 1] =
                    { id = st.id, hp = st.hp, food = st.food, bleed = st.bleed, x = x, y = y, z = z, rz = rz }
                st.dirty = false
            end
        end
        if #rows == 0 then
            return
        end
        -- MTA's toJSON wraps its argument in an outer array: {r1, r2} -> "[[r1, r2]]"; the procedure reads '$[0][*]'.
        db.call("character_flush", { toJSON(rows) }, function(res)
            if not res or not res.ok then
                util.log("character", "error", "character_flush failed: %s", res and res.code or "db")
            end
        end)
    end

    setTimer(function()
        M.flushAll(false)
    end, FLUSH_MS, 0)

    return M
end
