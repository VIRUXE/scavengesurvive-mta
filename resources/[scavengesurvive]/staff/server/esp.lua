-- ESP: a position snapshot pushed to staff on duty and developers who enable it off duty. The client draws a marker
-- and label for each one wherever they are, even outside stream range (client/main.lua drawEsp).
return function(ctx)
    local state = ctx.state
    local M = {}
    local hiddenOnDuty = {}
    local shownOffDuty = {}

    local function isShown(p)
        if state.duty[p] then
            return not hiddenOnDuty[p]
        end
        return shownOffDuty[p] and ctx.level(p) >= ctx.logic.MAX_LEVEL
    end

    local function snapshot()
        local out = {}
        for _, p in ipairs(getElementsByType("player")) do
            if not state.spectating[p] then
                local x, y, z, int, dim
                local real = getElementData(p, "character.realPosition") -- set by the dev studio; same rule as ghosts
                if type(real) == "table" and real.x then
                    x, y, z, int, dim = real.x, real.y, real.z, real.interior or 0, real.dimension or 0
                else
                    x, y, z = getElementPosition(p)
                    int, dim = getElementInterior(p), getElementDimension(p)
                end
                local veh = getPedOccupiedVehicle(p)
                out[#out + 1] = {
                    p = p,
                    name = getPlayerName(p),
                    x = x,
                    y = y,
                    z = z,
                    int = int,
                    dim = dim,
                    veh = veh and getVehicleName(veh) or nil,
                    dead = isPedDead(p) or nil,
                    authed = state.authed[p] and true or nil,
                    duty = state.duty[p] and true or nil,
                }
            end
        end
        return out
    end

    function M.sendTo(p)
        if isElement(p) then
            triggerClientEvent(p, "staffEspChanged", p, isShown(p) and snapshot() or {})
        end
    end

    function M.forget(p)
        hiddenOnDuty[p] = nil
        shownOffDuty[p] = nil
    end

    ctx.command({
        name = "esp",
        level = 2,
        usage = "/esp",
        help = "Toggle player and nearby vehicle ESP.",
        playerOnly = true,
        needsDb = false,
        fn = function(p, _, level)
            if state.duty[p] then
                hiddenOnDuty[p] = not hiddenOnDuty[p] or nil
            elseif level >= ctx.logic.MAX_LEVEL then
                shownOffDuty[p] = not shownOffDuty[p] or nil
            else
                ctx.say(p, " >  You must be on duty (/duty) to do that.")
                return
            end
            M.sendTo(p)
            ctx.say(p, " >  ESP %s", isShown(p) and "shown" or "hidden")
        end,
    })

    setTimer(function()
        if next(state.duty) == nil and next(shownOffDuty) == nil then
            return
        end
        local list
        for _, p in ipairs(getElementsByType("player")) do
            if shownOffDuty[p] and ctx.level(p) < ctx.logic.MAX_LEVEL then
                shownOffDuty[p] = nil
                M.sendTo(p)
            elseif isShown(p) then
                list = list or snapshot()
                triggerClientEvent(p, "staffEspChanged", p, list)
            end
        end
    end, 1000, 0)

    return M
end
