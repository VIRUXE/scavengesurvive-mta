-- Green-screen photo studio, server side: moves a player into a private dimension at the studio spot, freezes
-- them on an invisible floor slab and tells their client to draw the green box and place the camera; puts them
-- back exactly where they were on /studio, death, quit or resource stop. Survival is held still meanwhile: a
-- long shoot used to starve or bleed the frozen ped to death. Loaded by server/main.lua with
-- { logic = <shared/logic/studio.lua>, say = say }; returns { enter, leave, isIn, setCam, pose, setModels }.
return function(ctx)
    local studio, say = ctx.logic, ctx.say
    local occupants = {} -- player -> { x, y, z, rz, interior, dimension, frozen, studioDim, floor, stats }
    local HELD_STATS = { "hp", "food" } -- bleed only kills through hp; raising it via modifyStat adds a wound

    local function usedDimensions()
        local used = {}
        for _, o in pairs(occupants) do
            used[o.studioDim] = true
        end
        return used
    end

    local M = {}

    function M.isIn(p)
        return occupants[p] ~= nil
    end

    function M.enter(p)
        if occupants[p] then
            return true
        end
        if getPedOccupiedVehicle(p) then
            removePedFromVehicle(p)
        end
        local x, y, z = getElementPosition(p)
        local _, _, rz = getElementRotation(p)
        local o = {
            x = x,
            y = y,
            z = z,
            rz = rz,
            interior = getElementInterior(p),
            dimension = getElementDimension(p),
            frozen = isElementFrozen(p),
            studioDim = studio.freeDimension(usedDimensions()),
        }
        local c = studio.CENTRE
        o.floor = createObject(studio.FLOOR_MODEL, c.x, c.y, c.z - studio.FEET)
        if o.floor then
            setElementAlpha(o.floor, 0)
            setElementDimension(o.floor, o.studioDim)
        end
        o.stats = exports.character:getStats(p) or nil
        occupants[p] = o
        -- server-only: a death in here drops the inventory at the real spot, not in the private dimension
        setElementData(p, "character.realPosition", { o.x, o.y, o.z, o.interior, o.dimension }, "local")
        setElementInterior(p, 0)
        setElementDimension(p, o.studioDim)
        setElementPosition(p, c.x, c.y, c.z)
        setElementFrozen(p, true)
        triggerClientEvent(p, "devStudioStateChanged", p, true, studio.parseCam({}), 0)
        return true
    end

    -- restore = false when the player died: the character resource respawns them, so only drop the state
    function M.leave(p, restore)
        local o = occupants[p]
        if not o then
            return false
        end
        occupants[p] = nil
        removeElementData(p, "character.realPosition")
        if isElement(o.floor) then
            destroyElement(o.floor)
        end
        if restore ~= false then
            setElementFrozen(p, o.frozen)
            setElementInterior(p, o.interior)
            setElementDimension(p, o.dimension)
            setElementPosition(p, o.x, o.y, o.z)
        end
        triggerClientEvent(p, "devStudioStateChanged", p, false, nil, restore ~= false and o.rz or nil)
        return true
    end

    -- args: { preset } or { yaw, dist, height [, lookZ] }; returns the camera spec, or nil and a message
    function M.setCam(p, args)
        local cam, err = studio.parseCam(args)
        if not cam then
            return nil, err
        end
        triggerClientEvent(p, "devStudioCamChanged", p, cam)
        return cam
    end

    -- the player's own client owns its ped's heading: a server-side setElementRotation does not stick
    function M.pose(p, rz)
        triggerClientEvent(p, "devStudioPoseChanged", p, rz)
    end

    -- list: studio.parseModels' result, or nil to put the ped back on the set. The ped waits under the floor
    -- meanwhile: hiding it with alpha would leave what it wears and holds in the shot.
    function M.setModels(p, list)
        local o = occupants[p]
        if not o then
            return false
        end
        o.models = list and #list > 0 and list or nil
        local c = studio.CENTRE
        setElementPosition(p, c.x, c.y, c.z - (o.models and studio.MODEL_DROP or 0))
        triggerClientEvent(p, "devStudioModelsChanged", p, o.models or {}, o.studioDim)
        return true
    end

    local function describeCam(cam)
        return string.format("yaw=%g dist=%g height=%g lookZ=%g", cam.yaw, cam.dist, cam.height, cam.lookZ)
    end
    M.describeCam = describeCam
    M.parseModels = studio.parseModels

    ctx.command("studio", function(p, ...)
        local args = { ... }
        if #args == 0 and occupants[p] then
            M.leave(p)
            return say(p, "left the studio")
        end
        M.enter(p)
        local cam, err = M.setCam(p, args)
        if not cam then
            return say(p, "%s", err)
        end
        say(
            p,
            "studio: %s; /studiocam to move the camera, /studiopose <rz> to turn, /studio to leave",
            describeCam(cam)
        )
    end)

    ctx.command("studiocam", function(p, ...)
        if not occupants[p] then
            return say(p, "not in the studio; /studio first")
        end
        local cam, err = M.setCam(p, { ... })
        say(p, "%s", cam and describeCam(cam) or err)
    end)

    ctx.command("studiomodel", function(p, ...)
        local spec = table.concat({ ... }, ",")
        if spec == "" then
            return say(p, "usage: /studiomodel <model>[@rx/ry/rz][,<model>...] | off")
        end
        if spec == "off" then
            M.setModels(p, nil)
            return say(p, occupants[p] and "the ped is back on the set" or "not in the studio")
        end
        local list, err = studio.parseModels(spec)
        if not list then
            return say(p, "%s", err)
        end
        M.enter(p)
        M.setModels(p, list)
        say(p, "studio: %d model(s) on the set; /studiocam to move the camera, /studiomodel off for the ped", #list)
    end)

    ctx.command("studiopose", function(p, rz)
        if not occupants[p] then
            return say(p, "not in the studio; /studio first")
        end
        if not tonumber(rz) then
            return say(p, "usage: /studiopose <rz degrees>")
        end
        M.pose(p, tonumber(rz))
    end)

    -- "high" so the player is back in place before auth's onPlayerQuit raises playerLoggedOut and character
    -- saves the position: a quit from the studio must not persist z=2500 in a studio dimension
    addEventHandler("onPlayerQuit", root, function()
        M.leave(source)
    end, true, "high+10")

    addEventHandler("onPlayerWasted", root, function()
        M.leave(source, false)
    end)

    -- the character survival tick keeps running in the studio; undo its drift every second
    setTimer(function()
        for p, o in pairs(occupants) do
            local now = o.stats and exports.character:getStats(p)
            if now then
                for _, key in ipairs(HELD_STATS) do
                    local delta = o.stats[key] - now[key]
                    if math.abs(delta) > 1e-6 then
                        exports.character:modifyStat(p, key, delta)
                    end
                end
            end
        end
    end, 1000, 0)

    addEventHandler("onResourceStop", resourceRoot, function()
        for p in pairs(occupants) do
            M.leave(p)
        end
    end)

    return M
end
