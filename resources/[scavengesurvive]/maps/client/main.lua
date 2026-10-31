-- Builds upstream's static maps on this client from data/<ZONE>.lua (tools/convert/maps.py): vanilla models in
-- the main world become buildings, everything else an object (see shared/logic/placement.lua), and the
-- RemoveBuildingForPlayer lines become removeWorldModel. Work is spread over frames with a time budget so the
-- join is not frozen. SA-MP-only models come from samp_models when it has them loaded.
local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local placement
do
    local f = fileOpen("shared/logic/placement.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    placement = assert(loadstring(src, "=maps/placement.lua"))()
end

local state = {
    stats = {
        buildings = 0,
        objects = 0,
        skipped = 0,
        glazed = 0,
        doors = 0,
        removals = 0,
        pending = 0,
        failed = 0,
        ms = 0,
    },
    elements = {}, -- every created element, for the stop path
    sampObjects = {}, -- { element = e, model = sampModel } to swap models when the pack (re)loads
    skippedRows = {}, -- SA-MP rows placed nowhere yet; re-queued when the pack loads
    removed = {}, -- removeWorldModel rows applied, restored on stop
}
local queue, queueIndex, started = {}, 1, 0
local building = false
local step

local function readLua(path)
    local f = fileOpen(path, true)
    if not f then
        return nil
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=maps/" .. path))()
end

local function sampModel(model)
    return models.resolve(model)
end

local function place(o)
    local samp = placement.isSampModel(o[1]) and sampModel(o[1]) or nil
    local kind = placement.kind(o, samp)
    if kind == "skip" then
        state.stats.skipped = state.stats.skipped + 1
        state.skippedRows[#state.skippedRows + 1] = o
        return
    end
    local model = samp or o[1]
    local e
    if kind == "building" then
        e = createBuilding(model, o[2], o[3], o[4], o[5], o[6], o[7])
    else
        e = createObject(model, o[2], o[3], o[4], o[5], o[6], o[7])
        if e then
            local dim, int = placement.where(o[8], o[9])
            setElementDimension(e, dim)
            setElementInterior(e, int)
            if placement.isBreakable(model) then
                setObjectBreakable(e, true)
            end
            if not placement.isSwingDoor(o[1]) then
                setElementFrozen(e, true)
            end
        end
    end
    if not e then
        state.stats.failed = state.stats.failed + 1
        return
    end
    state.elements[#state.elements + 1] = e
    if samp then
        state.sampObjects[#state.sampObjects + 1] = { element = e, model = o[1] }
    end
    if kind == "building" then
        state.stats.buildings = state.stats.buildings + 1
    else
        state.stats.objects = state.stats.objects + 1
    end
end

local function startBuilding(rows)
    queue, queueIndex, started = rows, 1, getTickCount()
    state.stats.pending = #queue
    if #queue > 0 and not building then
        building = true
        addEventHandler("onClientPreRender", root, step)
    end
end

function step()
    local deadline = getTickCount() + placement.FRAME_BUDGET_MS
    while queueIndex <= #queue and getTickCount() < deadline do
        place(queue[queueIndex])
        queueIndex = queueIndex + 1
    end
    state.stats.pending = #queue - queueIndex + 1
    if queueIndex > #queue then
        removeEventHandler("onClientPreRender", root, step)
        building = false
        state.stats.ms = getTickCount() - started
        local s = state.stats
        outputDebugString(
            ("maps: %d buildings, %d objects, %d SA-MP models skipped, %d failed, %d removals in %d ms"):format(
                s.buildings,
                s.objects,
                s.skipped,
                s.failed,
                s.removals,
                s.ms
            ),
            (s.failed > 0) and 2 or 3
        )
        triggerEvent("mapsBuilt", resourceRoot, s)
    end
end

local function removeWorld(rows)
    for _, r in ipairs(rows) do
        -- MTA argument order: model, radius, x, y, z (SA-MP: model, x, y, z, radius)
        if removeWorldModel(r[1], r[5], r[2], r[3], r[4]) then
            state.removed[#state.removed + 1] = r
            state.stats.removals = state.stats.removals + 1
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local index = readLua("data/index.lua") or {}
    local zones = {}
    for zone in pairs(index) do
        zones[#zones + 1] = zone
    end
    table.sort(zones)
    for _, zone in ipairs(zones) do
        local data = readLua("data/" .. zone .. ".lua")
        if data then
            removeWorld(data.removals or {})
            for _, o in ipairs(data.objects or {}) do
                queue[#queue + 1] = o
            end
        end
    end
    -- the house shells glaze their own windows: upstream's panes in those openings would double the glass
    local dropped
    queue, dropped = placement.dropGlazedPanes(queue, readLua("shared/glazed_windows.lua") or {})
    state.stats.glazed = dropped
    -- and hang doors cut to their entrances, in place of upstream's oversized ones and where it left none
    local swapped, added
    queue, swapped, added = placement.fitShellDoors(queue, readLua("shared/shell_doors.lua") or {})
    state.stats.doors = swapped + added
    if #state.removed > 0 then
        setOcclusionsEnabled(false) -- removed world models leave their occluders behind otherwise
    end
    -- the building pool is left to MTA, which grows it on demand: re-applying a capacity on a restart shrank a
    -- pool that was in use and crashed the client (2026-10-22)
    startBuilding(queue)
end)

-- the SA-MP model pack (re)loaded or is stopping: swap the models of the objects that use it, and place the rows
-- that were skipped because the pack was not loaded yet (the pack downloads before maps, but not always first)
addEventHandler("sampModelsChanged", root, function()
    for _, entry in ipairs(state.sampObjects) do
        if isElement(entry.element) then
            local id = sampModel(entry.model)
            if id then
                setElementModel(entry.element, id)
            end
        end
    end
    if #state.skippedRows > 0 and not building then
        local rows = state.skippedRows
        state.skippedRows, state.stats.skipped = {}, 0
        startBuilding(rows)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if building then
        removeEventHandler("onClientPreRender", root, step)
    end
    for _, r in ipairs(state.removed) do
        restoreWorldModel(r[1], r[5], r[2], r[3], r[4])
    end
    if #state.removed > 0 then
        setOcclusionsEnabled(true)
    end
    -- elements die with the resource; the tables only matter for stats
    state.elements, state.sampObjects, state.removed = {}, {}, {}
end)

function getMapStats()
    return state.stats
end
