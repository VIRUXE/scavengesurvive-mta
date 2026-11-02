-- luacheck: globals createStove setStoveBurner setStoveBurners getStoveBurner destroyStove
local stoves = {}
local STATE = "stove:burners"

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function level(value)
    return finite(value) and value >= 0 and value <= 1
end

function createStove(x, y, z, rz, interior, dimension)
    if not finite(x) or not finite(y) or not finite(z) or not finite(rz or 0) then
        return false
    end
    interior, dimension = interior or 0, dimension or 0
    if
        not finite(interior)
        or interior % 1 ~= 0
        or interior < 0
        or interior > 255
        or not finite(dimension)
        or dimension % 1 ~= 0
        or dimension < 0
        or dimension > 65535
    then
        return false
    end
    local object = createObject(2417, x, y, z, 0, 0, rz or 0)
    if not object then
        return false
    end
    setElementInterior(object, interior)
    setElementDimension(object, dimension)
    setElementFrozen(object, true)
    stoves[object] = { 0, 0, 0, 0 }
    if not setElementData(object, STATE, stoves[object], "broadcast", "deny") then
        stoves[object] = nil
        destroyElement(object)
        return false
    end
    return object
end

function setStoveBurners(object, values)
    if not stoves[object] or type(values) ~= "table" then
        return false
    end
    local nextState = {}
    for i = 1, 4 do
        if not level(values[i]) then
            return false
        end
        nextState[i] = values[i]
    end
    if not setElementData(object, STATE, nextState, "broadcast", "deny") then
        return false
    end
    stoves[object] = nextState
    return true
end

function setStoveBurner(object, burner, intensity)
    if
        not stoves[object]
        or not finite(burner)
        or burner % 1 ~= 0
        or burner < 1
        or burner > 4
        or not level(intensity)
    then
        return false
    end
    local current = stoves[object]
    local values = { current[1], current[2], current[3], current[4] }
    values[burner] = intensity
    return setStoveBurners(object, values)
end

function getStoveBurner(object, burner)
    if not stoves[object] or not finite(burner) or burner % 1 ~= 0 or burner < 1 or burner > 4 then
        return false
    end
    return stoves[object][burner]
end

function destroyStove(object)
    return stoves[object] ~= nil and destroyElement(object)
end

addEventHandler("onElementDestroy", root, function()
    stoves[source] = nil
end)
