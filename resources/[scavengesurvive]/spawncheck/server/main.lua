-- Spawn fit review (docs/reviews/2026-11-17-vehicle-spawn-fit.md): what tools/spawn_ground.py found, in the world.
-- Developer-level staff on duty turn it on with /spawncheck (staff resource): the client then draws the issues within
-- RADIUS (vehicle points with types removed, loot points with slots where an item size class fits no heading), and
-- /spawncheck next|prev|<id> walks through them. Read-only: it changes no data.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

local RADIUS, PUSH_MS, MOVE = 200, 2000, 25
local CHUNK = 500 -- loot rows parsed per timer tick
local DEV_LEVEL = 5 -- staff.MAX_LEVEL, "Developer"
local CLASSES = { "small", "medium", "long", "large" }
local RINGS = 6 -- loot roll.MAX_PER_SPAWN: rings past it are the outer room ring

local vehicleIssues, lootIssues = {}, {} -- arrays of issues, each { kind, id, x, y, z, ... }
local byKey = {} -- "v<id>" / "l<id>" -> issue
local viewers = {} -- player -> { kind, index, sent = { x, y, at } }
local loaded = false

local function onDuty(p)
    return getElementData(p, "staff.duty") == true and (tonumber(exports.staff:getLevel(p)) or 0) >= DEV_LEVEL
end

local VEHICLES_SQL = "SELECT s.id, s.x, s.y, s.z, s.rz, IFNULL(s.group_name, '') AS grp, "
    .. "IFNULL(s.type_name, '') AS tname, s.categories, s.sizes, IFNULL(pp.fits, 0) AS fits, "
    .. "IFNULL(pp.oneway, 0) AS oneway FROM vehicle_spawns s "
    .. "LEFT JOIN (SELECT spawn_id, COUNT(*) AS fits, SUM(heads = 1) AS oneway FROM (SELECT spawn_id, model, "
    .. "COUNT(*) AS heads FROM vehicle_spawn_poses GROUP BY spawn_id, model) m GROUP BY spawn_id) pp "
    .. "ON pp.spawn_id = s.id WHERE s.enabled = 1 AND EXISTS "
    .. "(SELECT 1 FROM vehicle_spawn_removed r WHERE r.spawn_id = s.id) ORDER BY s.id"
local REMOVED_SQL = "SELECT spawn_id, model, type_uname, reason, detail, ground_z, box_x0, box_x1, box_y0, box_y1, "
    .. "box_h, block_x, block_y, block_z FROM vehicle_spawn_removed ORDER BY spawn_id, type_uname"
local LOOT_SQL = "SELECT id, x, y, z, table_name, ground FROM loot_spawns WHERE enabled = 1 AND ground IS NOT NULL"

-- the slots of a loot point that fit some item size class at no heading, and which classes
local function lootIssue(r)
    local g = fromJSON(r.ground)
    if type(g) ~= "table" or type(g.s) ~= "table" then
        return nil
    end
    local slots, cramped, worst = {}, 0, {}
    for n, ring in ipairs(g.s) do
        for _, s in ipairs(ring) do
            if type(s) == "table" then
                local masks, none = {}, {}
                for c = 1, #CLASSES do
                    masks[c] = tonumber(s[5 + c]) or 0 -- the client only asks fits (> 0) or not
                    if n <= RINGS and masks[c] == 0 then
                        none[#none + 1] = CLASSES[c]
                        worst[CLASSES[c]] = (worst[CLASSES[c]] or 0) + 1
                    end
                end
                if #none > 0 then
                    cramped = cramped + 1
                end
                slots[#slots + 1] = { s[1], s[2], s[3], masks, n > RINGS }
            end
        end
    end
    if cramped == 0 then
        return nil
    end
    local text = {}
    for _, c in ipairs(CLASSES) do
        if worst[c] then
            text[#text + 1] = string.format("%s: no room at %d slot(s)", c, worst[c])
        end
    end
    return {
        kind = "loot",
        id = r.id,
        x = r.x,
        y = r.y,
        z = r.z,
        tbl = r.table_name,
        slots = slots,
        summary = table.concat(text, "; "),
    }
end

function reload(cb)
    loaded = false
    db.query(VEHICLES_SQL, {}, function(points)
        db.query(REMOVED_SQL, {}, function(removed)
            db.query(LOOT_SQL, {}, function(loot)
                vehicleIssues, lootIssues, byKey = {}, {}, {}
                local byPoint = {}
                for _, r in ipairs(removed or {}) do
                    byPoint[r.spawn_id] = byPoint[r.spawn_id] or {}
                    table.insert(byPoint[r.spawn_id], {
                        model = r.model,
                        uname = r.type_uname,
                        reason = r.reason,
                        blocker = (tostring(r.detail or ""):match("^%w+: ([^;]-) at ")) or r.reason,
                        gz = tonumber(r.ground_z),
                        box = r.box_x0 and { r.box_x0, r.box_x1, r.box_y0, r.box_y1, r.box_h } or nil,
                        at = r.block_x and { r.block_x, r.block_y, r.block_z } or nil,
                    })
                end
                for _, p in ipairs(points or {}) do
                    local fits = tonumber(p.fits) or 0
                    local list = byPoint[p.id] or {}
                    local issue = {
                        kind = "vehicle",
                        id = p.id,
                        x = p.x,
                        y = p.y,
                        z = p.z,
                        rz = p.rz,
                        group = p.tname ~= "" and p.tname or (p.grp .. " " .. p.categories .. "/" .. p.sizes),
                        fits = fits,
                        oneway = tonumber(p.oneway) or 0,
                        removed = list,
                        state = fits == 0 and "none" or "some",
                    }
                    vehicleIssues[#vehicleIssues + 1] = issue
                    byKey["v" .. p.id] = issue
                end
                -- the points where nothing fits first: they never spawn anything
                table.sort(vehicleIssues, function(a, b)
                    if (a.fits == 0) ~= (b.fits == 0) then
                        return a.fits == 0
                    end
                    return a.id < b.id
                end)
                -- the loot points' slot data is parsed CHUNK rows a frame: all at once trips the script watchdog
                loot = loot or {}
                local k = 0
                local function chunk()
                    for _ = 1, CHUNK do
                        k = k + 1
                        local r = loot[k]
                        if not r then
                            table.sort(lootIssues, function(a, b)
                                return a.id < b.id
                            end)
                            loaded = true
                            log.event("spawncheck.loaded", { vehicles = #vehicleIssues, loot = #lootIssues })
                            for p in pairs(viewers) do
                                viewers[p].sent = nil
                            end
                            if cb then
                                cb(#vehicleIssues, #lootIssues)
                            end
                            return
                        end
                        local issue = lootIssue(r)
                        if issue then
                            lootIssues[#lootIssues + 1] = issue
                            byKey["l" .. r.id] = issue
                        end
                    end
                    setTimer(chunk, 50, 1)
                end
                chunk()
            end)
        end)
    end)
end

local function near(p)
    local px, py = getElementPosition(p)
    local out = {}
    for _, list in ipairs({ vehicleIssues, lootIssues }) do
        for _, s in ipairs(list) do
            local dx, dy = s.x - px, s.y - py
            if dx * dx + dy * dy < RADIUS * RADIUS then
                out[#out + 1] = s
            end
        end
    end
    return out
end

local function push(p, force)
    local v = viewers[p]
    if not v then
        return
    end
    local x, y = getElementPosition(p)
    local s = v.sent
    if not force and s and math.abs(s.x - x) < MOVE and math.abs(s.y - y) < MOVE then
        return
    end
    v.sent = { x = x, y = y }
    triggerClientEvent(p, "spawnCheckChanged", p, near(p))
end

-- On or off for `p`; returns whether it is now on, and a message.
function toggle(p, on)
    if not isElement(p) or not onDuty(p) then
        return false, "Developer level, on duty"
    end
    if on == nil then
        on = viewers[p] == nil
    end
    if not on then
        viewers[p] = nil
        triggerClientEvent(p, "spawnCheckChanged", p, {})
        return false, "Spawn check hidden"
    end
    viewers[p] = viewers[p] or { kind = "vehicle", index = 0 }
    push(p, true)
    return true,
        string.format(
            "Spawn check: %d vehicle points with removed types, %d loot points with cramped slots",
            #vehicleIssues,
            #lootIssues
        )
end

local function describe(s)
    if s.kind == "vehicle" then
        local parts = {}
        for k, r in ipairs(s.removed) do
            if k > 6 then
                parts[#parts + 1] = string.format("+%d more", #s.removed - 6)
                break
            end
            parts[#parts + 1] = string.format("%s (%s)", r.uname, r.blocker)
        end
        return string.format(
            "Vehicle point %d (%s): %s, %d removed: %s",
            s.id,
            s.group,
            s.fits == 0 and "NOTHING FITS" or (s.fits .. " types fit"),
            #s.removed,
            table.concat(parts, ", ")
        )
    end
    return string.format("Loot point %d (%s): %s", s.id, s.tbl, s.summary)
end

-- Walk the issues: arg "next" / "prev" (in the current kind), "vehicles" / "loot" (switch kind, go to the first), or
-- a point id (of the current kind). Teleports `p` beside the point. Returns a message.
function step(p, arg)
    if not loaded then
        return "Spawn check data is still loading"
    end
    if not viewers[p] then
        local on, msg = toggle(p, true)
        if not on then
            return msg
        end
    end
    local v = viewers[p]
    arg = tostring(arg or "next"):lower()
    if arg == "vehicles" or arg == "vehicle" or arg == "loot" then
        v.kind, v.index = arg == "loot" and "loot" or "vehicle", 0
        arg = "next"
    end
    local list = v.kind == "loot" and lootIssues or vehicleIssues
    if #list == 0 then
        return "No " .. v.kind .. " issues"
    end
    local target
    local id = tonumber(arg)
    if id then
        target = byKey[(v.kind == "loot" and "l" or "v") .. id]
        if not target then
            return string.format("No %s issue at point %d", v.kind, id)
        end
        for k, s in ipairs(list) do
            if s == target then
                v.index = k
            end
        end
    else
        v.index = ((v.index + (arg == "prev" and -2 or 0)) % #list) + 1
        target = list[v.index]
    end
    -- stand a few metres off the point, facing it, so the drawn boxes are in view
    removePedFromVehicle(p)
    setElementInterior(p, 0)
    setElementDimension(p, 0)
    setElementPosition(p, target.x - 6, target.y - 6, target.z + 2)
    setElementRotation(p, 0, 0, 315)
    push(p, true)
    log.event("spawncheck.visited", { player = p, kind = v.kind, point_id = target.id })
    return string.format("[%d/%d] %s", v.index, #list, describe(target))
end

setTimer(function()
    for p in pairs(viewers) do
        if not isElement(p) or not onDuty(p) then
            viewers[p] = nil
            if isElement(p) then
                triggerClientEvent(p, "spawnCheckChanged", p, {})
            end
        else
            push(p, false)
        end
    end
end, PUSH_MS, 0)

addEventHandler("onPlayerQuit", root, function()
    viewers[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if db.connect("spawncheck") then
        reload()
    end
end)
