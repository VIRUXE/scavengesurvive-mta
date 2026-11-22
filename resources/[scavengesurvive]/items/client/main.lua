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
local liquids = loadModule("shared/logic/liquids.lua")
local gas = loadModule("shared/logic/gas.lua")
local small = loadModule("shared/logic/smallitems.lua")
local gardening = loadModule("shared/logic/gardening.lua")
local machines = loadModule("shared/logic/machines.lua")
-- the logic modules' label words in the local player's language (lib lang, auth's auth.lang)
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local outline = loadstring(exports.lib:getModule("outline"), "=lib/outline.lua")()
for _, m in ipairs({ ammo, clothes, cooking, liquids, small, gardening, machines }) do
    m.tr = lang.text
end
local worldCtx = { models = models, ammo = ammo, tent = tent, clothes = clothes, geometry = geometry }
worldCtx.cooking = cooking
worldCtx.small = small
worldCtx.gardening = gardening
worldCtx.machines = machines
worldCtx.furniture = loadModule("shared/logic/furniture.lua")
worldCtx.vending = loadModule("shared/logic/vending.lua")
worldCtx.floodlight = loadModule("client/floodlight.lua")({
    flood = loadModule("shared/logic/floodlight.lua"),
    lang = lang,
})
-- the Generator's engine and the Extension Cords plugged into a building's mains (power)
worldCtx.power = loadModule("client/power.lua")({ machines = machines, lang = lang })
local world = loadModule("client/world.lua")(worldCtx)
loadModule("client/vending.lua")({ world = world, vending = worldCtx.vending })
local carry = loadModule("shared/logic/carry.lua")
local attach = loadModule("client/attach.lua")({ models = models, apparel = apparel, carry = carry })
-- Reach checks distinguish crowbar work on installed panels from loose-item pickup.
worldCtx.heldUname = function()
    local _, uname = attach.heldObject(localPlayer)
    return uname
end
local preview = loadModule("client/preview.lua")({ logic = loadModule("shared/logic/preview.lua"), models = models })
local inventoryCtx = { ammo = ammo, apparel = apparel, clothes = clothes, models = models, preview = preview }
inventoryCtx.cooking = cooking
inventoryCtx.liquids = liquids
inventoryCtx.gas = gas
inventoryCtx.small = small
inventoryCtx.gardening = gardening
loadModule("client/inventory.lua")(inventoryCtx)
loadModule("client/text.lua")(machines)
loadModule("client/combo.lua")({ models = models, lang = lang })
loadModule("client/firework.lua")(loadModule("shared/logic/firework.lua"))
loadModule("client/parachute.lua")(small)

-- client exports for the attachedit resource: preview offsets on the local player's own attachments
function setAttachPreview(slot, offsets, scale)
    return attach.setPreview(slot, offsets, scale)
end

-- client export for the hud: "Campfire" / "Barbecue" when one is within the pickup reach (2 m), else false
function nearbyCooker()
    return world.nearbyCooker(2.0) or false
end

-- client export for the hud: whether the item is a hat, mask or armour that F wears from the hand (#154)
function isHandWearable(uname)
    local slot = apparel.slotFor(uname)
    return slot == "hat" or slot == "mask" or slot == "armour"
end

function nearbyContainerItem()
    local id, category, stuck = world.nearbyContainerItem(2.0)
    return id or false, category or false, stuck or false
end

-- (nearbyContainerItem's category is "fixed" for a take-only container such as the snack machine: no hold pickup;
-- stuck is true when the container does not fit through the way to the player: it opens, the hold does not lift it)

-- client export for the hud: a Sign or a body lying within reach (a tap of F edits or investigates it, a held F
-- picks it up): its id and uname, else false
function nearbyInspectable()
    local id, uname = world.nearbyInspectable(2.0)
    return id or false, uname or false
end

-- the distance to the nearest world item, or false (world's buttons give way to a nearer item)
function nearestItemDistance()
    return world.nearestItemDistance()
end

-- the machine within reach (#145): the hud's F taps to open it and holds for its menu
-- the objects of the world items of a type on this client, { [item id] = object } (vehicles: Welders and their torch)
function worldObjectsOfType(uname)
    return world.objectsOfType(uname)
end

-- the object of the item a player holds and its type, or false
function heldObjectOf(player)
    local obj, uname = attach.heldObject(player)
    if not obj then
        return false
    end
    return obj, uname
end

-- the machine within reach: its id and type, or false
function nearbyMachine()
    local id, uname, running = world.nearbyMachine(2.0)
    return id or false, uname or false, running == true
end

-- what a Crowbar's F works on (world.crowbarTarget): id, object (or false), uname; else false
function nearbyCrowbarTarget()
    local id, obj, uname = world.crowbarTarget()
    if not id then
        return false
    end
    return id, obj, uname
end

-- a world item's object, or false
function itemObject(id)
    return world.objectOf(id)
end

-- the ids of the world items within reach that a wall hides: the hud sends them with a pickup so the server skips them
function blockedItemsNear()
    return world.blockedNear(2.0)
end

function getAttachConfig(slot)
    return attach.getConfig(slot)
end

-- changing clothes (server/clothes.lua): the server times the hold and cancels it, the client only draws the bar
addEventHandler("clothesChangeStarted", localPlayer, function(durationMs)
    exports.ui:progressStart(lang.text("Changing clothes"), durationMs)
end)

addEventHandler("clothesChangeStopped", localPlayer, function()
    exports.ui:progressCancel()
end)

-- refuelling a machine (server/machines.lua, #145): the server moves the petrol while the key is held
addEventHandler("machineRefuelStarted", localPlayer, function(durationMs)
    exports.ui:progressStart(lang.text("Refuelling..."), durationMs)
end)

addEventHandler("machineRefuelStopped", localPlayer, function()
    exports.ui:progressCancel()
end)

local function isKeyHeld(key, cmd)
    if getKeyState(key) then
        return true
    end
    local dev = getResourceFromName("dev")
    return dev and getResourceState(dev) == "running" and exports.dev:isHeld(cmd or key) == true
end

-- treatments (server/medical.lua): the healer holds the interact key, letting go cancels; the patient sees the bar
local treatmentTimer = nil
addEventHandler("treatmentStarted", localPlayer, function(durationMs, healer, label)
    exports.ui:progressStart(label or (healer and lang.text("Treating") or lang.text("Being treated")), durationMs)
    if isTimer(treatmentTimer) then
        killTimer(treatmentTimer)
    end
    if not healer then
        return
    end
    local key = string.lower(getKeyBoundToCommand("interact") or "f")
    treatmentTimer = setTimer(function()
        if not isKeyHeld(key, "interact") then
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

-- A drop: the server has no bounding boxes, so it asks here for the first spot around the player that no vehicle's
-- box and no other world item's box (each plus a margin) holds and no wall hides, and drops there
-- (server/hands.lua, itemDropSpotChosen)
local function insideElement(el, px, py, pz, margin)
    local box = getElementType(el) == "object" and models.bounds or getElementBoundingBox
    local minX, minY, minZ, maxX, maxY, maxZ = box(el)
    if not minX then
        return false
    end
    local ex, ey, ez = getElementPosition(el)
    local ox, oy, oz = px - ex, py - ey, pz - ez
    local m = getElementMatrix(el)
    local lx = ox * m[1][1] + oy * m[1][2] + oz * m[1][3]
    local ly = ox * m[2][1] + oy * m[2][2] + oz * m[2][3]
    local lz = ox * m[3][1] + oy * m[3][2] + oz * m[3][3]
    return geometry.insideBox(lx, ly, lz, minX, minY, minZ, maxX, maxY, maxZ, margin)
end

addEventHandler("itemDropSpotRequested", localPlayer, function(removalId)
    local x, y, z = getElementPosition(localPlayer)
    local _, _, rz = getElementRotation(localPlayer)
    local dz = z - 0.9
    local vehicles = {}
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy, vz = getElementPosition(veh)
        if (vx - x) ^ 2 + (vy - y) ^ 2 + (vz - z) ^ 2 <= 225 then
            vehicles[#vehicles + 1] = veh
        end
    end
    local items = world.itemObjectsNear(x, y, dz, 5)
    -- a spot over a built ramp or floor lies on it: that defence's box (a ramp's covers the whole wedge) does not
    -- block it, and the spot is tested at the surface's height, which the server's world does not have
    local surface
    local function blocked(cx, cy)
        local sz, snx, sny, floor = world.defenceSurfaceBelow(cx, cy, dz)
        local gz = sz or dz
        for _, veh in ipairs(vehicles) do
            if insideElement(veh, cx, cy, gz, 0.3) then
                return true
            end
        end
        for _, obj in ipairs(items) do
            if obj ~= floor and insideElement(obj, cx, cy, gz, 0.2) then
                return true
            end
        end
        if not world.dropSpotReachable(cx, cy, gz) then
            return true
        end
        surface = sz and { sz, snx, sny } or nil
        return false
    end
    local cx, cy = geometry.freeSpot(x, y, rz, 1.0, blocked)
    if removalId then
        triggerServerEvent("defenceRemovalSpotChosen", localPlayer, removalId, cx, cy)
    elseif cx and surface then
        triggerServerEvent("itemDropSpotChosen", localPlayer, cx, cy, surface[1], surface[2], surface[3])
    else
        triggerServerEvent("itemDropSpotChosen", localPlayer, cx, cy)
    end
end)

-- Actions exposed to the HUD interaction chooser.
-- uname: what the player holds (the hud passes it); a Hammer's entries build a defence lying unbuilt
function interactionActions(uname)
    return world.interactionActions(uname)
end

-- luacheck: globals getProductionRecipes
-- Read-only production catalog for the recipe browser (shared/logic/production.lua, also read by the server for
-- crafting's recipe export), in the local player's language.
local production = loadModule("shared/logic/production.lua")
local fishing = loadModule("shared/logic/fishing.lua")
function getProductionRecipes()
    return production.build({
        tr = lang.text,
        unames = exports.data:itemTypes(),
        itemType = function(uname)
            return exports.data:itemType(uname)
        end,
        machines = machines,
        cooking = cooking,
        gardening = gardening,
        small = small,
        fishing = fishing,
    })
end

-- The world items a hold works on (building's build and removal, crafting's construction and deconstruction) stay
-- outlined while it lasts: the server names them when the hold starts and clears them when it stops early; the
-- outline also ends on its own once the hold's time is up.
local holdTargets = nil -- { ids, untilTick }
addEventHandler("itemHoldTargetsShown", localPlayer, function(ids, ms)
    if type(ids) ~= "table" or #ids == 0 then
        holdTargets = nil
        return
    end
    holdTargets = { ids = ids, untilTick = getTickCount() + math.min(tonumber(ms) or 0, 120000) + 300 }
end)
addEventHandler("itemHoldTargetsCleared", localPlayer, function()
    holdTargets = nil
end)
addEventHandler("onClientRender", root, function()
    if not holdTargets then
        return
    end
    if getTickCount() > holdTargets.untilTick then
        holdTargets = nil
        return
    end
    for _, id in ipairs(holdTargets.ids) do
        local obj = world.objectOf(id)
        if obj then
            outline.draw(obj)
        end
    end
end)
