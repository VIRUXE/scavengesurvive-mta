local cached, cachedHeld, checkedAt
return function(held, force)
    local uname = held and held.uname or false
    local now = getTickCount()
    if not force and cached and cachedHeld == uname and now - checkedAt < 150 then
        return cached
    end
    local actions = {}
    if
        getPedOccupiedVehicle(localPlayer)
        or isPedDead(localPlayer)
        or getElementData(localPlayer, "character.knockedOut") == true
    then
        return actions
    end
    local feature = exports.world:nearbyFeature()
    if feature == "ladder_on" or feature == "zipline_on" then
        return actions
    end
    for _, provider in ipairs({ "items", "vehicles", "world", "loot", "dumpsters" }) do
        local resource = getResourceFromName(provider)
        if resource and getResourceState(resource) == "running" and (provider ~= "items" or not held) then
            local entries = call(resource, "interactionActions", uname)
            for _, entry in ipairs(type(entries) == "table" and entries or {}) do
                actions[#actions + 1] = entry
            end
        end
    end
    cached, cachedHeld, checkedAt = actions, uname, now
    return actions
end
