local FLUSH_MS = 10000

function Character.sendStats(player, force)
    local st = Character.byPlayer[player]
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
    st.lastSent = { hp = st.hp, food = st.food, bleed = st.bleed }
    triggerClientEvent(player, "onClientCharacterStats", player, { hp = st.hp, food = st.food, bleed = st.bleed })
    triggerEvent("onCharacterStatsChanged", player, { hp = st.hp, food = st.food, bleed = st.bleed })
end

setTimer(function()
    for player, st in pairs(Character.byPlayer) do
        if isElement(player) and st.hp > 0 and not st.dead then
            local vx, vy, vz = getElementVelocity(player)
            local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
            local mult = Character.survival.movementMultiplier(speed, getPedOccupiedVehicle(player) ~= false)
            local bleedBefore = st.bleed
            local s, events = Character.survival.tick(st, mult, math.random)
            st.hp, st.food, st.bleed, st.dirty = s.hp, s.food, s.bleed, true
            setElementHealth(player, math.max(1, st.hp))
            Character.sendStats(player, false)
            for _, e in ipairs(events) do
                if e == "died" then
                    Character.die(player, Character.survival.deathCause(bleedBefore, st.food), false)
                end
            end
        end
    end
end, 1000, 0)

function Character.flushOne(player, st)
    if not st.dirty or st.dead then
        return
    end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    Character.db.exec(
        "UPDATE characters SET hp = ?, food = ?, bleed = ?, x = ?, y = ?, z = ?, rz = ?, interior = ?, dimension = ?"
            .. " WHERE id = ? AND alive = 1",
        { st.hp, st.food, st.bleed, x, y, z, rz, getElementInterior(player), getElementDimension(player), st.id }
    )
    st.dirty = false
end

function Character.flushAll(force)
    local rows = {}
    for player, st in pairs(Character.byPlayer) do
        if isElement(player) and (st.dirty or force) and st.hp > 0 and not st.dead then
            local x, y, z = getElementPosition(player)
            local _, _, rz = getElementRotation(player)
            rows[#rows + 1] = {
                id = st.id,
                hp = st.hp,
                food = st.food,
                bleed = st.bleed,
                x = x,
                y = y,
                z = z,
                rz = rz,
                interior = getElementInterior(player),
                dimension = getElementDimension(player),
            }
            st.dirty = false
        end
    end
    if #rows == 0 then
        return
    end
    -- MTA's toJSON wraps its argument in an outer array: {r1, r2} -> "[[r1, r2]]"; the procedure reads '$[0][*]'.
    Character.db.call("character_flush", { toJSON(rows) }, function(res)
        if not res or not res.ok then
            Character.util.log("character", "error", "character_flush failed: %s", res and res.code or "db")
        end
    end)
end

setTimer(function()
    Character.flushAll(false)
end, FLUSH_MS, 0)
