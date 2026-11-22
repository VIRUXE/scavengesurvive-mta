-- Hands this pack's model collisions to the server's collision companion (lib sageom.lua), so server-side ground
-- and ray queries collide with the parts players see lying about.
local sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()
sageom.registerPack({ "parts.lua" })
