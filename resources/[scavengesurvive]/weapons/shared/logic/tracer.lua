-- Pure bullet tracer geometry and timing (mirrors ../ScavengeSurvive/gamemodes/sss/core/weapon/tracer.pwn).
local Tracer = {}

Tracer.OFFSET = 2.0 -- metres ahead of muzzle where tracer becomes visible
Tracer.SPEED = 800.0 -- metres per second
Tracer.LENGTH = 6.0 -- visible streak length in metres
Tracer.TRACER_AMMO = {
    Ammo556Tracer = true,
    Ammo357Tracer = true,
}

function Tracer.isTracerAmmo(ammoUname)
    return Tracer.TRACER_AMMO[ammoUname] == true
end

function Tracer.spawn(ox, oy, oz, tx, ty, tz, startTick)
    local dx, dy, dz = tx - ox, ty - oy, tz - oz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= Tracer.OFFSET then
        return nil
    end
    local ux, uy, uz = dx / dist, dy / dist, dz / dist
    local travel = dist - Tracer.OFFSET
    local durationMs = (travel / Tracer.SPEED) * 1000.0
    return {
        sx = ox + ux * Tracer.OFFSET,
        sy = oy + uy * Tracer.OFFSET,
        sz = oz + uz * Tracer.OFFSET,
        tx = tx,
        ty = ty,
        tz = tz,
        ux = ux,
        uy = uy,
        uz = uz,
        travel = travel,
        startTick = startTick or 0,
        durationMs = durationMs,
    }
end

function Tracer.segment(tr, nowTick)
    local elapsed = (nowTick or 0) - tr.startTick
    if elapsed >= tr.durationMs then
        return nil
    end
    local headDist = math.min(tr.travel, math.max(0.0, (elapsed / 1000.0) * Tracer.SPEED))
    local tailDist = math.max(0.0, headDist - Tracer.LENGTH)
    return tr.sx + tr.ux * tailDist,
        tr.sy + tr.uy * tailDist,
        tr.sz + tr.uz * tailDist,
        tr.sx + tr.ux * headDist,
        tr.sy + tr.uy * headDist,
        tr.sz + tr.uz * headDist
end

return Tracer
