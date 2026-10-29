-- Replaces the vanilla des_westrn9_ house (model 3250) for every client with an enterable copy: the same exterior,
-- roof included, plus an open front doorway and a plastered interior with floor and ceiling. Built from the
-- original gta3.img DFF in Blender with DragonFF; the COL (wall slabs, roof and ceiling surfaces) is rebuilt from
-- it and the TXD is the original cxref_oldwest cut down to the 12 textures the model uses (#131).
local MODEL_ID = 3250
local collision, txd, dff
local replacedCollision, replacedModel = false, false

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Keep the RenderWare load order: collision, texture dictionary, then geometry.
    collision = engineLoadCOL("files/des_westrn9.col")
    txd = engineLoadTXD("files/des_westrn9.txd", true)
    dff = engineLoadDFF("files/des_westrn9.dff", 0)
    if not collision or not txd or not dff then
        outputDebugString("house_shell: failed to load the house COL, TXD, or DFF", 1)
        return
    end

    if not engineReplaceCOL(collision, MODEL_ID) then
        outputDebugString("house_shell: failed to replace collision for model 3250", 1)
        return
    end
    replacedCollision = true
    if not engineImportTXD(txd, MODEL_ID) then
        outputDebugString("house_shell: failed to import TXD for model 3250", 1)
        engineRestoreCOL(MODEL_ID)
        replacedCollision = false
        return
    end
    if not engineReplaceModel(dff, MODEL_ID, false) then
        outputDebugString("house_shell: failed to replace DFF for model 3250", 1)
        engineRestoreCOL(MODEL_ID)
        replacedCollision = false
        return
    end

    replacedModel = true
    -- GTA world buildings can keep their streamed copy until the world is restreamed.
    engineRestreamWorld()
    outputDebugString("house_shell: open des_westrn9_ model 3250 loaded", 3)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if replacedModel then
        engineRestoreModel(MODEL_ID)
        replacedModel = false
    end
    if replacedCollision then
        engineRestoreCOL(MODEL_ID)
        replacedCollision = false
    end
    engineRestreamWorld()
end)
