-- luacheck: read globals dxCreateShader dxSetShaderValue dxDrawMaterialLine3D getElementCollisionsEnabled
local STATE = "stove:burners"
local burners = {
    { -0.128, -0.116, 0.055 }, -- 1 front left, viewed from -Y
    { 0.128, -0.116, 0.050 }, -- 2 front right
    { -0.128, 0.102, 0.050 }, -- 3 rear left
    { 0.128, 0.102, 0.055 }, -- 4 rear right
}
local tracked = {}
local model, txd, dff, col, shader

local function forget(object)
    local entry = tracked[object]
    if not entry then
        return
    end
    if isElement(entry.visual) then
        destroyElement(entry.visual)
    end
    if isElement(object) then
        setElementAlpha(object, entry.alpha)
        setElementCollisionsEnabled(object, entry.collisions)
    end
    tracked[object] = nil
end

local function watch(object)
    if not model or tracked[object] or getElementType(object) ~= "object" or not isElementStreamedIn(object) then
        return
    end
    local levels = getElementData(object, STATE)
    if type(levels) ~= "table" then
        return
    end
    local x, y, z = getElementPosition(object)
    local visual = createObject(model, x, y, z)
    if not visual then
        return
    end
    setElementCollisionsEnabled(visual, true)
    setElementInterior(visual, getElementInterior(object))
    setElementDimension(visual, getElementDimension(object))
    attachElements(visual, object)
    tracked[object] = {
        visual = visual,
        alpha = getElementAlpha(object),
        levels = levels,
        collisions = getElementCollisionsEnabled(object),
    }
    setElementAlpha(object, 0)
    setElementCollisionsEnabled(object, false) -- the compact visual has its own matching collision
end

local function point(m, x, y, z)
    return x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
        x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
        x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    model = engineRequestModel("object", 2417)
    txd = model and engineLoadTXD("files/stove.txd")
    col = txd and engineImportTXD(txd, model) and engineLoadCOL("files/stove.col")
    dff = col and engineReplaceCOL(col, model) and engineLoadDFF("files/stove.dff")
    if not dff or not engineReplaceModel(dff, model) then
        if model then
            engineFreeModel(model)
        end
        model = nil
        outputDebugString("stove: model load failed", 1)
        return
    end
    shader = dxCreateShader("client/flame.fx")
    if not shader then
        outputDebugString("stove: gas flame shader unavailable", 1)
    end
    for _, object in ipairs(getElementsByType("object", root, true)) do
        watch(object)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    watch(source)
end)
addEventHandler("onClientElementStreamOut", root, function()
    forget(source)
end)
addEventHandler("onClientElementDestroy", root, function()
    forget(source)
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key ~= STATE then
        return
    end
    local levels = getElementData(source, STATE)
    if type(levels) ~= "table" then
        forget(source)
    elseif tracked[source] then
        tracked[source].levels = levels
    else
        watch(source)
    end
end)

addEventHandler("onClientPreRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    local time = getTickCount() / 1000
    if shader then
        dxSetShaderValue(shader, "time", time)
    end
    for object, entry in pairs(tracked) do
        local interior, dimension = getElementInterior(object), getElementDimension(object)
        if getElementInterior(entry.visual) ~= interior then
            setElementInterior(entry.visual, interior)
        end
        if getElementDimension(entry.visual) ~= dimension then
            setElementDimension(entry.visual, dimension)
        end
        local x, y, z = getElementPosition(object)
        local near = (x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2 < 40 ^ 2
        if
            shader
            and near
            and interior == getElementInterior(localPlayer)
            and dimension == getElementDimension(localPlayer)
        then
            local matrix = getElementMatrix(object, false)
            if matrix then
                for i, burner in ipairs(burners) do
                    local intensity = tonumber(entry.levels[i]) or 0
                    if intensity > 0 then
                        intensity = math.min(1, intensity)
                        for jet = 1, 12 do
                            local angle = jet * math.pi / 6
                            local radius = burner[3] * 0.72
                            local jx = burner[1] + math.cos(angle) * radius
                            local jy = burner[2] + math.sin(angle) * radius
                            local height = (0.010 + intensity * 0.033)
                                * (1 + 0.10 * math.sin(time * 14 + jet * 1.7 + i))
                            local bx, by, bz = point(matrix, jx, jy, 0.581)
                            local tx, ty, tz = point(matrix, jx, jy, 0.581 + height)
                            dxDrawMaterialLine3D(
                                tx,
                                ty,
                                tz,
                                bx,
                                by,
                                bz,
                                shader,
                                0.008 + 0.013 * intensity,
                                tocolor(255, 255, 255, 210),
                                "postfx"
                            )
                        end
                    end
                end
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for object in pairs(tracked) do
        forget(object)
    end
    if model then
        engineFreeModel(model)
    end
end)
