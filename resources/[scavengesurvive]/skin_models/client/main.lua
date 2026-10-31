-- Hatless ped variants (peds.lua, written by tools/extract_ped_models.py): a copy of a skin whose mesh carries
-- its own hat, cap or helmet, with that headgear cut away so a worn hat sits clean. The variant shares the base
-- skin's TXD and animations, plus its own txd when the head was rebuilt (the hair texture, #89);
-- items swaps a player onto it locally while a hat is worn (#75).
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local hatless = {} -- base skin -> allocated ped model
local bare = {} -- base skin -> its twin, when the twin's head was rebuilt bare (its own hair TXD, #89)
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifest = loader.loadLuaFile("peds.lua", "=skin_models/peds.lua")
    for base, e in pairs(manifest) do
        local id, err = ldr.loadPed(base, e)
        if id then
            hatless[base] = id
            bare[base] = e.txd and id or nil
            count = count + 1
        else
            failed[#failed + 1] = "skin " .. base .. " (" .. err .. ")"
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("skin_models: %d hatless skins loaded%s"):format(count, suffix)
    outputDebugString(msg, #failed > 0 and 2 or 3)
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    hatless, bare = {}, {}
    triggerEvent("sampModelsChanged", root)
    ldr.freeAll()
end)

-- base skin -> this client's hatless variant of it, or false when the skin has none (or the pack is not loaded)
function hatlessSkin(skin)
    return hatless[skin] or false
end

-- base skin -> its twin when that twin has a rebuilt bare head, shown in place of the skin at all times; false for
-- the twins that are only fit to be seen under a hat
function bareSkin(skin)
    return bare[skin] or false
end
