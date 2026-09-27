local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local roll
do
    local f = fileOpen("shared/logic/roll.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    roll = assert(loadstring(src, "=loot/roll.lua"))()
end
local settings = {}
local tableCache = {}
local busy = {}

local function lootTable(name)
    if tableCache[name] == nil then
        tableCache[name] = exports.data:lootTable(name) or false
    end
    return tableCache[name] or nil
end

local function rollSpawn(s)
    local tbl = lootTable(s.table_name)
    if not tbl then
        return util.log("loot", "warn", "unknown loot table %s at spawn %d", s.table_name, s.id)
    end
    local mult = tonumber(settings["loot.spawn_multiplier"]) or 1.0
    local unames = roll.pick(tbl, s.size, s.weight, mult, math.random)
    local despawn = tonumber(settings["loot.despawn_minutes"]) or 120
    local reroll = tonumber(settings["loot.reroll_minutes"]) or 30
    for i, uname in ipairs(unames) do
        if exports.data:itemType(uname) then
            local ang = math.rad(i * (360 / #unames))
            local x, y = s.x + math.cos(ang) * 0.6, s.y + math.sin(ang) * 0.6
            local despawnAt = os.date("!%Y-%m-%d %H:%M:%S", os.time() + despawn * 60)
            -- hitpoints and data are NULL; n is required because of the embedded nils
            local params = {
                uname,
                nil,
                nil,
                x,
                y,
                s.z + 0.1032,
                math.random(0, 359),
                s.interior,
                s.dimension,
                s.id,
                despawnAt,
                n = 11,
            }
            db.call("item_create", params, function(res)
                if not res or not res.ok then
                    util.log("loot", "warn", "item_create %s failed: %s", uname, res and res.code or "db")
                end
            end)
        end
    end
    db.exec("UPDATE loot_spawn_state SET next_roll_at = DATE_ADD(NOW(), INTERVAL ? MINUTE) WHERE spawn_id = ?", {
        reroll,
        s.id,
    })
    triggerEvent("onLootSpawned", resourceRoot, s.id, #unames)
end

-- Rolls due spawns inside a box around (x, y): spawns are due when next_roll_at has passed and no item from the
-- previous roll remains in the world.
function rollNear(x, y, radius)
    local batch = tonumber(settings["loot.roll_batch"]) or 300
    local sql = "SELECT s.id, s.x, s.y, s.z, s.table_name, s.weight, s.size, s.interior, s.dimension "
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
    db.query(sql, {}, function(rows)
        if not rows then
            return
        end
        for _, s in ipairs(rows) do
            if not busy[s.id] then
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
    end)
    db.exec("INSERT IGNORE INTO loot_spawn_state (spawn_id, next_roll_at) SELECT id, NOW() FROM loot_spawns", {})
end)

setTimer(function()
    for _, p in ipairs(getElementsByType("player")) do
        if exports.character:getCharacterId(p) then
            local x, y = getElementPosition(p)
            rollNear(x, y, 400)
        end
    end
end, 15000, 0)
