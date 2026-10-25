-- Survival tick, stat sync to the owning client and the periodic DB flush of every spawned character.
-- ctx = { db, util, survival, skills, medical, state, die, treatment } built by server/main.lua; die comes from
-- server/death.lua, treatment (server/medical.lua) is set after this module loads.
return function(ctx)
    local db, util, survival, skills, state = ctx.db, ctx.util, ctx.survival, ctx.skills, ctx.state
    local medical = ctx.medical
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
        payload.infection, payload.drugs = st.infection, st.drugs
        st.lastSent = payload
        triggerClientEvent(player, "characterStatsSynced", player, payload)
        triggerEvent("characterStatsChanged", player, payload)
    end

    setTimer(function()
        for player, st in pairs(state.byPlayer) do
            if isElement(player) and st.hp > 0 and not st.dead then
                local vx, vy, vz = getElementVelocity(player)
                local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                local mult = survival.movementMultiplier(speed, getPedOccupiedVehicle(player) ~= false)
                local bleedBefore = st.bleed
                local s, events = survival.tick(st, mult, math.random)
                st.hp, st.food, st.bleed, st.dirty = s.hp, s.food, s.bleed, true
                ctx.treatment.tick(player, st, 1000)
                setElementHealth(player, math.max(1, st.hp))
                M.sendStats(player, false)
                for _, e in ipairs(events) do
                    if e == "died" then
                        ctx.die(player, survival.deathCause(bleedBefore, st.food), false)
                    end
                end
            end
        end
    end, 1000, 0)

    -- Where the character is: a dev tool holding the ped somewhere else (the studio) records the real spot, so a
    -- flush never stores the studio set or its private dimension.
    local function placeOf(player)
        local real = getElementData(player, "character.realPosition")
        if type(real) == "table" then
            return real[1], real[2], real[3], real[4], real[5]
        end
        local x, y, z = getElementPosition(player)
        return x, y, z, getElementInterior(player), getElementDimension(player)
    end

    function M.flushOne(player, st)
        if not st.dirty or st.dead then
            return
        end
        local x, y, z, int, dim = placeOf(player)
        local _, _, rz = getElementRotation(player)
        local sql = "UPDATE characters SET hp = ?, food = ?, bleed = ?, x = ?, y = ?, z = ?, rz = ?,"
            .. " interior = ?, dimension = ?, skills = ?, infection = ?, drugs = ? WHERE id = ? AND alive = 1"
        local inf, drugs = medical.encodeInfection(st.infection), medical.encodeDrugs(st.drugs)
        db.exec(sql, { st.hp, st.food, st.bleed, x, y, z, rz, int, dim, skills.encode(st.skills), inf, drugs, st.id })
        st.dirty, st.skillsDirty = false, false
    end

    function M.flushAll(force)
        local rows = {}
        for player, st in pairs(state.byPlayer) do
            if isElement(player) and (st.dirty or force) and st.hp > 0 and not st.dead then
                local x, y, z, int, dim = placeOf(player)
                local _, _, rz = getElementRotation(player)
                local row = { id = st.id, hp = st.hp, food = st.food, bleed = st.bleed, x = x, y = y, z = z, rz = rz }
                -- skills change a few times a minute at most: sent only when they did (the procedure keeps the column)
                row.skills = st.skillsDirty and skills.encode(st.skills) or nil
                row.infection, row.drugs = medical.encodeInfection(st.infection), medical.encodeDrugs(st.drugs)
                row.interior, row.dimension = int, dim
                rows[#rows + 1] = row
                st.dirty, st.skillsDirty = false, false
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
