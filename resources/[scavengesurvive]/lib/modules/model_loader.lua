-- Shared loader for the model resources: loadModel / loadTxd / loadPed with col -> txd -> dff order,
-- parent physical properties inheritance, lod distance, tracking allocated ids and freeing them on unload.
local loader = {}

function loader.new(options)
    local opts = options or {}
    local allocated = {}
    local keep = {}
    local txds = {}
    local ctx = {}

    function ctx.loadTxd(name)
        if txds[name] == nil then
            local txd = engineLoadTXD("files/" .. name .. ".txd") or false
            txds[name] = txd
            if txd then
                keep[#keep + 1] = txd
            end
        end
        return txds[name]
    end

    function ctx.loadModel(e)
        local id = engineRequestModel("object")
        if not id then
            return nil, "no free model id"
        end
        allocated[#allocated + 1] = id
        if
            e.parent
            and not engineSetModelPhysicalPropertiesGroup(id, engineGetModelPhysicalPropertiesGroup(e.parent))
        then
            return nil, "physical properties of model " .. e.parent
        end
        local colName = e.col or e.dff
        local col = engineLoadCOL("files/" .. colName .. ".col")
        if not col or not engineReplaceCOL(col, id) then
            return nil, "col " .. colName
        end
        keep[#keep + 1] = col
        if e.txd then
            local txd = ctx.loadTxd(e.txd)
            if not txd or not engineImportTXD(txd, id) then
                return nil, "txd " .. e.txd
            end
        elseif e.txdModel then
            local txdId = engineGetModelTXDID(e.txdModel)
            if not txdId or not engineSetModelTXDID(id, txdId) then
                return nil, "txd of model " .. e.txdModel
            end
            if opts.onTxdModel then
                local ok, err = opts.onTxdModel(id, e, txdId, ctx.loadTxd)
                if ok == false and err then
                    return nil, err
                end
            end
        end
        local dff = engineLoadDFF("files/" .. e.dff .. ".dff")
        if not dff or not engineReplaceModel(dff, id) then
            return nil, "dff " .. e.dff
        end
        keep[#keep + 1] = dff
        if e.dist then
            engineSetModelLODDistance(id, math.min(e.dist, 300))
        end
        return id
    end

    function ctx.loadPed(base, e)
        local id = engineRequestModel("ped", base)
        if not id then
            return nil, "no free ped model id"
        end
        allocated[#allocated + 1] = id
        local txdId = engineGetModelTXDID(base)
        if not txdId or not engineSetModelTXDID(id, txdId) then
            return nil, "txd of skin " .. base
        end
        if e.txd then
            local txd = engineLoadTXD("files/" .. e.txd .. ".txd")
            if not txd or not engineImportTXD(txd, id) then
                return nil, "txd " .. e.txd
            end
            keep[#keep + 1] = txd
        end
        local dff = engineLoadDFF("files/" .. e.dff .. ".dff")
        if not dff or not engineReplaceModel(dff, id) then
            return nil, "dff " .. e.dff
        end
        keep[#keep + 1] = dff
        return id
    end

    function ctx.freeAll()
        for _, id in ipairs(allocated) do
            engineFreeModel(id)
        end
        allocated = {}
        keep = {}
        txds = {}
    end

    return ctx
end

function loader.loadLuaFile(name, chunkName)
    local f = fileOpen(name, true)
    if not f then
        return {}
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local chunk = loadstring(src, chunkName or ("=" .. name))
    return chunk and chunk() or {}
end

return loader
