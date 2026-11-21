-- The server's side of the enterable buildings (client/main.lua rebuilds them on every client): the rebuilt COL of
-- every vanilla model this resource replaces goes to the server's collision companion (lib sageom.lua), so server-side
-- ground and ray queries stand on a shell's floor as players do; and each house's fixed fittings are placed here, for
-- every player at once: the vanilla objects it removes and the stock props it is furnished with (houses.lua, in the
-- model's frame). Its doors swing, so each client hangs its own.
local sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()

local function readLua(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=house_shell/" .. path))()
end

local trailers = readLua("trailers.lua")
local cabins = readLua("cabins.lua")
local houses = readLua("houses.lua")
local removed = {} -- { model, radius, x, y, z } of vanilla objects removed, restored on stop

-- { vanilla model, COL name in files/ } of every model the client replaces (the same list as tools/geom_overlay.py)
local function shellCols()
    local cols = { { 3250, "des_westrn9" }, { 11092, "burgalrystore_sfs" }, { cabins.model, cabins.dff } }
    for model, m in pairs(trailers.models) do
        cols[#cols + 1] = { model, m.dff }
    end
    for _, house in ipairs(houses) do
        cols[#cols + 1] = { house.model, house.dff }
    end
    return cols
end

local function furnish(house, x, y, z, rz)
    local a = math.rad(rz)
    local c, s = math.cos(a), math.sin(a)
    local function at(p1, p2, p3)
        return x + p1 * c - p2 * s, y + p1 * s + p2 * c, z + p3
    end
    for _, r in ipairs(house.remove or {}) do
        local wx, wy, wz = at(r[2], r[3], r[4])
        if removeWorldModel(r[1], r[5], wx, wy, wz) then
            removed[#removed + 1] = { r[1], r[5], wx, wy, wz }
        end
    end
    local count = 0
    for _, p in ipairs(house.props or {}) do
        local px, py, pz = at(p[2], p[3], p[4])
        local obj = createObject(p[1], px, py, pz, 0, 0, rz + p[5])
        if obj then
            setElementFrozen(obj, true) -- kept where it stands, the same for every player
            count = count + 1
        end
    end
    return count
end

addEventHandler("onResourceStart", resourceRoot, function()
    local props = 0
    for _, house in ipairs(houses) do
        for _, p in ipairs(house.placements) do
            props = props + furnish(house, p[1], p[2], p[3], p[4])
        end
    end
    local cols = {}
    for _, c in ipairs(shellCols()) do
        if fileExists("files/" .. c[2] .. ".col") then
            cols[#cols + 1] = c
        else
            outputDebugString("house_shell: no files/" .. c[2] .. ".col for model " .. c[1], 1)
        end
    end
    sageom.onReady(function()
        local done = 0
        for _, c in ipairs(cols) do
            if sageom.call("replaceCOL", ":house_shell/files/" .. c[2] .. ".col", c[1]) then
                done = done + 1
            end
        end
        outputDebugString(("house_shell: %d of %d shell collisions registered with sageom"):format(done, #cols), 3)
    end)
    outputDebugString(("house_shell: %d props placed, %d vanilla objects removed"):format(props, #removed), 3)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[2], r[3], r[4], r[5])
    end
    removed = {}
end)
