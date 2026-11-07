local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local spawnGuard = loadstring(exports.lib:getModule("spawn_guard"), "=lib/spawn_guard.lua")().new()
local budget = loadstring(exports.lib:getModule("budget"), "=lib/budget.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=loot/" .. path))()
end
local roll = loadFile("shared/logic/roll.lua")
local dropsLogic = loadFile("shared/logic/drops.lua")
local settings = {}
local tableCache = {}
local busy = {}
local warnedTables = {}
local allowance = {} -- zone -> items the zone may still spawn (cache of world_budget.allowance between refill ticks)
local refillTimer = nil
local budgetBusy = true -- serialize placement and refill; startup loads the persisted budget first
local vendingTick -- the snack machines' budget tick, with stockContainer below

-- Per-zone carrying capacity: enabled points × items_per_point × cap_multiplier.
-- New zones earn their first allowance on the refill tick; restarts never mint supply.
local UPSERT_BUDGETS = "INSERT INTO world_budget (category, zone, cap, remainder, allowance) "
    .. "SELECT 'loot', zone, ROUND(COUNT(*) * ? * ?), 0, 0 "
    .. "FROM loot_spawns WHERE enabled = 1 GROUP BY zone "
    .. "ON DUPLICATE KEY UPDATE cap = VALUES(cap), allowance = LEAST(allowance, VALUES(cap))"

-- alive = every item that came from a loot point of the zone, wherever it is now (ADR 0001: carried stock counts);
-- loot.count_carried = 0 counts only items in the world or in containers.
local SELECT_BUDGETS = "SELECT b.zone, b.cap, b.remainder, b.allowance, (SELECT COUNT(*) FROM items i "
    .. "WHERE i.loot_zone = b.zone AND (? = 1 OR i.holder_char_id IS NULL)) AS alive "
    .. "FROM world_budget b WHERE b.category = 'loot'"

-- The cap is passed in: the stored cap scaled for the players online.
local UPDATE_BUDGET = "UPDATE world_budget SET remainder = ?, "
    .. "allowance = LEAST(?, GREATEST(? - ?, 0)) WHERE category = 'loot' AND zone = ?"

local function setting(key, default)
    return tonumber(settings[key]) or default
end

-- Players with a character in the world, for loot.player_scale.
local function onlinePlayers()
    local n = 0
    for _, p in ipairs(getElementsByType("player")) do
        if exports.character:getCharacterId(p) then
            n = n + 1
        end
    end
    return n
end

-- The stored zone cap scaled for the players online (budget.playerScale with loot.player_scale).
local function scaledCap(cap, scale)
    return math.floor((tonumber(cap) or 0) * scale + 0.5)
end

-- Unspent refill expires at the next tick. Banking it lets an unexplored area release hours of
-- supply in seconds. On restart, retain at most one interval (never award fresh allowance).
local function loadAllowances(cb)
    db.query(SELECT_BUDGETS, { setting("loot.count_carried", 1) }, function(rows)
        if not rows then
            allowance = {} -- fail closed until a successful refill reloads the budget
            budgetBusy = false
            return
        end
        local scale = budget.playerScale(onlinePlayers(), setting("loot.player_scale", 0.25))
        for _, r in ipairs(rows) do
            local quota = budget.refill(
                scaledCap(r.cap, scale),
                tonumber(r.alive),
                0.999999,
                setting("loot.refill_rate", 0.10),
                setting("loot.refill_floor", 0.02),
                setting("world.refill_interval_s", 300)
            )
            allowance[r.zone] = math.min(tonumber(r.allowance) or 0, quota)
            db.exec(
                "UPDATE world_budget SET allowance = LEAST(allowance, ?) WHERE category = 'loot' AND zone = ?",
                { allowance[r.zone], r.zone }
            )
        end
        -- FIFO DB queue: release placement only after the startup clamps have committed.
        db.query("SELECT 1", {}, function()
            budgetBusy = false
            if cb then
                cb()
            end
        end)
    end)
end

-- The ADR 0001 refill tick: each zone earns spawns in proportion to its deficit, never beyond it.
local function refillTick()
    if budgetBusy then
        return
    end
    budgetBusy = true
    local rate, floor = setting("loot.refill_rate", 0.10), setting("loot.refill_floor", 0.02)
    local interval = setting("world.refill_interval_s", 300)
    local carried = setting("loot.count_carried", 1)
    db.query(SELECT_BUDGETS, { carried }, function(rows)
        if not rows then
            budgetBusy = false
            return
        end
        local players = onlinePlayers()
        local scale = budget.playerScale(players, setting("loot.player_scale", 0.25))
        local zones, added, totalCap, totalAlive, totalAllow = 0, 0, 0, 0, 0
        for _, b in ipairs(rows) do
            local cap, alive = scaledCap(b.cap, scale), tonumber(b.alive) or 0
            local spawns, remainder = budget.refill(cap, alive, tonumber(b.remainder) or 0, rate, floor, interval)
            db.exec(UPDATE_BUDGET, { remainder, spawns, cap, alive, b.zone })
            allowance[b.zone] = spawns
            zones, added = zones + 1, added + spawns
            totalCap, totalAlive, totalAllow = totalCap + cap, totalAlive + alive, totalAllow + spawns
            log.event(
                "loot.refillTicked",
                { zone = b.zone, cap = cap, alive = alive, spawned = spawns, allowance = spawns }
            )
        end
        db.query("SELECT zone, allowance FROM world_budget WHERE category = 'loot'", {}, function(saved)
            if saved then
                for _, row in ipairs(saved) do
                    allowance[row.zone] = tonumber(row.allowance) or 0
                end
            else
                allowance = {}
            end
            budgetBusy = false
        end)
        vendingTick(scale, interval)
        log.event("loot.refillSummary", {
            zones = zones,
            alive = totalAlive,
            capacity = totalCap,
            allowance = totalAllow,
            added = added,
            players = players,
            scale = scale,
        })
    end)
end

-- A character ID is installed before spawnPlayer finishes. Wait for the first settled
-- non-origin position before allowing that player to activate lazy loot placement.
local function playerReady(player)
    if not exports.character:getCharacterId(player) or isPedDead(player) then
        return false
    end
    local x, y, z = getElementPosition(player)
    return spawnGuard.ready(player, getTickCount(), x, y, z)
end
addEventHandler("onPlayerSpawn", root, function()
    spawnGuard.reset(source, getTickCount())
end)
addEventHandler("onPlayerQuit", root, function()
    spawnGuard.forget(source)
end)

local function playerPositions()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        local x, y = getElementPosition(p)
        out[#out + 1] = { x = x, y = y }
    end
    return out
end

local function lootTable(name)
    if tableCache[name] == nil then
        tableCache[name] = exports.data:lootTable(name) or false
    end
    return tableCache[name] or nil
end

local drops = loadFile("server/drops.lua")({
    db = db,
    net = net,
    util = util,
    roll = roll,
    drops = dropsLogic,
    lootTable = lootTable,
    log = log,
    settings = function()
        return settings
    end,
})

-- One spawn's roll for loot_roll: { s = id, cd = cooldown seconds, items = { { u, data, x, y, z, rz } } }, or nil
-- for a spawn whose loot table is unknown (disabled instead).
local function rollSpawn(s)
    local tbl = lootTable(s.table_name)
    if not tbl then
        -- disable the spawn so it is never re-selected; warn once per table name
        if not warnedTables[s.table_name] then
            warnedTables[s.table_name] = true
            util.log("loot", "warn", "unknown loot table %s (spawn %d and others disabled)", s.table_name, s.id)
        end
        db.exec("UPDATE loot_spawns SET enabled = 0 WHERE id = ?", { s.id })
        return nil
    end
    local mult = setting("loot.spawn_multiplier", 1.0)
    local unames = roll.pick(tbl, s.size, s.weight, mult, math.random)
    -- the zone pays for this roll (loot_roll spends it); a roll bigger than what is left is trimmed
    local left = allowance[s.zone] or 0
    while #unames > left do
        unames[#unames] = nil
    end
    allowance[s.zone] = left - #unames
    local items = {}
    for i, uname in ipairs(unames) do
        local def = exports.data:itemType(uname)
        if def then
            local ang = math.rad(i * (360 / #unames))
            local cal = def.categoryData and def.categoryData.calibre
            local ammoTypes = cal and exports.data:ammoTypesForCalibre(cal) or nil
            local medical = roll.MEDICAL_DATA[uname] and exports.character:medicalLootData(uname)
            items[#items + 1] = {
                u = uname,
                data = medical or roll.initialItemData(def, s.table_name, ammoTypes, math.random), -- JSON text or nil
                x = s.x + math.cos(ang) * 0.6,
                y = s.y + math.sin(ang) * 0.6,
                z = s.z + 0.1032,
                rz = math.random(0, 359),
            }
        end
    end
    -- the point cools down from the roll: loot.cooldown_minutes ± jitter before it may roll again
    local base = setting("loot.cooldown_minutes", 360) * 60
    local secs = budget.cooldown(base, setting("loot.cooldown_jitter", 0.5), math.random)
    return { s = s.id, cd = secs, items = items }
end

-- A Heart Shaped Box that loot spawns comes with these inside (upstream item/heartshapedbox.pwn, #143): after a
-- roll, every box of the batch whose container is still empty gets them, one item_create_in_container each.
local LOVE_BOX, LOVE_BOX_CONTENTS = "HeartShapedBox", { "Dildo1", "Flowers", "AntiSepBandage", "ZorroMask" }
local function fillLoveBoxes(done)
    local ids = {}
    for _, r in ipairs(done) do
        ids[#ids + 1] = string.format("%d", tonumber(r.s) or 0)
    end
    if #ids == 0 then
        return
    end
    local sql = "SELECT c.id AS cid FROM items i JOIN containers c ON c.owner_item_id = i.id "
        .. "WHERE i.type_uname = '"
        .. LOVE_BOX
        .. "' AND i.loot_spawn_id IN ("
        .. table.concat(ids, ",")
        .. ") AND NOT EXISTS (SELECT 1 FROM items x WHERE x.container_id = c.id)"
    db.query(sql, {}, function(rows)
        for _, row in ipairs(rows or {}) do
            for _, uname in ipairs(LOVE_BOX_CONTENTS) do
                db.call("item_create_in_container", { uname, row.cid }, function(res)
                    if not res or not res.ok then
                        local code = res and res.code or "db"
                        util.log("loot", "warn", "love box %d: %s not added (%s)", row.cid, uname, code)
                    end
                end)
            end
        end
    end)
end

-- One item out of a loot table (upstream CreateLootItem): its uname and starting data (JSON text or nil), for the
-- anticheat's hacker traps. nil, nil for an unknown table.
function pickItem(tableName)
    local tbl = lootTable(tostring(tableName))
    if not tbl then
        return nil, nil
    end
    local unames = {}
    for _ = 1, 20 do
        unames = roll.pick(tbl, 1, 100, 1, math.random)
        if #unames > 0 then
            break
        end
    end
    local def = unames[1] and exports.data:itemType(unames[1])
    if not def then
        return nil, nil
    end
    local cal = def.categoryData and def.categoryData.calibre
    local ammoTypes = cal and exports.data:ammoTypesForCalibre(cal) or nil
    local medical = roll.MEDICAL_DATA[def.uname] and exports.character:medicalLootData(def.uname)
    return def.uname, medical or roll.initialItemData(def, tostring(tableName), ammoTypes, math.random)
end

-- Stocks a vehicle's glovebox container with up to `count` items rolled from tableName (small items only, the table
-- decides); one that does not fit is skipped. Returns the number rolled; loot.gloveboxStocked follows with how many
-- went in.
function stockGlovebox(containerId, tableName, count)
    containerId, count = tonumber(containerId), math.floor(tonumber(count) or 0)
    if not containerId or count < 1 then
        return 0
    end
    local rolled = {}
    for _ = 1, count do
        local uname, data = pickItem(tableName)
        if uname then
            rolled[#rolled + 1] = { uname = uname, data = data }
        end
    end
    local placed = 0
    local function place(i)
        local r = rolled[i]
        if not r then
            return log.event("loot.gloveboxStocked", { container_id = containerId, rolled = #rolled, items = placed })
        end
        db.call("item_create_in_container", { r.uname, containerId }, function(res)
            if res and res.ok then
                placed = placed + 1
                if r.data and res.payload and res.payload.item_id then
                    db.exec("UPDATE items SET data = ? WHERE id = ?", { r.data, res.payload.item_id })
                end
            elseif not res or res.code ~= "CONTAINER_FULL" then
                util.log(
                    "loot",
                    "warn",
                    "glovebox %d: %s not added (%s)",
                    containerId,
                    r.uname,
                    res and res.code or "db"
                )
            end
            place(i + 1)
        end)
    end
    place(1)
    return #rolled
end

-- Rolls due spawns inside a box around (x, y): spawns are due when next_roll_at has passed and no item from the
-- previous roll remains in the world; the zone must still have allowance and no player may be within
-- world.min_player_distance of the point. Every roll of the batch goes to the DB in one loot_roll call.
function rollNear(x, y, radius, onDone)
    if budgetBusy then
        if onDone then
            onDone()
        end
        return false
    end
    budgetBusy = true
    local function finish()
        budgetBusy = false
        if onDone then
            onDone()
        end
    end
    local batch = setting("loot.roll_batch", 300)
    local sql = "SELECT s.id, s.x, s.y, s.z, s.zone, s.table_name, s.weight, s.size FROM loot_spawns s "
        .. "JOIN loot_spawn_state st ON st.spawn_id = s.id WHERE s.enabled = 1 AND st.next_roll_at <= NOW() "
        .. "AND NOT EXISTS (SELECT 1 FROM items i WHERE i.loot_spawn_id = s.id) "
        .. string.format(
            "AND MBRContains(ST_GeomFromText('POLYGON((%g %g,%g %g,%g %g,%g %g,%g %g))'), s.pos) LIMIT %d",
            x - radius,
            y - radius,
            x + radius,
            y - radius,
            x + radius,
            y + radius,
            x - radius,
            y + radius,
            x - radius,
            y - radius,
            batch
        )
    db.query(sql, {}, function(rows)
        if not rows then
            finish()
            return
        end
        local players, minDist = playerPositions(), setting("world.min_player_distance", 150)
        local rolls, zoneOf = {}, {}
        for _, s in ipairs(rows) do
            local clear = (allowance[s.zone] or 0) > 0 and budget.clearOfPlayers(s.x, s.y, players, minDist)
            if clear and not busy[s.id] then
                local r = rollSpawn(s)
                if r then
                    busy[s.id] = true
                    zoneOf[s.id] = s.zone
                    rolls[#rolls + 1] = r
                end
            end
        end
        if #rolls == 0 then
            finish()
            return
        end
        local started = getTickCount()
        db.call("loot_roll", { toJSON(rolls), setting("loot.despawn_minutes", 120) }, function(res, done)
            local zoneSeen, zoneCount, itemCount = {}, 0, 0
            for _, r in ipairs(done) do
                busy[r.s] = nil
                itemCount = itemCount + #r.items
                local zone = zoneOf[r.s]
                if zone and not zoneSeen[zone] then
                    zoneSeen[zone] = true
                    zoneCount = zoneCount + 1
                end
            end
            local line = { zones = zoneCount, spots = #done, items = itemCount, ms = getTickCount() - started }
            if not res or not res.ok then
                loadAllowances(onDone) -- restore reservations from the rolled-back transaction
                line.ok, line.code = false, res and res.code or "DB_ERROR"
                log.event("loot.rolled", line, "warn")
                return
            end
            log.event("loot.rolled", line)
            for _, r in ipairs(done) do
                triggerEvent("lootSpawned", resourceRoot, r.s, #r.items, r.items)
            end
            fillLoveBoxes(done)
            finish()
        end, rolls)
    end)
    return true
end

-- The snack machines' own budget (world/server/vending.lua through stockContainer), apart from the loot points': per
-- zone a capacity of loot.vending_fill of the slots of the machines there (scaled for the players online like the
-- loot cap), alive = what they were stocked with that still exists (loot_zone "v_<zone>", carried too while
-- loot.count_carried), refilled every tick by budget.refill at loot.vending_refill_rate with a floor of
-- loot.vending_refill_floor per hour, banked between restocks up to the deficit. Kept in memory: a restart starts
-- every zone at nothing and the ticks earn it back (ADR 0001: restarts never mint supply).
local VENDING = "v_"
local fixedContainers = {} -- container id -> { zone, size }, learned from stockContainer
local vendingAllowance, vendingRemainder = {}, {}

function vendingTick(scale, interval)
    local slots = {}
    for _, c in pairs(fixedContainers) do
        slots[c.zone] = (slots[c.zone] or 0) + c.size
    end
    if not next(slots) then
        return
    end
    local sql = "SELECT loot_zone, COUNT(*) AS n FROM items WHERE loot_zone LIKE 'v\\_%' "
        .. "AND (? = 1 OR holder_char_id IS NULL) GROUP BY loot_zone"
    db.query(sql, { setting("loot.count_carried", 1) }, function(rows)
        if not rows then
            return
        end
        local alive = {}
        for _, r in ipairs(rows) do
            alive[r.loot_zone] = tonumber(r.n) or 0
        end
        local rate, floor = setting("loot.vending_refill_rate", 0.5), setting("loot.vending_refill_floor", 0.05)
        for zone, n in pairs(slots) do
            local cap = math.floor(n * setting("loot.vending_fill", 0.5) * scale + 0.5)
            local have = alive[VENDING .. zone] or 0
            local spawns, rem = budget.refill(cap, have, vendingRemainder[zone] or 0, rate, floor, interval)
            vendingRemainder[zone] = rem
            vendingAllowance[zone] = math.min((vendingAllowance[zone] or 0) + spawns, math.max(cap - have, 0))
            log.event(
                "loot.vendingTicked",
                { zone = zone, cap = cap, alive = have, spawned = spawns, allowance = vendingAllowance[zone] }
            )
        end
    end)
end

-- Restocks a fixed container of `size` slots (the snack machines, world/server/vending.lua) out of its zone's vending
-- budget: up to `free` items rolled from `tableName` (one pick per free slot, two of a kind allowed), no more than
-- the budget still allows, appended by loot_stock_container with loot_zone "v_<zone>" (the zone is that of the
-- nearest loot point, looked up once). Every item of the table must be of size 1. Asynchronous:
-- lootContainerStocked (containerId, created) follows on resourceRoot when the call went through. false when nothing
-- was asked of the database.
function stockContainer(containerId, x, y, tableName, free, size)
    containerId, free, size = tonumber(containerId), tonumber(free) or 0, tonumber(size) or 0
    local tbl = lootTable(tostring(tableName))
    if not containerId or not tbl then
        return false
    end
    local function stock(zone)
        local left = vendingAllowance[zone] or 0
        local unames = roll.fill(tbl, math.min(free, left), math.random)
        if #unames == 0 then
            return
        end
        vendingAllowance[zone] = left - #unames
        local items = {}
        for i, uname in ipairs(unames) do
            items[i] = { u = uname }
        end
        db.call("loot_stock_container", { containerId, VENDING .. zone, toJSON(items) }, function(res)
            local made = res and res.ok and res.payload and tonumber(res.payload.created) or 0
            local line = { container_id = containerId, zone = zone, rolled = #unames, items = made }
            if not (res and res.ok) then
                vendingAllowance[zone] = (vendingAllowance[zone] or 0) + #unames -- the rolled-back call spent nothing
                line.ok, line.code = false, res and res.code or "DB_ERROR"
                return log.event("loot.containerStocked", line, "warn")
            end
            if made < #unames then
                vendingAllowance[zone] = (vendingAllowance[zone] or 0) + #unames - made
            end
            log.event("loot.containerStocked", line)
            triggerEvent("lootContainerStocked", resourceRoot, containerId, made)
        end)
    end
    local known = fixedContainers[containerId]
    if known then
        known.size = size > 0 and size or known.size
        if free > 0 then
            stock(known.zone)
        end
        return free > 0
    end
    local sql = string.format(
        "SELECT zone FROM loot_spawns WHERE enabled = 1 ORDER BY ST_Distance(pos, POINT(%f, %f)) LIMIT 1",
        tonumber(x) or 0,
        tonumber(y) or 0
    )
    db.one(sql, {}, function(row)
        if row and row.zone then
            fixedContainers[containerId] = { zone = row.zone, size = size }
            if free > 0 then
                stock(row.zone)
            end
        end
    end)
    return true
end

local overlay = loadFile("server/overlay.lua")({
    db = db,
    roll = roll,
    setting = setting,
    allowance = function()
        return allowance
    end,
})

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("loot") then
        return
    end
    db.settings(function(map)
        settings = map
        drops.start()
        overlay.start()
        local perPoint, mult = setting("loot.items_per_point", 2.0), setting("loot.cap_multiplier", 0.05)
        db.exec(UPSERT_BUDGETS, { perPoint, mult }, function()
            loadAllowances()
        end)
        if isTimer(refillTimer) then
            killTimer(refillTimer)
        end
        refillTimer = setTimer(refillTick, setting("world.refill_interval_s", 300) * 1000, 0)
    end)
    db.exec("INSERT IGNORE INTO loot_spawn_state (spawn_id, next_roll_at) SELECT id, NOW() FROM loot_spawns", {})
end)

addEventHandler("onResourceStop", resourceRoot, function()
    drops.stop()
end)

-- Export for staff tooling and the smoke test: the loot budget per zone as cached since the last refill tick
function lootAllowances()
    local out = {}
    for zone, n in pairs(allowance) do
        out[zone] = n
    end
    return out
end

-- Exports for staff (/sc, /wc) and other resources
function dropSupply(typeIdx, x, y, z, locationName)
    return drops.dropSupply(typeIdx, x, y, z, locationName)
end

function dropWeaponCache(x, y, z)
    return drops.dropWeaponCache(x, y, z)
end

function supplyDropTypes()
    return drops.types()
end

function dropStatus()
    return drops.status()
end

-- Visit every player sequentially so asynchronous reservations cannot overlap or starve
-- everyone after the first player in the list.
setTimer(function()
    local players = getElementsByType("player")
    local index = 0
    local function nextPlayer()
        index = index + 1
        local p = players[index]
        if not p then
            return
        end
        if not isElement(p) or not playerReady(p) then
            return nextPlayer()
        end
        local x, y = getElementPosition(p)
        rollNear(x, y, 400, nextPlayer)
    end
    nextPlayer()
end, 15000, 0)

addEventHandler("playerZoneEntered", root, function()
    if playerReady(source) then
        local x, y = getElementPosition(source)
        rollNear(x, y, 400)
    end
end)
