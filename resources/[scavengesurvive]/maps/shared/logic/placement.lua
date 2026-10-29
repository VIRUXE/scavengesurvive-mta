-- How one upstream map object is placed on a client. Pure logic; the client passes the resolved SA-MP model id.
-- Object rows are { model, x, y, z, rx, ry, rz, world, interior, range } (tools/convert/maps.py).
local placement = {}
placement.BUILDING_LIMIT = 3000 -- createBuilding rejects |x| or |y| beyond this (the ocean rigs are objects)
placement.OBJECT_MODEL_MAX = 397 -- default.ide models (weapons etc.): createBuilding rejects part of this range
placement.FRAME_BUDGET_MS = 5 -- build time spent per frame while the world is being created
-- GTA:SA object.dat 6:SWINGDOOR models (dynamic2.ide Gen_doorINT01..05, Gen_doorEXT10): createBuilding makes them
-- rigid walls, and setElementFrozen locks their hinge, so they must be unfrozen CObjects to swing open.
placement.SWING_DOORS = {
    [1491] = true,
    [1492] = true,
    [1494] = true,
    [1499] = true,
    [1502] = true,
    [1523] = true,
}

-- Wire fence panels of the roadblocks: createBuilding cannot break, so they are objects with setObjectBreakable.
placement.BREAKABLE = {
    [1651] = true,
}

function placement.isSampModel(model)
    return model >= 18631 or (model >= 11682 and model <= 11753)
end

function placement.isSwingDoor(model)
    return placement.SWING_DOORS[model] == true
end

function placement.isBreakable(model)
    return placement.BREAKABLE[model] == true
end

-- SA-MP virtual world / interior (-1 = any) -> MTA dimension / interior
function placement.where(world, interior)
    local dim = (world and world > 0) and world or 0
    local int = (interior and interior > 0) and interior or 0
    return dim, int
end

-- "building" (static, cheapest), "object" (dimensioned, interior, far away, default.ide or SA-MP model) or
-- "skip" (SA-MP model with no loaded replacement: a stand-in would be wrong in a map, so nothing is placed)
function placement.kind(o, sampId)
    local model = o[1]
    if placement.isSampModel(model) then
        if not sampId then
            return "skip"
        end
        return "object" -- allocated ids are not vanilla models, which is all createBuilding accepts
    end
    if math.abs(o[2]) > placement.BUILDING_LIMIT or math.abs(o[3]) > placement.BUILDING_LIMIT then
        return "object"
    end
    local dim, int = placement.where(o[8], o[9])
    if dim ~= 0 or int ~= 0 then
        return "object"
    end
    if model <= placement.OBJECT_MODEL_MAX or placement.isSwingDoor(model) or placement.isBreakable(model) then
        return "object"
    end
    return "building"
end

-- counts per kind for a zone's object list; resolve(model) -> loaded id or false
function placement.tally(objects, resolve)
    local t = { building = 0, object = 0, skip = 0 }
    for _, o in ipairs(objects) do
        local k = placement.kind(o, placement.isSampModel(o[1]) and resolve(o[1]) or nil)
        t[k] = t[k] + 1
    end
    return t
end

return placement
