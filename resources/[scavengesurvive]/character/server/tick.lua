-- Survival tick, stat sync to the owning client and the periodic DB flush of every spawned character.
-- ctx = { db, util, survival, bleeding, blood, skills, medical, state, die, treatment, travel } built by
-- server/main.lua; die comes from server/death.lua, treatment (server/medical.lua) and travel (server/travel.lua)
-- are set after this loads.
return function(ctx)
    local db, util, survival, skills, state = ctx.db, ctx.util, ctx.survival, ctx.skills, ctx.state
    local medical, bleeding = ctx.medical, ctx.bleeding
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
            if
                isElement(player)
                and st.hp > 0
                and not st.dead
                and not getElementData(player, "auth.reauthProtection")
                and ctx.onDuty(player)
            then
                -- staff on duty: stats frozen where they were (no hunger, bleeding or drug timers), no blood spray
                if st.bleedShown then
                    st.bleedShown = false
                    setElementData(player, "character.bleeding", false, "broadcast", "deny")
                end
                setElementHealth(player, math.max(1, st.hp))
            elseif
                isElement(player)
                and st.hp > 0
                and not st.dead
                and not getElementData(player, "auth.reauthProtection")
            then
                local vx, vy, vz = getElementVelocity(player)
                local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
                local inVehicle = getPedOccupiedVehicle(player) ~= false
                local mult = survival.movementMultiplier(speed, inVehicle)
                local bleedBefore = st.bleed
                local s, events = survival.tick(st, mult, math.random)
                st.hp, st.food, st.bleed, st.dirty = s.hp, s.food, s.bleed, true
                -- the spray every client draws (client/blood.lua) and the pool trail (server/blood.lua)
                local blocked = inVehicle
                local shown = bleeding.visible(st.bleedShown, st.bleed, blocked, math.random)
                if shown ~= (st.bleedShown or false) then
                    st.bleedShown = shown
                    setElementData(player, "character.bleeding", shown, "broadcast", "deny")
                end
                if shown then
                    ctx.blood.drop(player)
                end
                ctx.treatment.tick(player, st, 1000)
                if ctx.travel then
                    ctx.travel.tick(player, 1000) -- travel stats and Endurance (#138)
                end
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

    -- Trail for the staff dashboard: a point every TRAIL_MS when the character moved TRAIL_MIN metres (or changed
    -- interior/dimension, vehicle or seat), buffered per player and sent with the next flush as
    -- { msAgo, x, y, z, int, dim, vehicleModel, seat }. Seat -1 means on foot.
    local TRAIL_MS, TRAIL_MIN, TRAIL_KEEP = 2000, 1.5, 60
    -- player -> last place/vehicle/seat and buffered { tick, x, y, z, int, dim, veh, seat } points
    local trail = {}

    local function sampleTrail()
        local now = getTickCount()
        for player, st in pairs(state.byPlayer) do
            if isElement(player) and st.hp > 0 and not st.dead then
                local x, y, z, int, dim = placeOf(player)
                local vehicle = getPedOccupiedVehicle(player)
                local veh = vehicle and getElementModel(vehicle) or 0
                local seat = vehicle and getPedOccupiedVehicleSeat(player) or -1
                local t = trail[player]
                if not t then
                    t = { points = {} }
                    trail[player] = t
                end
                local l = t.last
                local moved = not l
                    or l[4] ~= int
                    or l[5] ~= dim
                    or l[6] ~= veh
                    or l[7] ~= seat
                    or (x - l[1]) ^ 2 + (y - l[2]) ^ 2 + (z - l[3]) ^ 2 >= TRAIL_MIN * TRAIL_MIN
                if moved then
                    t.last = { x, y, z, int, dim, veh, seat }
                    t.points[#t.points + 1] = { now, x, y, z, int, dim, veh, seat }
                    if #t.points > TRAIL_KEEP then
                        table.remove(t.points, 1)
                    end
                end
            end
        end
    end

    -- Points since the last flush, oldest first, as offsets from now; clears the buffer.
    local function takeTrail(player)
        local t = trail[player]
        if not t or #t.points == 0 then
            return nil
        end
        local now, out = getTickCount(), {}
        for i, p in ipairs(t.points) do
            out[i] = { now - p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8] }
        end
        t.points = {}
        return out
    end

    addEventHandler("onPlayerQuit", root, function()
        trail[source] = nil
    end)

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
                row.path = takeTrail(player)
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

    setTimer(sampleTrail, TRAIL_MS, 0)
    setTimer(function()
        M.flushAll(false)
    end, FLUSH_MS, 0)

    return M
end
