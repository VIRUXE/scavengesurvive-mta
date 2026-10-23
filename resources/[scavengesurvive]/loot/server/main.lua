local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local budget = loadstring(exports.lib:getModule("budget"), "=lib/budget.lua")()
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

-- Per-zone carrying capacity: enabled points × items_per_point × cap_multiplier; a new zone starts full
-- (allowance = cap), an existing row only has its cap recomputed so a settings change applies on restart.
local UPSERT_BUDGETS = "INSERT INTO world_budget (category, zone, cap, remainder, allowance) "
    .. "SELECT 'loot', zone, ROUND(COUNT(*) * ? * ?), 0, ROUND(COUNT(*) * ? * ?) "
    .. "FROM loot_spawns WHERE enabled = 1 GROUP BY zone "
    .. "ON DUPLICATE KEY UPDATE cap = VALUES(cap), allowance = LEAST(allowance, VALUES(cap))"

-- alive = every item that came from a loot point of the zone, wherever it is now (ADR 0001: carried stock counts);
-- loot.count_carried = 0 counts only items in the world or in containers.
local SELECT_BUDGETS = "SELECT b.zone, b.cap, b.remainder, b.allowance, (SELECT COUNT(*) FROM items i "
    .. "WHERE i.loot_zone = b.zone AND (? = 1 OR i.holder_char_id IS NULL)) AS alive "
    .. "FROM world_budget b WHERE b.category = 'loot'"

local UPDATE_BUDGET = "UPDATE world_budget SET remainder = ?, "
    .. "allowance = LEAST(allowance + ?, GREATEST(cap - ?, 0)) WHERE category = 'loot' AND zone = ?"

local SPEND_BUDGET = "UPDATE world_budget SET allowance = GREATEST(allowance - ?, 0) "
    .. "WHERE category = 'loot' AND zone = ?"

local function setting(key, default)
    return tonumber(settings[key]) or default
end

local function loadAllowances(cb)
    db.query("SELECT zone, allowance FROM world_budget WHERE category = 'loot'", {}, function(rows)
        for _, r in ipairs(rows or {}) do
            allowance[r.zone] = tonumber(r.allowance) or 0
        end
        if cb then
            cb()
        end
    end)
end

-- The ADR 0001 refill tick: each zone earns spawns in proportion to its deficit, never beyond it.
local function refillTick()
    local rate, floor = setting("loot.refill_rate", 0.10), setting("loot.refill_floor", 0.02)
    local interval = setting("world.refill_interval_s", 300)
    local carried = setting("loot.count_carried", 1)
    db.query(SELECT_BUDGETS, { carried }, function(rows)
        if not rows then
            return
        end
        local zones, totalCap, totalAlive, totalAllow, added = 0, 0, 0, 0, 0
        for _, b in ipairs(rows) do
            local cap, alive = tonumber(b.cap) or 0, tonumber(b.alive) or 0
            local spawns, remainder = budget.refill(cap, alive, tonumber(b.remainder) or 0, rate, floor, interval)
            db.exec(UPDATE_BUDGET, { remainder, spawns, alive, b.zone })
            local allow = math.min((tonumber(b.allowance) or 0) + spawns, math.max(cap - alive, 0))
            allowance[b.zone] = allow
            zones, added = zones + 1, added + spawns
            totalCap, totalAlive, totalAllow = totalCap + cap, totalAlive + alive, totalAllow + allow
        end
        local line = "refill: %d zones, alive %d/%d, allowance %d (+%d)"
        util.log("loot", "info", line, zones, totalAlive, totalCap, totalAllow, added)
    end)
end

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
    util = util,
    roll = roll,
    drops = dropsLogic,
    lootTable = lootTable,
    settings = function()
        return settings
    end,
})

local function rollSpawn(s)
    local tbl = lootTable(s.table_name)
    if not tbl then
        -- disable the spawn so it is never re-selected; warn once per table name
        if not warnedTables[s.table_name] then
            warnedTables[s.table_name] = true
            util.log("loot", "warn", "unknown loot table %s (spawn %d and others disabled)", s.table_name, s.id)
        end
        db.exec("UPDATE loot_spawns SET enabled = 0 WHERE id = ?", { s.id })
        return
    end
    local mult = setting("loot.spawn_multiplier", 1.0)
    local unames = roll.pick(tbl, s.size, s.weight, mult, math.random)
    -- the zone pays for this roll; a roll bigger than what is left is trimmed, an empty roll costs nothing
    local left = allowance[s.zone] or 0
    while #unames > left do
        unames[#unames] = nil
    end
    allowance[s.zone] = left - #unames
    if #unames > 0 then
        db.exec(SPEND_BUDGET, { #unames, s.zone })
    end
    for i, uname in ipairs(unames) do
        local def = exports.data:itemType(uname)
        if def then
            local ang = math.rad(i * (360 / #unames))
            local x, y = s.x + math.cos(ang) * 0.6, s.y + math.sin(ang) * 0.6
            local cal = def.categoryData and def.categoryData.calibre
            local ammoTypes = cal and exports.data:ammoTypesForCalibre(cal) or nil
            local dataJson = roll.initialItemData(def, s.table_name, ammoTypes, math.random)
            -- hitpoints is NULL; n is required because of the embedded nils
            local params = {
                uname,
                nil,
                dataJson,
                x,
                y,
                s.z + 0.1032,
                math.random(0, 359),
                s.interior,
                s.dimension,
                s.id,
                s.despawn_at, -- computed by the DB (the only clock) in rollNear's SELECT
                n = 11,
            }
            db.call("item_create", params, function(res)
                if not res or not res.ok then
                    util.log("loot", "warn", "item_create %s failed: %s", uname, res and res.code or "db")
                end
            end)
        end
    end
    -- the point cools down from the roll: loot.cooldown_minutes ± jitter before it may roll again
    local base = setting("loot.cooldown_minutes", 60) * 60
    local secs = budget.cooldown(base, setting("loot.cooldown_jitter", 0.5), math.random)
    db.exec("UPDATE loot_spawn_state SET next_roll_at = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE spawn_id = ?", {
        secs,
        s.id,
    })
    triggerEvent("lootSpawned", resourceRoot, s.id, #unames)
end

-- Rolls due spawns inside a box around (x, y): spawns are due when next_roll_at has passed and no item from the
-- previous roll remains in the world; the zone must still have allowance and no player may be within
-- world.min_player_distance of the point.
function rollNear(x, y, radius)
    local batch = setting("loot.roll_batch", 300)
    local despawn = setting("loot.despawn_minutes", 120)
    local sql = "SELECT s.id, s.x, s.y, s.z, s.zone, s.table_name, s.weight, s.size, s.interior, s.dimension, "
        .. "DATE_FORMAT(DATE_ADD(NOW(), INTERVAL ? MINUTE), '%Y-%m-%d %H:%i:%s') AS despawn_at "
        .. "FROM loot_spawns s "
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
    db.query(sql, { despawn }, function(rows)
        if not rows then
            return
        end
        local players, minDist = playerPositions(), setting("world.min_player_distance", 150)
        for _, s in ipairs(rows) do
            local clear = (allowance[s.zone] or 0) > 0 and budget.clearOfPlayers(s.x, s.y, players, minDist)
            if clear and not busy[s.id] then
                busy[s.id] = true
                rollSpawn(s)
                setTimer(function(id)
                    busy[id] = nil
                end, 5000, 1, s.id)
            end
        end
    end)
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("loot") then
        return
    end
    db.settings(function(map)
        settings = map
        drops.start()
        local perPoint, mult = setting("loot.items_per_point", 2.0), setting("loot.cap_multiplier", 1.0)
        db.exec(UPSERT_BUDGETS, { perPoint, mult, perPoint, mult }, function()
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

setTimer(function()
    for _, p in ipairs(getElementsByType("player")) do
        if exports.character:getCharacterId(p) then
            local x, y = getElementPosition(p)
            rollNear(x, y, 400)
        end
    end
end, 15000, 0)

addEventHandler("playerZoneEntered", root, function()
    if exports.character:getCharacterId(source) then
        local x, y = getElementPosition(source)
        rollNear(x, y, 400)
    end
end)
