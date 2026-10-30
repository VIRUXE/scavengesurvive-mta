-- What others see of a bleeding character (upstream core/char/bleed.pwn): the blood spraying off them and the trail
-- of pools they leave. The bleed rate itself is survival.lua's.
local bleeding = {}
bleeding.POOL_MODEL = 19836 -- SA-MP BloodPool1 (models resource)
bleeding.POOLS = 15 -- per player, reused round-robin (MAX_BLOOD_OBJECTS)
bleeding.POOL_DROP = 0.9 -- below the ped's position, on the ground
bleeding.TICK_MS = 1000 -- upstream drops a pool every OnPlayerScriptUpdate

-- Whether the character shows as bleeding after this second. Upstream re-rolls every second: a showing bleed stops
-- with chance 1 - rate / 0.1 and a hidden one starts with chance rate / 0.1, so a rate of 0.1 or more always shows.
-- Upstream only took the spray off in a vehicle, on admin duty and once the bleed stopped, and kept dropping pools
-- until the next roll; here `blocked` and a stopped bleed hide both. rand() returns [0, 1).
function bleeding.visible(was, rate, blocked, rand)
    if blocked or rate <= 0 or rate ~= rate then
        return false
    end
    if was then
        return rand() * 0.1 >= 0.1 - rate
    end
    return rand() * 0.1 < rate
end

-- Where the next pool lands around the feet and its yaw: upstream's 0.1 * (3 - random(6)) metres on x and y and
-- 0.1 * random(3600) degrees on top of the facing angle, which only ever made it a random yaw.
function bleeding.poolOffset(rand)
    local dx = 0.1 * (3 - math.floor(rand() * 6))
    local dy = 0.1 * (3 - math.floor(rand() * 6))
    return dx, dy, 0.1 * math.floor(rand() * 3600)
end

-- Ring slot after `index` in a ring of `size` (1-based).
function bleeding.nextSlot(index, size)
    return index % size + 1
end

return bleeding
