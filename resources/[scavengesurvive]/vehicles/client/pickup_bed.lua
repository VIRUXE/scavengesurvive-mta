local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
local objects = {}
local beds = {
    [422] = { width = 1.35, depth = 1.65, rear = -2.12, floor = 0.03 }, -- Bobcat
    [543] = { width = 1.45, depth = 1.8, rear = -2.35, floor = 0.05 }, -- Sadler
}

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
    return cx, cy, cz - height / 2, width, depth
end

local function draw(vehicle)
    clear(vehicle)
    if getElementType(vehicle) ~= "vehicle" or not isElementStreamedIn(vehicle) then return end
    local bed = beds[getElementModel(vehicle)]
    if not bed then return end
    local load = getElementData(vehicle, "vehicles.bedLoad")
    if type(load) ~= "string" then return end
    local items = split(load, ",")
    local columns = math.ceil(math.sqrt(#items * bed.width / bed.depth))
    local rows = math.ceil(#items / columns)
    local width, depth = bed.width / columns, bed.depth / rows
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
            local rz = (t and t.rotz or 0) + ((i * 37) % 31 - 15)
            local cx, cy, bottom, spanX, spanY = posedBounds(object, rx, ry, rz)
            local scale = math.min(1, width * 0.94 / math.max(0.01, spanX),
                depth * 0.94 / math.max(0.01, spanY))
            setObjectScale(object, scale)
            local x = -bed.width / 2 + ((i - 1) % columns + 0.5) * width
            local y = bed.rear + (math.floor((i - 1) / columns) + 0.5) * depth
            attachElements(object, vehicle, x - cx * scale, y - cy * scale,
                bed.floor - bottom * scale, rx, ry, rz)
        end
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
