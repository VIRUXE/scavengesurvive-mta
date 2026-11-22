-- Content identity comes from decoded TXD pixels. Only the shared tyre is global;
-- even generic rim/atlas names are bound to the vehicle element that owns them.
local data
do
    local file = assert(fileOpen("shared/data/wheel_hd.lua", true))
    local text = fileRead(file, fileGetSize(file))
    fileClose(file)
    data = assert(loadstring(text, "=vehicles/wheel_hd-data.lua"))()
end

local assets = {} -- content id -> one texture and one immutable shader, shared by all vehicles
local tracked = {} -- vehicle -> current wheel upgrade and texture-name bindings
local ready = false

local function asset(id)
    if assets[id] ~= nil then
        return assets[id]
    end
    local def = data.assets[id]
    local texture = dxCreateTexture(def.file, def.format, true, def.cropped and "clamp" or "wrap")
    local shader = texture
        and dxCreateShader(def.cropped and "client/wheel_hd_crop.fx" or "client/wheel_hd.fx", 0, 0, false, "vehicle")
    local ok = shader and dxSetShaderValue(shader, "WheelTexture", texture)
    if ok and def.cropped then
        ok = dxSetShaderValue(shader, "Region", unpack(def.region))
            and dxSetShaderValue(shader, "Transform", unpack(def.transform))
    end
    if not ok then
        if shader then
            destroyElement(shader)
        end
        if texture then
            destroyElement(texture)
        end
        assets[id] = false
        outputDebugString("vehicles: failed to load HD wheel material " .. id, 1)
        return false
    end
    assets[id] = { texture = texture, shader = shader }
    return assets[id]
end

local function detach(vehicle)
    local state = tracked[vehicle]
    if not state then
        return
    end
    for name, id in pairs(state.bindings) do
        engineRemoveShaderFromWorldTexture(assets[id].shader, name, vehicle)
    end
    tracked[vehicle] = nil
end

local function refresh(vehicle)
    if not ready or getElementType(vehicle) ~= "vehicle" then
        return
    end
    detach(vehicle)
    if not isElementStreamedIn(vehicle) then
        return
    end
    local model = getElementModel(vehicle)
    local own = data.models[model]
    if not own then
        return
    end
    local upgrade = getVehicleUpgradeOnSlot(vehicle, 12)
    local wanted = {}
    for name, id in pairs(own) do
        wanted[name] = id
    end
    for name, id in pairs(data.models[upgrade] or {}) do
        wanted[name] = id
    end
    local state = { upgrade = upgrade, bindings = {} }
    tracked[vehicle] = state
    for name, id in pairs(wanted) do
        local shared = asset(id)
        if shared then
            if engineApplyShaderToWorldTexture(shared.shader, name, vehicle) then
                state.bindings[name] = id
            else
                outputDebugString("vehicles: failed to bind HD wheel material " .. name, 1)
            end
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    ready = true
    local tyre = asset(data.tyre)
    if tyre and not engineApplyShaderToWorldTexture(tyre.shader, "vehicletyres128") then
        outputDebugString("vehicles: failed to bind shared HD tyre", 1)
    end
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        refresh(vehicle)
    end
    -- MTA has no client upgrade-change event. Only poll streamed vehicles, once a
    -- second, and touch bindings only when slot 12 changes (including removal).
    setTimer(function()
        for vehicle, state in pairs(tracked) do
            if getVehicleUpgradeOnSlot(vehicle, 12) ~= state.upgrade then
                refresh(vehicle)
            end
        end
    end, 1000, 0)
end)

addEventHandler("onClientElementStreamIn", root, function()
    refresh(source)
end)

addEventHandler("onClientElementModelChange", root, function()
    refresh(source)
end)

addEventHandler("onClientElementStreamOut", root, function()
    detach(source)
end)

addEventHandler("onClientElementDestroy", root, function()
    detach(source)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ready = false
    for vehicle in pairs(tracked) do
        detach(vehicle)
    end
    local tyre = assets[data.tyre]
    if tyre then
        engineRemoveShaderFromWorldTexture(tyre.shader, "vehicletyres128")
    end
    for _, shared in pairs(assets) do
        if shared then
            destroyElement(shared.shader)
            destroyElement(shared.texture)
        end
    end
end)
