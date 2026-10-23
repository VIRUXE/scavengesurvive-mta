-- Supply drop visuals: a smoke trail on the falling crate and a smoke marker where it landed (upstream used the
-- SA-MP-only smoke object 18728, which is not in the model pack; MTA's built-in effect replaces it).
local function effectFor(ms, x, y, z)
    local fx = createEffect("smoke_flare", x, y, z)
    if not fx then
        return nil
    end
    setTimer(function(e)
        if isElement(e) then
            destroyElement(e)
        end
    end, ms, 1, fx)
    return fx
end

addEventHandler("supplyDropStarted", root, function(obj, x, y)
    if not isElement(obj) then
        return
    end
    local _, _, z = getElementPosition(obj)
    local fx = effectFor(10 * 60 * 1000, x, y, z + 1.5)
    if fx then
        attachElements(fx, obj, 0, 0, 1.5)
        addEventHandler("onClientElementDestroy", obj, function()
            if isElement(fx) then
                destroyElement(fx)
            end
        end)
    end
end)

addEventHandler("supplyCrateLanded", root, function(x, y, z)
    effectFor(3 * 60 * 1000, x, y, z + 0.5)
end)
