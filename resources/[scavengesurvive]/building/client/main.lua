-- Client-side building interactions and door swing synchronisation.
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=building/" .. path))()
end

loadModule("client/keypad.lua")
loadModule("client/tweak.lua")
