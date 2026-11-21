-- The server's collision companion (the sageom resource, https://github.com/VIRUXE/sa-geom): it mirrors every server
-- object and building in dimension 0 into ml_sageom by itself. A resource tells it only what it cannot see: the COL a
-- model id collides with when the server has no such model (replaceCOL) and the model an element collides as when the
-- server created it with a stand-in (setElementCollisionModel, lib standins.lua). Every call is guarded: without the
-- companion nothing happens, and the old overlay (world/server/geom.lua) stays the fallback.
-- Server only: local sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()
local NAME = "sageom"

local function running()
    local res = getResourceFromName(NAME)
    return res and getResourceState(res) == "running" or false
end

-- exports.sageom:fn(...) when the companion runs; false otherwise or when the call fails
local function call(fn, ...)
    if not running() then
        return false
    end
    local exp = exports[NAME]
    local ok, result = pcall(exp[fn], exp, ...)
    return ok and result
end

-- fn() now when the companion runs, and again each time it starts: it forgets what it was told when it stops
local function onReady(fn)
    if running() then
        fn()
    end
    addEventHandler("onResourceStart", root, function(res)
        if getResourceName(res) == NAME then
            fn()
        end
    end)
end

-- Registers the collision of every model of this resource's model pack manifests (lua files returning
-- { [id] = { dff = "name", col = "name"?, ... } }, files in files/<col or dff>.col), as tools/geom_overlay.py picks
-- them; returns how many are registered each time the companion takes them.
local function registerPack(manifests)
    local res = getResourceName(getThisResource())
    local cols = {}
    for _, name in ipairs(manifests) do
        local f = fileOpen(name, true)
        local list = f and assert(loadstring(fileRead(f, fileGetSize(f)), "=" .. res .. "/" .. name))()
        if f then
            fileClose(f)
        end
        for id, e in pairs(list or {}) do
            local col = "files/" .. (e.col or e.dff) .. ".col"
            if fileExists(col) then
                cols[#cols + 1] = { ":" .. res .. "/" .. col, id }
            end
        end
    end
    onReady(function()
        local done = 0
        for _, c in ipairs(cols) do
            if call("replaceCOL", c[1], c[2]) then
                done = done + 1
            end
        end
        outputDebugString(("%s: %d of %d model collisions registered with sageom"):format(res, done, #cols), 3)
    end)
    return #cols
end

return { running = running, call = call, onReady = onReady, registerPack = registerPack }
