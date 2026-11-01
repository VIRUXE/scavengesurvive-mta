-- The two propane tanks on the towable Airstream's A-frame are frames of their own in the model (gas_l, gas_r,
-- tools/trailer_shells/towable.py): each shows only while a Gas Bottle stands on that mount. The server publishes which
-- mounts are filled as the element data "vehicles.gasBottles" ("l", "r", "lr" or "", vehicles/server/gasbottles.lua);
-- a vehicle without it is not drawn on here.
local KEY = "vehicles.gasBottles"

local function dress(vehicle)
    local filled = isElement(vehicle) and getElementData(vehicle, KEY)
    if type(filled) ~= "string" then
        return
    end
    setVehicleComponentVisible(vehicle, "gas_l", filled:find("l", 1, true) ~= nil)
    setVehicleComponentVisible(vehicle, "gas_r", filled:find("r", 1, true) ~= nil)
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        dress(source)
    end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == KEY and getElementType(source) == "vehicle" then
        dress(source)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        dress(vehicle)
    end
end)
