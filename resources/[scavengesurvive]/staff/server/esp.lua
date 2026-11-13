-- Duty ESP: a position snapshot of every player, pushed once a second to staff on duty only. The client draws a marker
-- and label for each one wherever they are, even outside stream range (client/main.lua drawEsp).
return function(ctx)
    local state = ctx.state
    local M = {}

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
                    x = x, y = y, z = z, int = int, dim = dim,
                    hp = math.floor(getElementHealth(p)),
                    armour = math.floor(getPedArmor(p)),
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
            triggerClientEvent(p, "staffEspChanged", p, snapshot())
        end
    end

    function M.hideFor(p)
        if isElement(p) then
            triggerClientEvent(p, "staffEspChanged", p, {})
        end
    end

    setTimer(function()
        if next(state.duty) == nil then
            return
        end
        local list = snapshot()
        for p in pairs(state.duty) do
            if isElement(p) then
                triggerClientEvent(p, "staffEspChanged", p, list)
            end
        end
    end, 1000, 0)

    return M
end
