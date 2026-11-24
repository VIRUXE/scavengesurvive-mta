-- luacheck: read globals setVehicleComponentRotation

local YOSEMITE, TRUNK_DOOR = 554, 1
local tailgates = {} -- streamed Yosemite -> whether its pose needs updating when shut

local function track(vehicle)
    if getElementType(vehicle) == "vehicle" and getElementModel(vehicle) == YOSEMITE then
        tailgates[vehicle] = true
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        track(vehicle)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    track(source)
end)

for _, event in ipairs({ "onClientElementStreamOut", "onClientElementDestroy" }) do
    addEventHandler(event, root, function()
        tailgates[source] = nil
    end)
end

addEventHandler("onClientPreRender", root, function()
    for vehicle, needsReset in pairs(tailgates) do
        if getVehicleDoorState(vehicle, TRUNK_DOOR) ~= 4 then -- the tailgate is still attached
            local ratio = getVehicleDoorOpenRatio(vehicle, TRUNK_DOOR)
            if ratio > 0 or needsReset then
                -- GTA swings this bottom-hinged boot into the bed. Keep its synced door ratio
                -- and turn the original hinge outward until the gate lies flat.
                setVehicleComponentRotation(vehicle, "boot_dummy", -90 * ratio, 0, 0)
                tailgates[vehicle] = ratio > 0
            end
        end
    end
end)
