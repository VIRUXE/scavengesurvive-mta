-- Loads resources/[scavengesurvive]/lib/modules/<name>.lua exactly like a resource would (loadstring of the source).
return function(name)
    local path = "resources/[scavengesurvive]/lib/modules/" .. name .. ".lua"
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return assert(loadstring(src, "=lib/" .. name .. ".lua"))()
end
