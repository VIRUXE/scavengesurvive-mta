-- Serves the source of a module in modules/ to other resources, on the server and on clients: local m =
-- loadstring(exports.lib:getModule("name"), "=lib/name.lua")(). Only the modules clients use are <file> entries in
-- meta.xml (every <file> is served to anyone over the download URL, download="false" included); the server-only ones
-- are left out of meta.xml, the server still reads them from disk, and on a client getModule returns false for them.
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
