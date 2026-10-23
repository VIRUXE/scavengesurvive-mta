-- Client entry: the item model resolver is shared by the world objects and the bone attachments; the inventory
-- list is UI only. The modules are read from the downloaded files in the order the <script> lines used to have.
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=items/" .. path))()
end
local ammo = loadModule("shared/logic/ammo.lua")
local apparel = loadModule("shared/logic/apparel.lua")
local models = loadModule("client/models.lua")()
loadModule("client/world.lua")({ models = models, ammo = ammo })
local attach = loadModule("client/attach.lua")({ models = models, apparel = apparel })
loadModule("client/inventory.lua")({ ammo = ammo, apparel = apparel })

-- client exports for the attachedit resource: preview offsets on the local player's own attachments
function setAttachPreview(slot, offsets, scale)
    return attach.setPreview(slot, offsets, scale)
end

function getAttachConfig(slot)
    return attach.getConfig(slot)
end
