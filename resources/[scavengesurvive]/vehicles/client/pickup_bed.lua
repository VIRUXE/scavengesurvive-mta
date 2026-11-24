local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local objects = {}

local function clear(vehicle)
    for _, object in ipairs(objects[vehicle] or {}) do
        if isElement(object) then destroyElement(object) end
    end
    objects[vehicle] = nil
end

-- Project the model bounds onto the bed axes after applying its rest pose.
local function posedBounds(object, rx, ry, rz)
    -- Object rotations use ZXY order. Compute axes even before the prop streams in.
    rx, ry, rz = math.rad(rx), math.rad(ry), math.rad(rz)
    local sx, sy, sz = math.sin(rx), math.sin(ry), math.sin(rz)
    local cx, cy, cz = math.cos(rx), math.cos(ry), math.cos(rz)
    local m = {
        { cy * cz - sx * sy * sz, cy * sz + sx * sy * cz, -cx * sy },
        { -cx * sz, cx * cz, sx },
        { sy * cz + sx * cy * sz, sy * sz - sx * cy * cz, cx * cy },
    }
    local ax, ay, az, bx, by, bz = getElementBoundingBox(object)
    if not ax then ax, ay, az, bx, by, bz = -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 end
    local function extent(axis)
        local x, y, z = m[1][axis], m[2][axis], m[3][axis]
        local center = ((ax + bx) * x + (ay + by) * y + (az + bz) * z) / 2
        local span = math.abs((bx - ax) * x) + math.abs((by - ay) * y) + math.abs((bz - az) * z)
        return center, span
    end
    local cx, width = extent(1)
    local cy, depth = extent(2)
    local cz, height = extent(3)
    return cx, cy, cz - height / 2, width, depth, height
end

-- Each rectangle is free space on the floor or on a previously placed prop.
local function placeCargo(spaces, prop, random)
    local best, scale
    for i, area in ipairs(spaces) do
        local fit = math.min(1, area.w / prop.w, area.d / prop.d)
        if not best or fit > scale or (fit == scale and area.z < spaces[best].z) then
            best, scale = i, fit
        end
    end
    local area = table.remove(spaces, best)
    local w, d = prop.w * scale, prop.d * scale
    local dx = random() * math.max(0, area.w - w)
    local dy = random() * math.max(0, area.d - d)
    local x, y = area.x + dx, area.y + dy
    local function add(left, rear, width, depth, z)
        if width > 0.001 and depth > 0.001 then
            spaces[#spaces + 1] = { x = left, y = rear, w = width, d = depth, z = z }
        end
    end
    add(area.x, area.y, dx, area.d, area.z)
    add(x + w, area.y, area.w - dx - w, area.d, area.z)
    add(x, area.y, w, dy, area.z)
    add(x, y + d, w, area.d - dy - d, area.z)
    add(x, y, w, d, area.z + prop.height * scale)
    return x + w / 2, y + d / 2, area.z, scale
end

local function draw(vehicle)
    clear(vehicle)
    if getElementType(vehicle) ~= "vehicle" or not isElementStreamedIn(vehicle) then return end
    local bed = pickupBeds[getElementModel(vehicle)]
    if not bed then return end
    local load = getElementData(vehicle, "vehicles.bedLoad")
    if type(load) ~= "string" then return end
    local items = split(load, ",")
    local seed = tonumber(getElementData(vehicle, "vehicles.id")) or 1
    local function random()
        seed = (seed * 48271) % 2147483647
        return seed / 2147483647
    end
    local cargo = {}
    objects[vehicle] = {}
    for i, uname in ipairs(items) do
        local t = exports.data:itemType(uname)
        local model = t and (models.resolve(t.model) or t.mtaModel or t.model)
        local object = (model and createObject(model, 0, 0, 0)) or createObject(1271, 0, 0, 0)
        if object then
            table.insert(objects[vehicle], object)
            setElementCollisionsEnabled(object, false)
            setElementDimension(object, getElementDimension(vehicle))
            setElementInterior(object, getElementInterior(vehicle))
            local rx, ry = t and t.rotx or 0, t and t.roty or 0
            local rz = (t and t.rotz or 0) + random() * 360
            local cx, cy, bottom, w, d, height = posedBounds(object, rx, ry, rz)
            cargo[#cargo + 1] = { object = object, rx = rx, ry = ry, rz = rz, cx = cx, cy = cy,
                bottom = bottom, w = math.max(w, 0.01), d = math.max(d, 0.01), height = height, index = i }
        end
    end
    table.sort(cargo, function(a, b)
        local aa, ba = a.w * a.d, b.w * b.d
        if aa == ba then return a.index < b.index end
        return aa > ba
    end)
    local spaces = { { x = -bed.width / 2, y = bed.rear, w = bed.width, d = bed.depth, z = bed.floor } }
    for _, prop in ipairs(cargo) do
        local x, y, z, scale = placeCargo(spaces, prop, random)
        setObjectScale(prop.object, scale)
        attachElements(prop.object, vehicle, x - prop.cx * scale, y - prop.cy * scale,
            z - prop.bottom * scale, prop.rx, prop.ry, prop.rz)
    end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "vehicles.bedLoad" then draw(source) end
end)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then draw(source) end
end)
for _, event in ipairs({ "onClientElementStreamOut", "onClientElementDestroy" }) do
    addEventHandler(event, root, function()
        if objects[source] then clear(source) end
    end)
end
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do draw(vehicle) end
end)
