-- The Flashlight (the port's own light and pose; upstream's item did nothing): held in the hand and switched on with
-- the goggles key, the arm comes up to point it ahead and it throws a narrow beam (server/flashlight.lua keeps who has
-- one on, client/flashlight.lua poses the arm and draws the light on every client).
local UNAME = "Flashlight"

-- the light on the model (flashlight1.dff: the wide head is its -Z end): where it comes from and the way it points
local LENS = { 0.0, 0.0, -0.088 }
local AIM = { 0.0, 0.0, -1.0 }

-- The arm pointing it, as carry.lua's pose: bones[gtaBoneId] = { x, y, z } the way getElementBoneRotation gives
-- them, set on every client each frame, so walking, running and crouching go on underneath (setPedAnimation would
-- run it as a full ped task and freeze WASD). Found live on the studio set.
local POSE = {
    [21] = { -70.9, 98.4, 80.0 }, -- right clavicle (GTA's own ARRESTgun, so the shoulder does not sway with a step)
    [22] = { 34.0, -36.5, -58.5 }, -- right upper arm: down along the ribs, a little forward
    [23] = { 0.0, -78.5, 0.0 }, -- right forearm: ahead at the waist
    [24] = { 141.6, 43.4, -85.7 }, -- right hand: turned until the lens looks ahead and 13 degrees down, at the ground
    -- a dozen steps on
}

-- the ped tasks the arm stays out of (it would point through a climb or a stroke)
local NO_POSE_TASKS = {
    TASK_SIMPLE_CLIMB = true,
    TASK_SIMPLE_SWIM = true,
    TASK_SIMPLE_IN_AIR = true,
    TASK_SIMPLE_FALL = true,
    TASK_SIMPLE_GET_UP = true,
}

-- a rotation `t` of the way (0 .. 1) from the animation's own angles to the pose's, each angle the short way round
local function blend(from, to, t)
    local out = {}
    for i = 1, 3 do
        local d = ((to[i] - from[i] + 180) % 360) - 180
        out[i] = from[i] + d * t
    end
    return out
end

-- the light's origin and aim in the world for the held object's matrix (getElementMatrix): x, y, z, dx, dy, dz
local function lensPose(m)
    local function apply(v, w)
        return m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3] + m[4][1] * w,
            m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3] + m[4][2] * w,
            m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3] + m[4][3] * w
    end
    local x, y, z = apply(LENS, 1)
    local dx, dy, dz = apply(AIM, 0)
    return x, y, z, dx, dy, dz
end

-- The beam's aim kept near the way the holder faces: the lens' own aim dx, dy, dz, turned no further than AIM_YAW
-- degrees off the facing fx, fy and tilted no further than AIM_PITCH allows. A run leans the body, and the hand with
-- it, 40 degrees down, which put the light at the runner's feet; standing still nothing is changed.
local AIM_YAW = 20
local AIM_PITCH = { -24, 8 } -- degrees below and above level

local function steady(dx, dy, dz, fx, fy)
    local facing = math.atan2(fy, fx)
    local yaw = math.atan2(dy, dx) - facing
    yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
    local limit = math.rad(AIM_YAW)
    yaw = math.max(-limit, math.min(limit, yaw)) + facing
    local flat = math.sqrt(dx * dx + dy * dy)
    local pitch = math.atan2(dz, flat)
    pitch = math.max(math.rad(AIM_PITCH[1]), math.min(math.rad(AIM_PITCH[2]), pitch))
    local c = math.cos(pitch)
    return math.cos(yaw) * c, math.sin(yaw) * c, math.sin(pitch)
end

-- The lens' glow (a corona) for a camera `toward` the beam: the cosine of the angle between the aim and the way to
-- the camera. Nothing from behind or side on, all of GLOW_ALPHA from GLOW_FULL on.
local GLOW_ALPHA = 170
local GLOW_FROM, GLOW_FULL = 0.15, 0.5

local function glowAlpha(toward)
    local t = math.max(0, math.min(1, (toward - GLOW_FROM) / (GLOW_FULL - GLOW_FROM)))
    return math.floor(GLOW_ALPHA * t + 0.5)
end

return {
    UNAME = UNAME,
    POSE = POSE,
    NO_POSE_TASKS = NO_POSE_TASKS,
    RAISE_MS = 220, -- the arm comes up and goes down over this long
    STEADY_MS = 90, -- the beam follows the hand this slowly, so a step's jolt does not shake it
    -- the beam on walls, ground and objects (world/client/blackout.fx): how far it reaches, the cosines of the half
    -- angles where it is full and where it is gone, and its colour
    RADIUS = 32.0,
    CONE = { 0.972, 0.90 },
    COLOUR = { 0.86, 0.82, 0.70 },
    -- createLight's point light for peds and vehicles, which the world shader does not reach, this far down the beam
    PED_LIGHT_RADIUS = 9.0,
    PED_LIGHT_AHEAD = 4.0,
    blend = blend,
    lensPose = lensPose,
    steady = steady,
    glowAlpha = glowAlpha,
}
