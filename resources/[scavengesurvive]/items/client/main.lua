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
local geometry = loadModule("shared/logic/geometry.lua")
local cooking = loadModule("shared/logic/cooking.lua")
local worldCtx = { models = models, ammo = ammo, tent = tent, clothes = clothes, geometry = geometry }
worldCtx.cooking = cooking
local world = loadModule("client/world.lua")(worldCtx)
local attach = loadModule("client/attach.lua")({ models = models, apparel = apparel })
local preview = loadModule("client/preview.lua")({ logic = loadModule("shared/logic/preview.lua") })
local inventoryCtx = { ammo = ammo, apparel = apparel, clothes = clothes, models = models, preview = preview }
inventoryCtx.cooking = cooking
loadModule("client/inventory.lua")(inventoryCtx)

-- client exports for the attachedit resource: preview offsets on the local player's own attachments
function setAttachPreview(slot, offsets, scale)
    return attach.setPreview(slot, offsets, scale)
end

-- client export for the hud: "Campfire" / "Barbecue" when one is within the pickup reach (2 m), else false
function nearbyCooker()
    return world.nearbyCooker(2.0) or false
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

-- treatments (server/medical.lua): the healer holds the interact key, letting go cancels; the patient sees the bar
local treatmentTimer = nil
addEventHandler("treatmentStarted", localPlayer, function(durationMs, healer)
    exports.ui:progressStart(healer and "Treating" or "Being treated", durationMs)
    if isTimer(treatmentTimer) then
        killTimer(treatmentTimer)
    end
    if not healer then
        return
    end
    local key = string.lower(getKeyBoundToCommand("interact") or "f")
    treatmentTimer = setTimer(function()
        if not getKeyState(key) then
            killTimer(treatmentTimer)
            triggerServerEvent("treatmentCancelRequested", localPlayer)
        end
    end, 100, 0)
end)

addEventHandler("treatmentStopped", localPlayer, function()
    exports.ui:progressCancel()
    if isTimer(treatmentTimer) then
        killTimer(treatmentTimer)
    end
end)
