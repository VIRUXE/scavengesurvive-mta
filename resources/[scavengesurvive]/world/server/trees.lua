-- Felling trees (#157; upstream core/world/tree.pwn): the interact key with a Chainsaw in hand, standing within reach
-- of one of GTA's own trees of the species in data/trees.lua (shared/logic/trees.lua), cuts it for as long as the key
-- stays down; the hold bar and the key release are the treatment hold of items (treatmentStarted and
-- treatmentCancelRequested).
-- Taking the last of its health fells it: every client takes the tree out of its world and draws it falling, the logs
-- land a moment later (one item_create_many call), and the tree stands again world.tree_respawn_s later. Felled trees
-- stay in the felled_trees table (kept over restarts, stood again at regrow_at, world.tree_respawn_s after the fell);
-- half-cut health lives in memory only.
-- ctx = { db, net, util, log, logAt, logic = shared/logic/trees.lua, data = data/trees.lua, setting } built by
-- server/main.lua.
return function(ctx)
    local db, net, util, logic, data = ctx.db, ctx.net, ctx.util, ctx.logic, ctx.data
    local log, logAt = ctx.log, ctx.logAt
    local index = logic.index(data)
    local felled, health = {}, {} -- tree -> true; tree -> health left
    local active = {} -- player -> { itemId, tree, x, y, z, perPointMs, timer }
    local byKey = {} -- tree_key -> index into index.trees
    local MAX_TIMER_S = 20 * 86400 -- setTimer takes 32-bit milliseconds

    local function keyOf(t)
        return string.format("%d:%.1f:%.1f", t[1], t[2], t[3])
    end

    for i, t in ipairs(index.trees) do
        byKey[keyOf(t)] = i
    end

    local function regrow(i)
        local t = index.trees[i]
        if not felled[i] then
            return
        end
        felled[i] = nil
        db.exec("DELETE FROM felled_trees WHERE tree_key = ?", { keyOf(t) })
        triggerClientEvent(root, "treeRestored", root, i, t[1], t[2], t[3], t[4])
    end

    local regrowAt = {} -- tree -> unix time it stands again

    local function regrowIn(i, seconds)
        regrowAt[i] = getRealTime().timestamp + seconds
        local function arm()
            local left = regrowAt[i] - getRealTime().timestamp
            if left > MAX_TIMER_S then
                return setTimer(arm, MAX_TIMER_S * 1000, 1)
            end
            setTimer(regrow, math.max(1, left) * 1000, 1, i)
        end
        arm()
    end

    local function chainsawRuns()
        return true
    end

    local function stop(player, quiet)
        local a = active[player]
        if not a then
            return
        end
        active[player] = nil
        if isTimer(a.timer) then
            killTimer(a.timer)
        end
        if isElement(player) and not quiet then
            setPedAnimation(player)
            triggerClientEvent(player, "treatmentStopped", player)
        end
    end

    local function dropLogs(i, groundZ)
        local t = index.trees[i]
        local list = {}
        for _, d in ipairs(logic.drops(index.species[t[1]][4], t[2], t[3], math.random)) do
            list[#list + 1] = { u = logic.YIELD, x = d.x, y = d.y, z = groundZ, rz = d.rz, i = 0 }
        end
        db.call("item_create_many", { toJSON(list) }, function(res)
            if not (res and res.ok) then
                util.log("world", "warn", "trees: logs of tree %d: %s", i, res and res.code or "DB_ERROR")
            end
        end)
    end

    local function fell(player, a)
        local i = a.tree
        local t = index.trees[i]
        local species = index.species[t[1]]
        felled[i], health[i] = true, nil
        stop(player)
        exports.character:gainSkill(player, logic.SKILL)
        local fall = logic.fall(species[5], math.random)
        triggerClientEvent(root, "treeFelled", root, i, t[1], t[2], t[3], t[4], t[5], fall)
        local groundZ = a.z - 0.9
        setTimer(dropLogs, logic.FALL_MS, 1, i, groundZ)
        local respawn = ctx.setting("world.tree_respawn_s", logic.RESPAWN_S)
        local sql = "INSERT INTO felled_trees (tree_key, regrow_at) VALUES (?, NOW() + INTERVAL ? SECOND) "
            .. "ON DUPLICATE KEY UPDATE felled_at = NOW(), regrow_at = VALUES(regrow_at)"
        db.exec(sql, { keyOf(t), respawn })
        regrowIn(i, respawn)
        local line = { player = player, tree_id = i, model = t[1], logs = species[4] }
        log.event("world.treeFelled", logAt(line, player))
    end

    local function tick(player)
        local a = active[player]
        if not a or not isElement(player) then
            return
        end
        local x, y, z = getElementPosition(player)
        local held = exports.items:getHeld(player)
        local moved = getDistanceBetweenPoints3D(x, y, z, a.x, a.y, a.z) > logic.MAX_MOVE
        if isPedDead(player) or moved or getPedOccupiedVehicle(player) or felled[a.tree] then
            return stop(player)
        end
        if not held or held.id ~= a.itemId or not chainsawRuns() then
            return stop(player)
        end
        local species = index.species[index.trees[a.tree][1]]
        local left = (health[a.tree] or species[2]) - logic.damage(species, logic.CHECK_MS, a.perPointMs)
        health[a.tree] = left
        if left <= 0 then
            fell(player, a)
        end
    end

    local function start(player, held)
        local x, y, z = getElementPosition(player)
        local i = logic.nearest(index, felled, x, y, z)
        if not i then
            return false
        end
        local t = index.trees[i]
        local species = index.species[t[1]]
        if not chainsawRuns() then
            return false
        end
        stop(player)
        local perPointMs = exports.character:skillTimeModifier(player, logic.BASE_MS, logic.SKILL)
        local a = { itemId = held.id, tree = i, x = x, y = y, z = z, perPointMs = perPointMs }
        a.timer = setTimer(tick, logic.CHECK_MS, 0, player)
        active[player] = a
        setElementRotation(player, 0, 0, logic.facing(x, y, t[2], t[3]))
        setPedAnimation(player, "CHAINSAW", "CSAW_G", -1, true, false, false, false)
        local ms = logic.remainingMs(species, health[i] or species[2], perPointMs)
        triggerClientEvent(player, "treatmentStarted", player, ms, true)
        return true
    end

    -- the trees felled before this start, with the seconds each has left to regrow
    local function loadFelled()
        local sql = "SELECT tree_key, GREATEST(TIMESTAMPDIFF(SECOND, NOW(), regrow_at), 0) AS left_s FROM felled_trees"
        db.query(sql, {}, function(rows)
            if not rows then
                return util.log("world", "warn", "trees: could not read the felled trees")
            end
            local list = {}
            for _, row in ipairs(rows) do
                local i = byKey[row.tree_key]
                local left = tonumber(row.left_s) or 0
                if i and left > 0 then
                    felled[i] = true
                    regrowIn(i, left)
                    local t = index.trees[i]
                    list[#list + 1] = { i, t[1], t[2], t[3], t[4] }
                else
                    db.exec("DELETE FROM felled_trees WHERE tree_key = ?", { row.tree_key })
                end
            end
            for _, player in ipairs(getElementsByType("player")) do
                triggerClientEvent(player, "treesSynced", player, list)
            end
            util.log("world", "info", "trees: %d felled, regrowing", #list)
        end)
    end
    loadFelled()

    addEventHandler("itemUseAttempted", root, function(_, uname)
        if uname ~= logic.TOOL or active[source] then
            return
        end
        local held = exports.items:getHeld(source)
        if not held or isPedDead(source) or getPedOccupiedVehicle(source) then
            return
        end
        if getElementInterior(source) ~= 0 or getElementDimension(source) ~= 0 then
            return
        end
        if start(source, held) then
            cancelEvent()
        end
    end)

    net.handler("treatmentCancelRequested", function(player)
        stop(player)
    end)

    net.handler("treesStateRequested", function(player)
        local list = {}
        for i in pairs(felled) do
            local t = index.trees[i]
            list[#list + 1] = { i, t[1], t[2], t[3], t[4] }
        end
        triggerClientEvent(player, "treesSynced", player, list)
    end, { rate = 2 })

    addEventHandler("onPlayerQuit", root, function()
        stop(source, true)
    end)
end
