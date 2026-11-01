-- Pure excess-accuracy window of upstream hack-detect.pwn (NUM_SHOT_CHECK 10, EXCESS_AMOUNT 7): a rolling ring of the
-- last shots at a moving target, a hit is 1 and a miss 0; a full ring with 7 or more hits is a warning. A shot at a
-- standing target is not recorded at all. No MTA calls at file scope.
local accuracy = {}

accuracy.WINDOW = 10
accuracy.EXCESS = 7

function accuracy.new()
    return { shots = 0, hits = 0, ring = {}, cursor = 0, checks = 0 }
end

-- hit: true / false for a recorded shot. Returns the hit count of the full ring when it warrants a warning, else nil.
function accuracy.record(state, hit)
    state.shots = state.shots + 1
    if hit then
        state.hits = state.hits + 1
    end
    state.cursor = state.cursor + 1
    state.ring[state.cursor] = hit and 1 or 0
    local warn
    if state.cursor == accuracy.WINDOW then
        local count = 0
        for i = 1, accuracy.WINDOW do
            count = count + state.ring[i]
        end
        if count >= accuracy.EXCESS then
            warn = count
            state.checks = state.checks + 1
        end
        state.cursor = 0
        state.ring = {}
    end
    return warn
end

function accuracy.ratio(state)
    if state.shots == 0 then
        return 0
    end
    return state.hits / state.shots
end

return accuracy
