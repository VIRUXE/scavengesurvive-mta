-- Loading screen numbers: how the key art is cropped to the screen, the download fraction and its label, and the
-- fade once the character has spawned.
local M = {}

M.HOLD_MS = 600 -- the art stays this long after the spawn (the world streams in behind it)
M.FADE_MS = 700
M.FOCUS_X = 0.38 -- where a narrower screen centres its crop: between the survivor and the crate

-- The part of an iw x ih image that fills an sw x sh screen without stretching: u, v, w, h in image pixels.
function M.cover(sw, sh, iw, ih)
    local screenAspect, imageAspect = sw / sh, iw / ih
    if screenAspect >= imageAspect then
        local h = iw / screenAspect
        return 0, (ih - h) / 2, iw, h
    end
    local w = ih * screenAspect
    local u = math.max(0, math.min(iw - w, iw * M.FOCUS_X - w / 2))
    return u, 0, w, ih
end

-- Downloaded share, 0 to 1 (0 while the total is unknown).
function M.fraction(done, total)
    done, total = tonumber(done) or 0, tonumber(total) or 0
    if total <= 0 then
        return 0
    end
    return math.max(0, math.min(1, done / total))
end

-- "63%   12.4 / 80.1 MB"
function M.label(done, total)
    local mb = 1024 * 1024
    return string.format("%d%%   %.1f / %.1f MB", math.floor(M.fraction(done, total) * 100), done / mb, total / mb)
end

-- Opacity of the whole screen, 1 to 0: full until HOLD_MS after the spawn, gone FADE_MS later.
function M.opacity(now, spawnedAt)
    if not spawnedAt then
        return 1
    end
    local t = (now - spawnedAt - M.HOLD_MS) / M.FADE_MS
    return math.max(0, math.min(1, 1 - t))
end

-- One step of a value easing towards its target, independent of the frame rate.
function M.approach(value, target, dtMs, rate)
    local k = 1 - math.exp(-(rate or 8) * dtMs / 1000)
    return value + (target - value) * k
end

return M
