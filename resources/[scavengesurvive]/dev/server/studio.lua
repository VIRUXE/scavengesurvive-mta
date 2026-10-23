-- Green-screen photo studio, server side: moves a player into a private dimension at the studio spot, freezes
-- them on an invisible floor slab and tells their client to draw the green box and place the camera; puts them
-- back exactly where they were on /studio, death, quit or resource stop. Loaded by server/main.lua with
-- { logic = <shared/logic/studio.lua>, say = say }; returns { enter, leave, isIn, setCam, pose }.
return function(ctx)
    local studio, say = ctx.logic, ctx.say
    local occupants = {} -- player -> { x, y, z, rz, interior, dimension, frozen, studioDim, floor }

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
        occupants[p] = o
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

    local function describeCam(cam)
        return string.format("yaw=%g dist=%g height=%g lookZ=%g", cam.yaw, cam.dist, cam.height, cam.lookZ)
    end
    M.describeCam = describeCam

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

    addEventHandler("onResourceStop", resourceRoot, function()
        for p in pairs(occupants) do
            M.leave(p)
        end
    end)

    return M
end
