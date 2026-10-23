-- Client entry: the item model resolver is shared by the world objects and the bone attachments; the inventory
-- list is UI only. The modules are read from the downloaded files in the order the <script> lines used to have.
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=items/" .. path))()
end
local ammo = loadModule("shared/logic/ammo.lua")
local tent = loadModule("shared/logic/tent.lua")
local apparel = loadModule("shared/logic/apparel.lua")
apparel.skins = loadModule("shared/logic/skins.lua")
local clothes = loadModule("shared/logic/clothes.lua")
local models = loadModule("client/models.lua")()
loadModule("client/world.lua")({ models = models, ammo = ammo, tent = tent, clothes = clothes })
local attach = loadModule("client/attach.lua")({ models = models, apparel = apparel })
local preview = loadModule("client/preview.lua")({ logic = loadModule("shared/logic/preview.lua") })
local inventoryCtx = { ammo = ammo, apparel = apparel, clothes = clothes, models = models, preview = preview }
loadModule("client/inventory.lua")(inventoryCtx)

-- client exports for the attachedit resource: preview offsets on the local player's own attachments
function setAttachPreview(slot, offsets, scale)
    return attach.setPreview(slot, offsets, scale)
end

function getAttachConfig(slot)
    return attach.getConfig(slot)
end

-- changing clothes (server/clothes.lua): the server times the hold and cancels it, the client only draws the bar
addEventHandler("clothesChangeStarted", localPlayer, function(durationMs)
    exports.ui:progressStart("Changing clothes", durationMs)
end)

addEventHandler("clothesChangeStopped", localPlayer, function()
    exports.ui:progressCancel()
end)
