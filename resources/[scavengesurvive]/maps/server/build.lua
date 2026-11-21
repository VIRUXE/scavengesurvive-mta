-- Builds upstream's static maps on the server from data/<ZONE>.lua, once, for every player: vanilla models in the main
-- world become buildings, everything else an object (shared/logic/placement.lua), and the RemoveBuildingForPlayer lines
-- become removeWorldModel. Built here rather than on each client so the server's collision companion (lib sageom.lua)
-- sees the same world players stand in. SA-MP and port models exist only on clients: they are stand-ins
-- (lib standins.lua) that each client swaps for its own model (client/main.lua). Movable props and swing doors stay
-- unfrozen: MTA does not sync objects' physics, so each client pushes and swings its own copy, as before.
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local standins = loadstring(exports.lib:getModule("standins"), "=lib/standins.lua")()

local function readLua(path)
    local f = fileOpen(path, true)
    if not f then
        return nil
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=maps/" .. path))()
end

local placement = readLua("shared/logic/placement.lua")
local stats =
    { buildings = 0, adopted = 0, objects = 0, standins = 0, glazed = 0, doors = 0, removals = 0, failed = 0, ms = 0 }
local removed = {} -- removeWorldModel rows applied, restored on stop
-- Server buildings outlive their resource (MTA 1.6.0-9.24159 hands them to root when it stops), and destroying them
-- by hand costs ~3 ms each with the map loaded (destroyElement slows with the element count: 30 s for this map). So a
-- restart takes over the buildings its last run left at root instead: each carries its row's key in server-only
-- element data (the server cannot read a building's model or rotation back: getElementModel returns false).
local ROW_KEY = "maps.row"
local leftovers = {} -- row key -> buildings at root left by the last run

local function rowKey(o)
    return ("%d:%.2f:%.2f:%.2f:%.1f:%.1f:%.1f"):format(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
end

-- the buildings the last run left at root, by row key; returns how many could not be matched to a row (no key)
local function collectLeftovers()
    local stray = 0
    for _, b in ipairs(getElementsByType("building")) do
        if getElementParent(b) == root then
            local key = getElementData(b, ROW_KEY)
            if key then
                leftovers[key] = leftovers[key] or {}
                table.insert(leftovers[key], b)
            else
                stray = stray + 1
            end
        end
    end
    return stray
end

local function building(o)
    local key = rowKey(o)
    local list = leftovers[key]
    local b = list and table.remove(list)
    if b then
        stats.adopted = stats.adopted + 1
        return b
    end
    b = createBuilding(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
    if b then
        setElementData(b, ROW_KEY, key, false)
    end
    return b
end

local function place(o)
    local custom = placement.isSampModel(o[1])
    local kind = placement.kind(o, custom or nil)
    local e
    if kind == "building" then
        e = building(o)
    elseif custom then
        -- frozen until the client has its model in place: a swing door is let go there (client/main.lua)
        e = standins.create(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
    else
        e = createObject(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
        if e and not (placement.isSwingDoor(o[1]) or placement.isMovable(o[1])) then
            setElementFrozen(e, true)
        end
    end
    if not e then
        stats.failed = stats.failed + 1
        return
    end
    if kind ~= "building" then
        local dim, int = placement.where(o[8], o[9])
        setElementDimension(e, dim)
        setElementInterior(e, int)
        if placement.isBreakable(o[1]) then
            setObjectBreakable(e, true)
        end
    end
    if kind == "building" then
        stats.buildings = stats.buildings + 1
    else
        stats.objects = stats.objects + 1
        stats.standins = stats.standins + (custom and 1 or 0)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    local started = getTickCount()
    local index = readLua("data/index.lua") or {}
    local zones = {}
    for zone in pairs(index) do
        zones[#zones + 1] = zone
    end
    table.sort(zones)
    local rows = {}
    for _, zone in ipairs(zones) do
        local data = readLua("data/" .. zone .. ".lua")
        if data then
            for _, r in ipairs(data.removals or {}) do
                -- MTA argument order: model, radius, x, y, z (SA-MP: model, x, y, z, radius)
                if removeWorldModel(r[1], r[5], r[2], r[3], r[4]) then
                    removed[#removed + 1] = r
                end
            end
            for _, o in ipairs(data.objects or {}) do
                rows[#rows + 1] = o
            end
        end
    end
    stats.removals = #removed
    -- the house shells glaze their own windows: upstream's panes in those openings would double the glass
    -- (a shell stretched to a deeper plot takes its base shell's openings and doors, the doors moved with the walls)
    local stretched = readLua("shared/stretched_shells.lua") or {}
    local glazed = placement.stretchShells(readLua("shared/glazed_windows.lua") or {}, stretched)
    rows, stats.glazed = placement.dropGlazedPanes(rows, glazed)
    -- and hang doors cut to their entrances, in place of upstream's oversized ones and where it left none
    local doors = placement.stretchShells(readLua("shared/shell_doors.lua") or {}, stretched, 6)
    local swapped, added
    rows, swapped, added = placement.fitShellDoors(rows, doors)
    stats.doors = swapped + added
    local stray = collectLeftovers()
    if stray > 0 then
        util.log("maps", "warn", "%d buildings at root carry no row key: not ours, left alone", stray)
    end
    for _, o in ipairs(rows) do
        place(o)
    end
    -- what the last run built and this one no longer does (only this resource builds on the server)
    for _, list in pairs(leftovers) do
        for _, left in ipairs(list) do
            destroyElement(left)
        end
    end
    leftovers = {}
    stats.ms = getTickCount() - started
    util.log(
        "maps",
        stats.failed > 0 and "warn" or "info",
        "%d buildings (%d kept from the last run), %d objects (%d stand-ins), %d failed, %d removals in %d ms",
        stats.buildings,
        stats.adopted,
        stats.objects,
        stats.standins,
        stats.failed,
        stats.removals,
        stats.ms
    )
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[5], r[2], r[3], r[4])
    end
    removed = {}
end)

function getMapStats()
    return stats
end
