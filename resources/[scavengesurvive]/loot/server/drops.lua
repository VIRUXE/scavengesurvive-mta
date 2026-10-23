-- Supply drops and weapons caches (server half). Upstream: core/world/supply-crate.pwn and weapons-cache.pwn.
-- A supply drop is a pair of crate objects that descend from z 1000 at 3.5 u/s; on landing they stay where they
-- are and a 32-slot "Supply Crate" container is filled from the type's airdrop table. A weapons cache appears at
-- once (object 964, a 32-slot "Weapon Cache" container) and three bearing/distance signals point at it 200 s
-- apart. One crate of each kind exists at a time (the next one replaces it, contents included, as upstream's
-- DestroyContainer does); crates persist in world_crates so a restart rebuilds them. Players open a crate with
-- the interact key next to it (supplyCrateOpenRequested -> items:openSupplyContainer).
-- ctx = { db, net, util, roll, drops, settings(), lootTable(name) } from server/main.lua.
return function(ctx)
    local db, net, util, roll, drops = ctx.db, ctx.net, ctx.util, ctx.roll, ctx.drops
    local M = {}
    local rng = math.random
    local function rand()
        return rng()
    end
    local typeState = drops.newTypeState(drops.TYPES, getTickCount(), rng)
    local lastSupplyDrop = nil -- tick of the last landing
    local inFlight = nil -- { typeIdx, x, y, z, objects, blip, timer }
    local activeCache = nil -- { x, y, z, timer }
    local cachePoints = {} -- every weapon_cache_points row, for the signal reference
    local crates = {} -- kind -> { id, kind, containerId, x, y, z, objects }
    local warnedEmpty = {}

    local function num(key, default)
        return tonumber(ctx.settings()[key]) or default
    end

    local function say(text)
        outputChatBox(text, root, 255, 255, 0, true)
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

    -- Crates -------------------------------------------------------------------------------------------------

    local function tagObjects(c)
        local first = c.objects[1]
        if isElement(first) then
            setElementData(first, "crate.id", c.id, "broadcast", "deny")
            setElementData(first, "crate.kind", c.kind, "broadcast", "deny")
        end
    end

    local function createObjects(kind, x, y, z)
        local out = {}
        for _, spec in ipairs(drops.crateObjects(kind, x, y, z)) do
            local o = createObject(spec.model, spec.x, spec.y, spec.z, spec.rx, spec.ry, spec.rz)
            if o then
                out[#out + 1] = o
            end
        end
        return out
    end

    local function destroyObjects(objects)
        for _, o in ipairs(objects or {}) do
            if isElement(o) then
                destroyElement(o)
            end
        end
    end

    local function removeCrate(kind)
        local c = crates[kind]
        if not c then
            return
        end
        crates[kind] = nil
        destroyObjects(c.objects)
        -- the container row cascades to its items and to the world_crates row
        db.exec("DELETE FROM containers WHERE id = ?", { c.containerId })
    end

    -- Fills a crate container like upstream FillContainerWithLoot: every rolled item that fits goes in, one that
    -- does not (container slots count item size units) is skipped, nothing is created outside the crate.
    local function fillContainer(containerId, tableName, count, label, where)
        local tbl = ctx.lootTable(tableName)
        if not tbl then
            return util.log("loot", "warn", "drop: unknown loot table %s", tableName)
        end
        local unames = roll.fill(tbl, count, function()
            return rng()
        end)
        local placed = 0
        local function finish()
            local counts = string.format("%d of %d rolled items in the crate", placed, #unames)
            util.log("loot", "info", "%s at %s: %s", label, where, counts)
        end
        local function place(i)
            local uname = unames[i]
            if not uname then
                return finish()
            end
            db.call("item_create_in_container", { uname, containerId }, function(res)
                if res and res.ok then
                    placed = placed + 1
                    local data = initialData(uname, tableName)
                    if data and res.payload and res.payload.item_id then
                        db.exec("UPDATE items SET data = ? WHERE id = ?", { data, res.payload.item_id })
                    end
                elseif not res or res.code ~= "CONTAINER_FULL" then
                    local why = res and res.code or "db"
                    util.log("loot", "warn", "drop: item_create_in_container %s failed: %s", uname, why)
                end
                place(i + 1)
            end)
        end
        place(1)
    end

    -- Replaces the crate of `kind` with a new one at (x, y, z); `objects` reuses the landed drop objects.
    local function createCrate(kind, x, y, z, objects, tableName, count, label)
        removeCrate(kind)
        local where = string.format("%.1f, %.1f, %.1f", x, y, z)
        -- db.exec callbacks get (ok, ctx, affectedRows, insertId)
        local insertContainer = "INSERT INTO containers (kind, size) VALUES ('supply', ?)"
        db.exec(insertContainer, { drops.CRATE_SIZE }, function(ok, _, _, cid)
            local containerId = ok and tonumber(cid)
            if not containerId then
                destroyObjects(objects)
                return util.log("loot", "warn", "%s at %s: container insert failed", label, where)
            end
            local sql = "INSERT INTO world_crates (kind, container_id, x, y, z) VALUES (?, ?, ?, ?, ?)"
            db.exec(sql, { kind, containerId, x, y, z }, function(ok2, _, _, crateId)
                local id = ok2 and tonumber(crateId)
                if not id then
                    destroyObjects(objects)
                    return util.log("loot", "warn", "%s at %s: world_crates insert failed", label, where)
                end
                local c = { id = id, kind = kind, containerId = containerId, x = x, y = y, z = z, objects = objects }
                if not c.objects or #c.objects == 0 then
                    c.objects = createObjects(kind, x, y, z)
                end
                crates[kind] = c
                tagObjects(c)
                fillContainer(containerId, tableName, count, label, where)
            end)
        end)
    end

    local function rebuildCrates()
        db.query("SELECT id, kind, container_id, x, y, z FROM world_crates ORDER BY id", {}, function(rows)
            for _, r in ipairs(rows or {}) do
                local c = { id = r.id, kind = r.kind, containerId = r.container_id, x = r.x, y = r.y, z = r.z }
                if crates[r.kind] then
                    destroyObjects(crates[r.kind].objects)
                end
                c.objects = createObjects(r.kind, r.x, r.y, r.z)
                crates[r.kind] = c
                tagObjects(c)
            end
            if rows and #rows > 0 then
                util.log("loot", "info", "%d crate(s) rebuilt from world_crates", #rows)
            end
        end)
    end

    -- The interact key next to a crate: the items resource shows the container like a trunk or safebox.
    net.handler("supplyCrateOpenRequested", function(p, crateId)
        crateId = tonumber(crateId)
        if not crateId then
            return
        end
        for kind, c in pairs(crates) do
            if c.id == crateId then
                local px, py, pz = getElementPosition(p)
                if getDistanceBetweenPoints3D(px, py, pz, c.x, c.y, c.z) > drops.OPEN_RADIUS + 1.0 then
                    return
                end
                local title, size = drops.TITLES[kind], drops.CRATE_SIZE
                exports.items:openSupplyContainer(p, c.containerId, title, size, c.x, c.y, c.z)
                return
            end
        end
    end, { rate = 5 })

    -- Supply drops -------------------------------------------------------------------------------------------

    local function land()
        local d = inFlight
        if not d then
            return
        end
        inFlight = nil
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
        createCrate("supply", d.x, d.y, d.z, d.objects, t.table, count, "supply crate (" .. t.name .. ")")
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
        local specs = drops.crateObjects("supply", x, y, z)
        local objects = {}
        for i, spec in ipairs(specs) do
            local startZ = spec.z - z + drops.DROP_HEIGHT
            local o = createObject(spec.model, spec.x, spec.y, startZ, spec.rx, spec.ry, spec.rz)
            if not o then
                destroyObjects(objects)
                return false, "NO_OBJECT"
            end
            objects[i] = o
            moveObject(o, ms, spec.x, spec.y, spec.z, 0, 0, 720)
        end
        local blip = createBlipAttachedTo(objects[1], 0, 2, 255, 200, 0, 255, 0, 99999)
        inFlight = { typeIdx = typeIdx, x = x, y = y, z = z, objects = objects, blip = blip }
        inFlight.timer = setTimer(land, ms, 1)
        triggerClientEvent(root, "supplyDropStarted", resourceRoot, objects[1], x, y, z)
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
        createCrate("cache", x, y, z, nil, drops.CACHE_TABLE, drops.cacheCount(rand), "weapons cache")
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
        local out = {
            inFlight = inFlight and drops.TYPES[inFlight.typeIdx].name or false,
            activeCache = activeCache and { x = activeCache.x, y = activeCache.y } or false,
            lastSupplyDropAgoS = lastSupplyDrop and math.floor((getTickCount() - lastSupplyDrop) / 1000) or false,
            crates = {},
        }
        for kind, c in pairs(crates) do
            out.crates[kind] = { id = c.id, containerId = c.containerId, x = c.x, y = c.y, z = c.z }
        end
        return out
    end

    function M.start()
        db.query("SELECT x, y, z FROM weapon_cache_points", {}, function(rows)
            cachePoints = rows or {}
        end)
        rebuildCrates()
        setTimer(supplyTick, num("loot.supply_tick_s", 60) * 1000, 0)
        scheduleCache()
    end

    function M.stop()
        if inFlight then
            destroyObjects(inFlight.objects)
            if isElement(inFlight.blip) then
                destroyElement(inFlight.blip)
            end
            inFlight = nil
        end
        for kind, c in pairs(crates) do
            destroyObjects(c.objects)
            crates[kind] = nil
        end
        activeCache = nil
    end

    return M
end
