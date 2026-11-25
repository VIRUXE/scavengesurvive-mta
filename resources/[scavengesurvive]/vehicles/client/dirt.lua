-- luacheck: read globals dxCreateShader dxSetShaderValue engineApplyShaderToWorldTexture

addEventHandler("onClientResourceStart", resourceRoot, function()
    local texture = dxCreateTexture("files/dirt.dds", "dxt1", true, "wrap")
    if not texture then
        return
    end
    -- The mower wheel uses a region of this atlas. Its per-vehicle wheel shader takes priority.
    local shader = dxCreateShader("client/dirt.fx", -1, 0, false, "vehicle")
    if
        shader
        and dxSetShaderValue(shader, "DirtTexture", texture)
        and engineApplyShaderToWorldTexture(shader, "vehiclegrunge256")
    then
        return
    end
    if shader then
        destroyElement(shader)
    end
    destroyElement(texture)
end)
