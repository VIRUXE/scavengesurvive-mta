-- Supply drops and weapons caches (server half). Upstream: core/world/supply-crate.pwn and weapons-cache.pwn.
-- A supply drop is a crate object that descends from z 1000 at 3.5 u/s; on landing it becomes a world safebox
-- item (drops.SUPPLY_CRATE) filled from the type's airdrop table, overflow lying in rings around it. A weapons
-- cache appears at once (drops.CACHE_CRATE) and three bearing/distance signals point at it 200 s apart.
-- ctx = { db, util, roll, drops, settings(), lootTable(name) } from server/main.lua.
return function(ctx)
    local db, util, roll, drops = ctx.db, ctx.util, ctx.roll, ctx.drops
    local M = {}
    local rng = math.random
    local function rand()
        return rng()
    end
    local typeState = drops.newTypeState(drops.TYPES, getTickCount(), rng)
    local lastSupplyDrop = nil -- tick of the last landing
    local inFlight = nil -- { typeIdx, x, y, z, obj, blip, timer }
    local activeCache = nil -- { x, y, z, timer }
    local cachePoints = {} -- every weapon_cache_points row, for the signal reference
    local warnedEmpty = {}

    local function num(key, default)
        return tonumber(ctx.settings()[key]) or default
    end

    local function say(text)
        outputChatBox(text, root, 255, 255, 0, true)
    end

    local function createWorldItem(uname, x, y, z, dataJson, despawnAt, cb)
        local params = { uname, nil, dataJson, x, y, z, rng(0, 359), 0, 0, nil, despawnAt, n = 11 }
        db.call("item_create", params, function(res)
            if not res or not res.ok then
                util.log("loot", "warn", "drop: item_create %s failed: %s", uname, res and res.code or "db")
                return cb and cb(nil)
            end
            if cb then
                cb(res.payload)
            end
        end)
    end

    local function initialData(uname, tableName)
        local def = exports.data:itemType(uname)
        if not def then
            return nil
        end
        local cal = def.categoryData and def.categoryData.calibre
        local ammoTypes = cal and exports.data:ammoTypesForCalibre(cal) or nil
        return roll.initialItemData(def, tableName, ammoTypes, rng)
    end

    -- Creates the crate item, fills its container, and lays the overflow around it.
    local function fillCrate(crateUname, tableName, count, x, y, z, label)
        local tbl = ctx.lootTable(tableName)
        if not tbl then
            return util.log("loot", "warn", "drop: unknown loot table %s", tableName)
        end
        local def = exports.data:itemType(crateUname)
        local slots = def and def.categoryData and tonumber(def.categoryData.size) or 8
        local unames = roll.fill(tbl, count, function()
            return rng()
        end)
        local inside, around = drops.splitForCrate(unames, slots)
        createWorldItem(crateUname, x, y, z, nil, nil, function(payload)
            if not payload then
                return
            end
            local containerId = payload.container_id
            -- ground positions: the overflow first, then one spare per crate item in case the crate refuses it
            -- (container slots count item size units, so a 5-slot gun case holds fewer than five rifles)
            local positions = drops.ringPositions(x, y, #around + #inside, function()
                return rng()
            end)
            local nextGround = #around
            local despawnAt = nil
            local function ground(uname)
                nextGround = nextGround + 1
                local pos = positions[nextGround] or positions[#positions]
                createWorldItem(uname, pos.x, pos.y, z, initialData(uname, tableName), despawnAt)
            end
            local sql = "SELECT DATE_FORMAT(DATE_ADD(NOW(), INTERVAL ? MINUTE), '%Y-%m-%d %H:%i:%s') AS d"
            db.one(sql, { num("loot.despawn_minutes", 120) }, function(row)
                despawnAt = row and row.d or nil
                for i, uname in ipairs(around) do
                    local pos = positions[i]
                    createWorldItem(uname, pos.x, pos.y, z, initialData(uname, tableName), despawnAt)
                end
                for _, uname in ipairs(inside) do
                    if not containerId or containerId == false then
                        ground(uname)
                    else
                        db.call("item_create_in_container", { uname, containerId }, function(res, u)
                            if not res or not res.ok then
                                return ground(u) -- CONTAINER_FULL: size units, not slots
                            end
                            local data = initialData(u, tableName)
                            if data and res.payload and res.payload.item_id then
                                db.exec("UPDATE items SET data = ? WHERE id = ?", { data, res.payload.item_id })
                            end
                        end, uname)
                    end
                end
            end)
            local where = string.format("%.1f, %.1f, %.1f", x, y, z)
            local counts = string.format("%d items (%d offered to the crate, %d around)", #unames, #inside, #around)
            util.log("loot", "info", "%s at %s: %s", label, where, counts)
        end)
    end

    -- Supply drops -------------------------------------------------------------------------------------------

    local function land()
        local d = inFlight
        if not d then
            return
        end
        inFlight = nil
        if isElement(d.obj) then
            destroyElement(d.obj)
        end
        if isElement(d.blip) then
            destroyElement(d.blip)
        end
        for _, p in ipairs(getElementsByType("player")) do
            local px, py, pz = getElementPosition(p)
            if math.abs(pz - d.z) < 5 then
                local nx, ny = drops.pushOut(px, py, d.x, d.y, drops.LAND_PUSH_RADIUS)
                if nx then
                    setElementPosition(p, nx, ny, d.z + 1.0)
                end
            end
        end
        local t = drops.TYPES[d.typeIdx]
        local count = drops.supplyCount(rand)
        fillCrate(drops.SUPPLY_CRATE, t.table, count, d.x, d.y, d.z, "supply crate (" .. t.name .. ")")
        triggerClientEvent(root, "supplyCrateLanded", resourceRoot, d.x, d.y, d.z)
        triggerEvent("supplyCrateLanded", resourceRoot, d.typeIdx, d.x, d.y, d.z)
        lastSupplyDrop = getTickCount()
    end

    function M.dropSupply(typeIdx, x, y, z, locationName)
        typeIdx = tonumber(typeIdx) or 1
        local t = drops.TYPES[typeIdx]
        if not t then
            return false, "BAD_TYPE"
        end
        if inFlight then
            return false, "IN_FLIGHT"
        end
        local ms = drops.descentMs(drops.DROP_HEIGHT, z, drops.DROP_SPEED)
        local obj = createObject(3799, x, y, drops.DROP_HEIGHT, 0, 0, 0)
        if not obj then
            return false, "NO_OBJECT"
        end
        moveObject(obj, ms, x, y, z, 0, 0, 720)
        local blip = createBlipAttachedTo(obj, 0, 2, 255, 200, 0, 255, 0, 99999)
        inFlight = { typeIdx = typeIdx, x = x, y = y, z = z, obj = obj, blip = blip }
        inFlight.timer = setTimer(land, ms, 1)
        triggerClientEvent(root, "supplyDropStarted", resourceRoot, obj, x, y, z)
        say(drops.supplyText(drops.announceName(t.name, rand), locationName or "an unknown location"))
        local target = string.format("%s (%s) falling to %.1f, %.1f, %.1f", t.name, locationName or "?", x, y, z)
        util.log("loot", "info", "supply drop %s in %d s", target, ms / 1000)
        return true
    end

    local function supplyTick()
        if inFlight then
            return
        end
        local now = getTickCount()
        if lastSupplyDrop and now - lastSupplyDrop < num("loot.supply_cooldown_s", 600) * 1000 then
            return
        end
        local idx = drops.pickType(drops.TYPES, typeState, getPlayerCount(), now)
        if not idx then
            return
        end
        local sql = "SELECT id, name, x, y, z FROM supply_drop_points"
            .. " WHERE used_at IS NULL OR used_at < NOW() - INTERVAL ? HOUR ORDER BY RAND() LIMIT 1"
        db.one(sql, { num("loot.drop_point_reuse_hours", 24) }, function(row)
            if not row then
                if not warnedEmpty.supply then
                    warnedEmpty.supply = true
                    util.log("loot", "warn", "supply drops: every drop point was used recently")
                end
                return
            end
            if inFlight then
                return
            end
            db.exec("UPDATE supply_drop_points SET used_at = NOW() WHERE id = ?", { row.id })
            drops.markDropped(drops.TYPES, typeState, idx, getTickCount(), rand)
            M.dropSupply(idx, row.x, row.y, row.z, row.name)
        end)
    end

    -- Weapons caches -----------------------------------------------------------------------------------------

    local function signal(x, y, z, count)
        local ref = drops.signalReference(cachePoints, x, y, function()
            return rng()
        end)
        if ref then
            say(drops.signalText(ref, x, y))
        else
            util.log("loot", "warn", "weapons cache: no reference point within %d m", drops.CACHE_REFERENCE_RADIUS)
        end
        if count < drops.CACHE_SIGNALS and activeCache then
            activeCache.timer = setTimer(signal, drops.CACHE_SIGNAL_INTERVAL_S * 1000, 1, x, y, z, count + 1)
        else
            activeCache = nil
        end
    end

    function M.dropWeaponCache(x, y, z)
        if activeCache then
            return false, "ACTIVE"
        end
        activeCache = { x = x, y = y, z = z }
        fillCrate(drops.CACHE_CRATE, drops.CACHE_TABLE, drops.cacheCount(rand), x, y, z, "weapons cache")
        triggerEvent("weaponCacheDropped", resourceRoot, x, y, z)
        signal(x, y, z, 1)
        return true
    end

    local function playersNear(x, y, z, radius)
        for _, p in ipairs(getElementsByType("player")) do
            local px, py, pz = getElementPosition(p)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) < radius then
                return true
            end
        end
        return false
    end

    local function scheduleCache()
        local ms = (num("loot.cache_interval_s", 1500) + rng() * num("loot.cache_jitter_s", 600)) * 1000
        setTimer(function()
            if not activeCache and getPlayerCount() >= num("loot.cache_min_players", 4) then
                local sql = "SELECT id, x, y, z FROM weapon_cache_points"
                    .. " WHERE used_at IS NULL OR used_at < NOW() - INTERVAL ? HOUR ORDER BY RAND() LIMIT 25"
                db.query(sql, { num("loot.drop_point_reuse_hours", 24) }, function(rows)
                    for _, r in ipairs(rows or {}) do
                        if not playersNear(r.x, r.y, r.z, drops.CACHE_CLEAR_RADIUS) then
                            db.exec("UPDATE weapon_cache_points SET used_at = NOW() WHERE id = ?", { r.id })
                            M.dropWeaponCache(r.x, r.y, r.z)
                            return
                        end
                    end
                    if not rows or #rows == 0 then
                        if not warnedEmpty.cache then
                            warnedEmpty.cache = true
                            util.log("loot", "warn", "weapons caches: every cache point was used recently")
                        end
                    end
                end)
            end
            scheduleCache()
        end, math.floor(ms), 1)
    end

    function M.types()
        local out = {}
        for i, t in ipairs(drops.TYPES) do
            out[i] = { name = t.name, table = t.table, required = t.required }
        end
        return out
    end

    function M.status()
        return {
            inFlight = inFlight and drops.TYPES[inFlight.typeIdx].name or false,
            activeCache = activeCache and { x = activeCache.x, y = activeCache.y } or false,
            lastSupplyDropAgoS = lastSupplyDrop and math.floor((getTickCount() - lastSupplyDrop) / 1000) or false,
        }
    end

    function M.start()
        db.query("SELECT x, y, z FROM weapon_cache_points", {}, function(rows)
            cachePoints = rows or {}
        end)
        setTimer(supplyTick, num("loot.supply_tick_s", 60) * 1000, 0)
        scheduleCache()
    end

    function M.stop()
        if inFlight then
            if isElement(inFlight.obj) then
                destroyElement(inFlight.obj)
            end
            if isElement(inFlight.blip) then
                destroyElement(inFlight.blip)
            end
            inFlight = nil
        end
        activeCache = nil
    end

    return M
end
