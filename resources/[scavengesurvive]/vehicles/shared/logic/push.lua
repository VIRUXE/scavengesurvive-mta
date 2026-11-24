-- Pushing a vehicle by hand (server/push.lua, client/push.lua). Running into a parked vehicle no longer shoves it
-- (each client holds an empty, standing vehicle still while a ped on foot is against it); a player moves one on
-- purpose with "Push" from the interaction list at its front or rear, then walks into it. The speed comes from the
-- Strength skill, the character's health and the vehicle's mass.
-- Pure logic: no MTA calls at file scope.
local M = {}

M.SKILL = "Strength"
local UNTRAINED_MASS = 3000 -- kg
local MAX_MASS = 10000 -- kg at full Strength
-- getVehicleType values that roll on wheels and stand on their own (a bike falls over, a boat or helicopter has none)
M.TYPES = { Automobile = true, ["Monster Truck"] = true, Quad = true, Trailer = true, Plane = true }
M.REACH = 1.3 -- metres from the bumper the hands still touch it
M.ACCEL = 1.2 -- m/s per second while the player leans in
M.MIN_SKILL_DISTANCE = 3 -- metres a push must move the vehicle to count for the skill

local function strength(skill)
    return math.max(0, math.min(1, tonumber(skill) or 0))
end

function M.canPushMass(mass, skill)
    return (mass or 0) <= UNTRAINED_MASS + (MAX_MASS - UNTRAINED_MASS) * strength(skill)
end

-- Front or rear by the angle round the vehicle (shared/logic/vehicle.lua angleToVehicle: 0 front, 180 rear):
-- +1 when the push moves it forward (the player at its rear), -1 backward (at its front), nil from a side.
function M.side(angle)
    if angle < 40 or angle > 320 then
        return -1
    elseif angle > 140 and angle < 220 then
        return 1
    end
    return nil
end

-- Top speed in m/s: 0.8 untrained to 1.8 for a Master, times 0.4..1 from health, times the mass factor (a 1400 kg
-- car is 1, lighter ones go a little faster, a 3000 kg one about two thirds).
function M.speed(skill, hp, mass)
    skill = strength(skill)
    local health = 0.4 + 0.6 * math.max(0, math.min(1, (tonumber(hp) or 0) / 100))
    local m = math.max(200, tonumber(mass) or 1400)
    local weight = math.max(0.35, math.min(1.3, math.sqrt(1400 / m)))
    return (0.8 + skill) * health * weight
end

-- The skill gain's multiplier for a push that moved the vehicle dist metres (false below the minimum).
function M.skillMult(dist)
    if dist < M.MIN_SKILL_DISTANCE then
        return false
    end
    return math.min(1, dist / 15)
end

return M
