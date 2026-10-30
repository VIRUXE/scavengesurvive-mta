-- Poses and the aim shout (upstream core/char/animations.pwn and aim-shout.pwn, #140): sitting down after holding
-- crouch while standing still, hands up on sprint and crouch together, and the line a player shouts by aiming
-- and looking behind at once. Pure rules; the client watches the keys, the server plays the animations.
local M = {}

M.SIT_HOLD_MS = 800 -- crouch held this long while standing still sits the character down
M.SIT_CANCEL_MS = 250 -- let go of crouch sooner than this and it was a crouch, not a sit
M.SIT_IN_MS = 1900 -- PARKSIT_M_IN runs this long before the loop
M.STILL_SPEED = 0.05 -- velocity under this is standing still
M.SHOUT_MAX = 128
M.SHOUT_GAP_MS = 750

M.ANIMS = {
    sitIn = { "SUNBATHE", "PARKSIT_M_IN" },
    sitLoop = { "BEACH", "PARKSIT_M_LOOP" },
    sitOut = { "SUNBATHE", "PARKSIT_M_OUT" },
    handsUp = { "ROB_BANK", "SHP_HandsUp_Scr" },
}

-- The pose a request leads to from the current one: "sit" sits a standing character, "stand" gets a sitting one
-- up, "hands" raises or lowers the hands. Returns the next pose (nil = none) and the animation key to play
-- (nil = nothing to do).
function M.next(pose, action)
    if action == "sit" then
        if pose == nil then
            return "sitting", "sitIn"
        end
    elseif action == "stand" then
        if pose == "sitting" then
            return nil, "sitOut"
        end
    elseif action == "hands" then
        if pose == "handsUp" then
            return nil, "clear"
        elseif pose == nil then
            return "handsUp", "handsUp"
        end
    end
    return pose, nil
end

-- /aimshout text as kept: one line, no colour codes, at most SHOUT_MAX characters; "" when nothing is left
function M.cleanShout(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("[%c]", " "):gsub("#%x%x%x%x%x%x", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, M.SHOUT_MAX)
end

-- whether a shout may go out now (upstream: 750 ms since the last)
function M.canShout(lastTick, now)
    return lastTick == nil or (now - lastTick) > M.SHOUT_GAP_MS
end

-- whether a crouch press that lasted heldMs was a sit (true) or an ordinary crouch
function M.crouchWasSit(heldMs)
    return heldMs >= M.SIT_CANCEL_MS
end

return M
