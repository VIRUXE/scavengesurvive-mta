-- A model pack's own files, read by the pack for others: a resource may read only its own files, so the pack that
-- holds a model hands out its .dff (loot rests items by the shape of their mesh, loot/shared/logic/settle.lua).
-- Server only: local modelpack = loadstring(exports.lib:getModule("modelpack"), "=lib/modelpack.lua")()

-- dffReader(manifests): for this resource's manifests (lua files returning { [id] = { dff = "name", ... } }, files in
-- files/<dff>.dff) a function (model id) -> the file's bytes, false for a model that is not the pack's.
local function dffReader(manifests)
    local files
    return function(id)
        if not files then
            files = {}
            for _, name in ipairs(manifests) do
                local f = fileExists(name) and fileOpen(name, true)
                local list = f and assert(loadstring(fileRead(f, fileGetSize(f)), "=" .. name))()
                if f then
                    fileClose(f)
                end
                for model, e in pairs(list or {}) do
                    if type(e) == "table" and e.dff and not files[model] then
                        files[model] = "files/" .. e.dff .. ".dff"
                    end
                end
            end
        end
        local path = files[tonumber(id)]
        local f = path and fileExists(path) and fileOpen(path, true)
        if not f then
            return false
        end
        local bytes = fileRead(f, fileGetSize(f))
        fileClose(f)
        return bytes
    end
end

return { dffReader = dffReader }
