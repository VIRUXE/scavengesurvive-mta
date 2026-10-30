-- Weapon overheat on the armed vehicles (upstream char/overheat.pwn). A driver's heat rises by 20 with every main
-- weapon shot while the engine runs and, in the Hunter, by 1 every 100 ms its gun is held; otherwise it falls by 1 a
-- tick. Over 80 % of the maximum the driver is warned, over the maximum the vehicle blows up and the heat starts again.
-- Of the three only the Rhino is a vehicle type (here and upstream), so the Hunter and Hydra need a staff spawn.
local M = {}

M.MAX = 40.0
M.TICK_MS = 100
M.SHOT = 20.0
M.EXPLOSION_TYPE = 11 -- upstream CreateExplosion(x, y, z, 11, 5.0); MTA's type 11 is the same small blast

M.RHINO, M.HUNTER, M.HYDRA = 432, 425, 520
M.MODELS = { [M.RHINO] = true, [M.HUNTER] = true, [M.HYDRA] = true }

function M.isArmed(model)
    return M.MODELS[model] == true
end

-- heat after one tick; holdingGun = the secondary fire control is down
function M.tick(heat, model, holdingGun, engineOn)
    if model == M.HUNTER and holdingGun then
        return engineOn and heat + 1.0 or heat
    end
    return heat > 0.0 and heat - 1.0 or heat
end

-- heat after a main weapon shot (counted only with the engine running)
function M.shot(heat, engineOn)
    return engineOn and heat + M.SHOT or heat
end

function M.isWarning(heat)
    return heat > M.MAX * 0.8
end

function M.isOver(heat)
    return heat > M.MAX
end

return M
