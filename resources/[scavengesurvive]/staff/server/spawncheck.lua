-- /spawncheck: the in-game review of the spawn fit check (the spawncheck resource draws it, docs/reviews/
-- 2026-11-17-vehicle-spawn-fit.md lists it). Developer level, on duty. No argument toggles the overlay; next / prev
-- walk the issues and teleport there, vehicles / loot switch between vehicle points with removed types and loot
-- points with cramped slots, a number goes to that point, reload re-reads the tables after tools/spawn_ground.py.
return function(ctx)
    local M = {}

    local function running()
        local res = getResourceFromName("spawncheck")
        return res and getResourceState(res) == "running"
    end

    ctx.command({
        name = "spawncheck",
        level = 5,
        playerOnly = true,
        usage = "/spawncheck [next|prev|vehicles|loot|<point id>|reload|off]",
        help = "Review the spawn fit check: vehicle types removed from points, cramped loot slots",
        fn = function(p, args)
            if not running() then
                return ctx.say(p, " >  Start the spawncheck resource first.")
            end
            if getElementData(p, "staff.duty") ~= true then
                return ctx.say(p, " >  You must be on duty (/duty) to do that.")
            end
            local arg = args[1] and args[1]:lower() or nil
            if arg == "reload" then
                exports.spawncheck:reload()
                return ctx.say(p, " >  Spawn check data reloading.")
            end
            if not arg or arg == "off" or arg == "on" then
                local want = nil -- no argument flips it
                if arg == "on" then
                    want = true
                elseif arg == "off" then
                    want = false
                end
                local _, msg = exports.spawncheck:toggle(p, want)
                return ctx.say(p, " >  %s", msg)
            end
            ctx.say(p, " >  %s", exports.spawncheck:step(p, arg))
        end,
    })

    return M
end
