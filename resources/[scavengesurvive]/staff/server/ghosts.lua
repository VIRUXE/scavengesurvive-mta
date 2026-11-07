-- Duty ghosts: where players were standing when they left. The quit spot is remembered in memory for a while and
-- pushed to staff on duty only, who see a translucent ped and a label there (client/main.lua). A ghost goes away when
-- that account logs in again, when it expires, or when the staff resource restarts.
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
return function(ctx)
    local state = ctx.state
    local M = {}

    local LIFETIME = 30 * 60 -- seconds a ghost stays
    local MAX_GHOSTS = 100
    local nextId = 0

    state.ghosts = state.ghosts or {}
    state.authed = state.authed or {}

    -- the list as sent to a client: ages instead of timestamps so client clock skew does not matter
    local function payload()
        local now = getRealTime().timestamp
        local out = {}
        for _, g in ipairs(state.ghosts) do
            out[#out + 1] = {
                id = g.id,
                name = g.name,
                skin = g.skin,
                x = g.x,
                y = g.y,
                z = g.z,
                rz = g.rz,
                int = g.int,
                dim = g.dim,
                reason = g.reason,
                age = now - g.at,
            }
        end
        return out
    end

    function M.sendTo(p)
        if isElement(p) then
            triggerClientEvent(p, "staffGhostsChanged", p, payload())
        end
    end

    function M.hideFor(p)
        if isElement(p) then
            triggerClientEvent(p, "staffGhostsChanged", p, {})
        end
    end

    local function pushAll()
        local list = payload()
        for p in pairs(state.duty) do
            if isElement(p) then
                triggerClientEvent(p, "staffGhostsChanged", p, list)
            end
        end
    end

    -- Called from the quit handler before the staff state is torn down.
    function M.record(p, reason)
        if not state.authed[p] or state.duty[p] or state.spectating[p] or isPedDead(p) then
            return
        end
        local x, y, z, int, dim
        local real = getElementData(p, "character.realPosition") -- set by the dev studio; same rule as character/tick
        if type(real) == "table" and real.x then
            x, y, z, int, dim = real.x, real.y, real.z, real.interior or 0, real.dimension or 0
        else
            x, y, z = getElementPosition(p)
            int, dim = getElementInterior(p), getElementDimension(p)
        end
        local _, _, rz = getElementRotation(p)
        nextId = nextId + 1
        state.ghosts[#state.ghosts + 1] = {
            id = nextId,
            name = getPlayerName(p),
            accountId = ctx.accountId(p),
            skin = getElementModel(p),
            x = x, y = y, z = z, rz = rz,
            int = int, dim = dim,
            reason = tostring(reason or "Quit"),
            at = getRealTime().timestamp,
        }
        while #state.ghosts > MAX_GHOSTS do
            table.remove(state.ghosts, 1)
        end
        log.event("staff.ghostRecorded", { name = getPlayerName(p), x = x, y = y, z = z, reason = reason })
        pushAll()
    end

    -- A player logged in again: their ghost is no longer a whereabouts.
    function M.clearFor(accountId, name)
        local removed = false
        for i = #state.ghosts, 1, -1 do
            local g = state.ghosts[i]
            if (accountId and g.accountId == accountId) or (not accountId and g.name == name) then
                table.remove(state.ghosts, i)
                removed = true
            end
        end
        if removed then
            pushAll()
        end
    end

    setTimer(function()
        local cutoff = getRealTime().timestamp - LIFETIME
        local removed = false
        for i = #state.ghosts, 1, -1 do
            if state.ghosts[i].at < cutoff then
                table.remove(state.ghosts, i)
                removed = true
            end
        end
        if removed then
            pushAll()
        end
    end, 60000, 0)

    return M
end
