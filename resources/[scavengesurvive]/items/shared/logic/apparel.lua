-- Pure logic for wearable apparel items (hats, masks, armour, holsters, bags).
-- Provides slot resolution, wearable checks, and default bone attach matrices.
local M = {}

local HATS = {
    HelmArmy = true,
    PoliceHelm = true,
    PoliceCap = true,
    CaptainsCap = true,
    SwatHelmet = true,
    TopHat = true,
    CowboyHat = true,
    TruckCap = true,
    BoaterHat = true,
    BowlerHat = true,
    XmasHat = true,
    Beanie = true,
    StrawHat = true,
    WitchesHat = true,
    PizzaHat = true,
}

local MASKS = {
    GasMask = true,
    HockeyMask = true,
    ZorroMask = true,
    PussyMask = true,
    DevilMask = true,
    BandanaBl = true,
    BandanaGr = true,
    BandanaWh = true,
    BandanaPat = true,
}

local ARMOUR = {
    Armour = true,
    Torso = true,
}

local BAGS = {
    Satchel = true,
    Backpack = true,
    LargeBackpack = true,
    Daypack = true,
    MediumBag = true,
    Rucksack = true,
    ParaBag = true,
    HeartShapedBox = true,
}

-- Holstered weapons: map uname to { bone = 1 (spine) or 8 (thigh), offsets = {x,y,z,rx,ry,rz} }
local HOLSTER_THIGH = { 0.061868, 0.008748, 0.136682, 254.87, 0.32, 0.18 }
local HOLSTER_SPINE = { 0.214089, -0.126031, 0.114131, 0.0, 159.52, 0.0 }

local HOLSTERS = {
    -- Thigh / Handguns & Small
    M9Pistol = { bone = 8, offsets = HOLSTER_THIGH },
    M9PistolSD = { bone = 8, offsets = HOLSTER_THIGH },
    DesertEagle = { bone = 8, offsets = HOLSTER_THIGH },
    Sawnoff = { bone = 8, offsets = HOLSTER_THIGH },
    Mac10 = { bone = 8, offsets = HOLSTER_THIGH },
    Tec9 = { bone = 8, offsets = HOLSTER_THIGH },
    StunGun = { bone = 8, offsets = HOLSTER_THIGH },
    Baton = { bone = 8, offsets = HOLSTER_THIGH },
    DogsBreath = { bone = 8, offsets = { 0.176, -0.005, 0.063, -14.5, -0.9, 1.1 } },

    -- Spine / Long weapons
    PumpShotgun = { bone = 1, offsets = HOLSTER_SPINE },
    Spas12 = { bone = 1, offsets = HOLSTER_SPINE },
    MP5 = { bone = 1, offsets = HOLSTER_SPINE },
    WASR3Rifle = { bone = 1, offsets = HOLSTER_SPINE },
    M16Rifle = { bone = 1, offsets = HOLSTER_SPINE },
    SemiAutoRifle = { bone = 1, offsets = HOLSTER_SPINE },
    SniperRifle = { bone = 1, offsets = HOLSTER_SPINE },
    AK47Rifle = { bone = 1, offsets = HOLSTER_SPINE },
    M77RMRifle = { bone = 1, offsets = HOLSTER_SPINE },
    Model70Rifle = { bone = 1, offsets = HOLSTER_SPINE },
    LenKnocksRifle = { bone = 1, offsets = HOLSTER_SPINE },
    RocketLauncher = { bone = 1, offsets = { 0.182, -0.238, -0.095, 252.8, 353.9, 357.5 } },
    Heatseeker = { bone = 1, offsets = { 0.182, -0.238, -0.095, 252.8, 353.9, 357.5 } },
    Spade = { bone = 1, offsets = { 0.179, -0.032, 0.0, 0.0, -112.2, -78.4 } },
    Sword = { bone = 1, offsets = { 0.123, -0.129, -0.139, 0.0, 301.5, 0.0 } },
    Shield = { bone = 1, offsets = { 0.027, -0.040, 0.170, 270.0, -171.0, 90.0 } },
}

--- Resolves the apparel slot name for an item unique name.
---@param uname string
---@return string|nil "hat"|"mask"|"armour"|"bag"|"holster"|nil
function M.slotFor(uname)
    if not uname then
        return nil
    end
    if HATS[uname] then
        return "hat"
    end
    if MASKS[uname] then
        return "mask"
    end
    if ARMOUR[uname] then
        return "armour"
    end
    if BAGS[uname] then
        return "bag"
    end
    if HOLSTERS[uname] then
        return "holster"
    end
    return nil
end

--- Returns whether an item can be worn as apparel or holstered.
---@param uname string
---@return boolean
function M.isWearable(uname)
    return M.slotFor(uname) ~= nil
end

--- Returns the attachment configuration { bone, offsets, scale } for an item in a gear slot.
---@param slot string
---@param uname string
---@return table|nil
function M.attachConfig(slot, uname)
    if slot == "hat" then
        return {
            bone = 2, -- SA-MP head (GTA bone 8)
            offsets = { 0.152, 0.0, -0.006, 0.0, 0.0, 0.0 },
            scale = { 1.0, 1.0, 1.0 },
        }
    elseif slot == "mask" then
        return {
            bone = 2, -- SA-MP head (GTA bone 8)
            offsets = { 0.08, 0.03, 0.0, -85.5, 8.6, -92.8 },
            scale = { 1.0, 1.0, 1.0 },
        }
    elseif slot == "armour" then
        return {
            bone = 1, -- SA-MP spine (GTA bone 3)
            offsets = { 0.117, 0.05, 0.009, -1.2, 0.5, 0.0 },
            scale = { 1.05, 1.08, 0.95 },
        }
    elseif slot == "holster" then
        local cfg = HOLSTERS[uname]
        if cfg then
            return {
                bone = cfg.bone,
                offsets = cfg.offsets,
                scale = { 1.0, 1.0, 1.0 },
            }
        end
    end
    return nil
end

return M
