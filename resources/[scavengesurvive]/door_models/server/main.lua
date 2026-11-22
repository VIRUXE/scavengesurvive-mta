-- Hands this pack's model collisions to the server's collision companion (lib sageom.lua), so server-side ground
-- and ray queries collide with the objects players see built from these models.
local sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()
sageom.registerPack({ "doors.lua" })

-- The .dff of one of this pack's models (false for a model that is not its own): loot rests an item by the shape of
-- its mesh (loot/shared/logic/settle.lua), and a resource reads only its own files.
local readDff = loadstring(exports.lib:getModule("modelpack"), "=lib/modelpack.lua")().dffReader({ "doors.lua" })
function modelDff(id)
    return readDff(id)
end
