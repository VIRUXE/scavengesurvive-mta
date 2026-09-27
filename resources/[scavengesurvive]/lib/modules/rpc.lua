local rpc = {}
function rpc.call(resourceName, fnName, ...)
    local res = getResourceFromName(resourceName)
    if not res or getResourceState(res) ~= "running" then
        return false, "down"
    end
    return true, call(res, fnName, ...)
end
return rpc
