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
