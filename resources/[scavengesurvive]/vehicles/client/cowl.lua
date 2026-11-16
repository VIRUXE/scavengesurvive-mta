-- Engine covers on the client. The Maverick (487) is replaced by files/maverick.dff (tools/build_maverick_cowl.py),
-- whose cowl doors are frames of their own (vlogic.COWLS): the server keeps a cowl open or shut in vehicles.cowl and
-- each client turns the doors of the Mavericks it has streamed in. The exports answer, for any vehicle, what lies
-- over its engine (vehicles.cover), whether the engine can be reached and whether a spot is at the engine.
local vlogic
do
    local f = fileOpen("shared/logic/vehicle.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    vlogic = assert(loadstring(src, "=vehicles/vehicle.lua"))()
end

local MODEL, FILE = 487, "files/maverick"
local SWING_MS = 700
local keep = {} -- loaded TXD and DFF elements
local share = {} -- vehicle -> how far its doors stand open, 0 (shut) to 1
local swing = {} -- vehicle -> { from, to, start }: doors on their way
local swinging = false

local function wantOpen(vehicle)
    return getElementData(vehicle, "vehicles.cowl") == true
end

local function pose(vehicle, s)
    local cowl = vlogic.COWLS[getElementModel(vehicle)]
    if not cowl then
        return
    end
    for frame, side in pairs(cowl.frames) do
        setVehicleComponentRotation(vehicle, frame, 0, side * cowl.openDeg * s, 0)
    end
    share[vehicle] = s
end

local function step()
    local now = getTickCount()
    for vehicle, w in pairs(swing) do
        if not isElement(vehicle) or not isElementStreamedIn(vehicle) then
            swing[vehicle] = nil
        else
            local t = math.min(1, (now - w.start) / SWING_MS)
            pose(vehicle, w.from + (w.to - w.from) * getEasingValue(t, "InOutQuad"))
            if t >= 1 then
                swing[vehicle] = nil
            end
        end
    end
    if not next(swing) then
        swinging = false
        removeEventHandler("onClientPreRender", root, step)
    end
end

local function settle(vehicle)
    if getElementType(vehicle) == "vehicle" and vlogic.COWLS[getElementModel(vehicle)] then
        swing[vehicle] = nil
        pose(vehicle, wantOpen(vehicle) and 1 or 0)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local txd = engineLoadTXD(FILE .. ".txd", true)
    local dff = txd and engineImportTXD(txd, MODEL) and engineLoadDFF(FILE .. ".dff")
    if not dff or not engineReplaceModel(dff, MODEL) then
        return outputDebugString("vehicles: failed to load the Maverick with its cowl (model " .. MODEL .. ")", 1)
    end
    keep[#keep + 1], keep[#keep + 2] = txd, dff
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        settle(vehicle)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    settle(source)
end)

addEventHandler("onClientElementStreamOut", root, function()
    share[source], swing[source] = nil, nil
end)

addEventHandler("onClientElementDestroy", root, function()
    share[source], swing[source] = nil, nil
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key ~= "vehicles.cowl" or getElementType(source) ~= "vehicle" or not isElementStreamedIn(source) then
        return
    end
    if not vlogic.COWLS[getElementModel(source)] then
        return
    end
    swing[source] = { from = share[source] or 0, to = wantOpen(source) and 1 or 0, start = getTickCount() }
    if not swinging then
        swinging = true
        addEventHandler("onClientPreRender", root, step)
    end
end)

-- export: what lies over the vehicle's engine: "bonnet", "cowl", or nil for nothing (an aircraft without a cowl)
function engineCoverKind(vehicle)
    if not isElement(vehicle) then
        return nil
    end
    local kind = getElementData(vehicle, "vehicles.cover")
    if kind == nil then
        return "bonnet"
    end
    return kind or nil
end

-- export: the cover can be neither opened nor shut: there is none, or the bonnet has been taken off
function engineCoverFixed(vehicle)
    local kind = engineCoverKind(vehicle)
    return kind == nil or (kind == "bonnet" and getVehicleDoorState(vehicle, 0) == 4)
end

-- export: the engine can be reached: no cover, the bonnet open or off, the cowl open
function engineReachable(vehicle)
    local kind = engineCoverKind(vehicle)
    if kind == nil then
        return isElement(vehicle)
    end
    if kind == "cowl" then
        return wantOpen(vehicle)
    end
    return getVehicleDoorState(vehicle, 0) == 4 or getVehicleDoorOpenRatio(vehicle, 0) > 0.5
end

-- export: (px, py) is at the vehicle's engine: beside its cowl, else in its front cone
function atEngine(vehicle, px, py)
    if not isElement(vehicle) then
        return false
    end
    local vx, vy = getElementPosition(vehicle)
    local _, _, vrz = getElementRotation(vehicle)
    return vlogic.atEngine(getElementModel(vehicle), px, py, vx, vy, vrz)
end
