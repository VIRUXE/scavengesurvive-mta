-- Builds upstream's static maps on the server from data/<ZONE>.lua, once, for every player: vanilla models in the main
-- world become buildings, everything else an object (shared/logic/placement.lua), and the RemoveBuildingForPlayer lines
-- become removeWorldModel. Built here rather than on each client so the server's collision companion (lib sageom.lua)
-- sees the same world players stand in. SA-MP and port models exist only on clients: they are stand-ins
-- (lib standins.lua) that each client swaps for its own model (client/main.lua). Movable props and swing doors stay
-- unfrozen: MTA does not sync objects' physics, so each client pushes and swings its own copy, as before.
-- Needs the patched server deathmatch module (docs/runbooks/patched-mta-server.md): the published 1.6.0 builds never
-- send buildings to joining players, leave them behind when this resource stops, and cannot read their model or
-- rotation back (getElementModel/getElementRotation), all of which this file relies on.
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local standins = loadstring(exports.lib:getModule("standins"), "=lib/standins.lua")()
local sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()

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
local stats = { buildings = 0, objects = 0, standins = 0, glazed = 0, doors = 0, removals = 0, failed = 0, ms = 0 }
local removed = {} -- removeWorldModel rows applied, restored on stop

local function place(o)
    local custom = placement.isSampModel(o[1])
    local kind = placement.kind(o, custom or nil)
    local e
    if kind == "building" then
        e = createBuilding(o[1], o[2], o[3], o[4], o[5], o[6], o[7])
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
    for _, o in ipairs(rows) do
        place(o)
    end
    stats.ms = getTickCount() - started
    util.log(
        "maps",
        stats.failed > 0 and "warn" or "info",
        "%d buildings, %d objects (%d stand-ins), %d failed, %d removals in %d ms",
        stats.buildings,
        stats.objects,
        stats.standins,
        stats.failed,
        stats.removals,
        stats.ms
    )
end)

-- sageom started after the maps were built: its hooks never saw createBuilding or removeWorldModel. Its start scan
-- skips buildings whose createBuilding call it did not see (sa-geom 7b1c6a8 does not read their model and rotation
-- back), so each building's is handed over, and the removals are made again for its hooks to see.
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "sageom" then
        return
    end
    local n = 0
    for _, b in ipairs(getElementsByType("building", resourceRoot)) do
        local rx, ry, rz = getElementRotation(b)
        if sageom.call("setBuildingTransform", b, getElementModel(b), rx, ry, rz) then
            n = n + 1
        end
    end
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[5], r[2], r[3], r[4])
        removeWorldModel(r[1], r[5], r[2], r[3], r[4])
    end
    util.log("maps", "info", "sageom started: %d buildings and %d removals handed over", n, #removed)
end)

-- The removals above reach each client, which takes the building out but can leave its LOD standing: the driving
-- school sheds' LODs (11371, 11372) still stood at -2028,-111 and -2076,-108 once the server built the maps, gone as
-- soon as the client made the same removeWorldModel calls itself. So each client makes them too (client/main.lua).
net.handler("mapRemovalsRequested", function(player)
    triggerClientEvent(player, "mapRemovalsSent", resourceRoot, removed)
end, { rate = 2 })

addEventHandler("onResourceStop", resourceRoot, function()
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[5], r[2], r[3], r[4])
    end
    removed = {}
end)

function getMapStats()
    return stats
end
