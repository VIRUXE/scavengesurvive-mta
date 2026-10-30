-- Serves the source of a module in modules/ to other resources, on the server and on clients (the files are
-- downloaded with lib): local m = loadstring(exports.lib:getModule("name"), "=lib/name.lua")()
local cache = {}
function getModule(name)
    if cache[name] then
        return cache[name]
    end
    local path = "modules/" .. name .. ".lua"
    if not fileExists(path) then
        return false
    end
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    cache[name] = src
    return src
end
