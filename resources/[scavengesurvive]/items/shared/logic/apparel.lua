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

-- Hats, masks and armour carry upstream's per-skin offsets (item type wearOffsets, keyed by ped model:
-- { x, y, z, rx, ry, rz, sx, sy, sz }). Everything below was tuned in the dev studio (docs/dev-studio.md)
-- where upstream has no row. On the head bone rx turns the item about the up axis (yaw), ry about the
-- forward axis (roll) and rz about the side axis (pitch).

-- Wearables upstream never defined take the per-skin rows of `from` (which carry each skin's head height
-- and size). `rot` replaces the row's rotation (each model has its own pivot: the 186xx/189xx hats lie on
-- their side and need 0/90/90, the 19xxx ones stand upright at 0/0/0), `shift` is added to the position and
-- `scale` (one number or { sx, sy, sz }) multiplies.
local BORROW = {
    Beanie = { from = "HelmArmy" },
    StrawHat = { from = "HelmArmy", rot = { 90, 0, 0 } },
    CaptainsCap = { from = "HelmArmy", shift = { -0.015, 0, 0 } },
    SwatHelmet = { from = "PoliceHelm" },
    PizzaHat = { from = "HelmArmy", rot = { 0, 0, -20 } },
    PussyMask = { from = "HockeyMask", rot = { 0, -20, 0 }, shift = { 0.02, 0.015, 0 }, scale = 0.85 },
    DevilMask = { from = "HockeyMask", rot = { 180, 90, 0 }, shift = { -0.06, 0.065, 0 }, scale = 0.45 },
    Torso = { from = "Armour" },
}

-- Rows that replace upstream's for one skin: OVERRIDES[uname][skin].
local OVERRIDES = {}

-- Position nudges added on top of whatever row is chosen (upstream, borrowed or overridden):
-- NUDGE[uname][skin] = { dx, dy, dz }. Studio-checked: the nose of skins 250 and 188 poked through the bandanas,
-- which sat below the nose on the female civilians; Zorro sat on the nose of 192.
local UP = 0.015
local BANDANA_NUDGE = {
    [250] = { 0, 0.012, 0 },
    [188] = { 0, 0.012, 0 },
    [93] = { UP, 0, 0 },
    [233] = { UP, 0, 0 },
    [193] = { UP, 0, 0 },
    [90] = { UP, 0, 0 },
    [191] = { UP, 0, 0 },
    [131] = { UP, 0, 0 },
}
local NUDGE = {
    BandanaBl = BANDANA_NUDGE,
    BandanaGr = BANDANA_NUDGE,
    BandanaWh = BANDANA_NUDGE,
    BandanaPat = BANDANA_NUDGE,
    ZorroMask = { [192] = { 0.04, 0, 0 } },
}

-- Skins upstream never tuned an item for take the rows of a similar skin: M.skins is the shared/logic/skins.lua
-- module (gender and build per ped model), set by the loader. Without it only the wearer's own row is used.
M.skins = nil

local function rowFor(bySkin, skin)
    if not skin then
        return nil
    end
    local function has(s)
        return bySkin[tostring(s)] ~= nil or bySkin[s] ~= nil
    end
    local donor = M.skins and M.skins.fallback(skin, has) or (has(skin) and skin)
    return donor and (bySkin[tostring(donor)] or bySkin[donor]) or nil
end

-- Used for a skin with no row of its own and no donor (M.skins unset, or an item with no rows at all).
local DEFAULTS = {
    hat = { bone = 2, offsets = { 0.152, 0.0, -0.006, 0.0, 0.0, 0.0 }, scale = { 1.0, 1.0, 1.0 } },
    mask = { bone = 2, offsets = { 0.08, 0.03, 0.0, -85.5, 8.6, -92.8 }, scale = { 1.0, 1.0, 1.0 } },
    armour = { bone = 1, offsets = { 0.064, 0.048, 0.006, -1.2, -1.3, -0.9 }, scale = { 1.138, 1.294, 1.108 } },
}

--- Returns the attachment configuration { bone, offsets, scale } for an item in a gear slot.
---@param slot string
---@param uname string
---@param skin number|nil ped model of the wearer
---@param wearOffsetsOf function|nil uname -> the item type's wearOffsets table (or nil)
---@return table|nil
function M.attachConfig(slot, uname, skin, wearOffsetsOf)
    local default = DEFAULTS[slot]
    if default then
        local borrow = BORROW[uname]
        local o = OVERRIDES[uname] and skin and OVERRIDES[uname][skin]
        if not o then
            local bySkin = wearOffsetsOf and skin and wearOffsetsOf(borrow and borrow.from or uname)
            o = bySkin and rowFor(bySkin, skin)
        elseif borrow then
            borrow = nil -- an override is the final row
        end
        if not o then
            return default
        end
        local shift = borrow and borrow.shift or { 0, 0, 0 }
        local nudge = NUDGE[uname] and NUDGE[uname][skin]
        if nudge then
            shift = { shift[1] + nudge[1], shift[2] + nudge[2], shift[3] + nudge[3] }
        end
        local rot = borrow and borrow.rot or { o[4], o[5], o[6] }
        local mul = borrow and borrow.scale or { 1, 1, 1 }
        if type(mul) == "number" then
            mul = { mul, mul, mul }
        end
        return {
            bone = default.bone,
            offsets = { o[1] + shift[1], o[2] + shift[2], o[3] + shift[3], rot[1], rot[2], rot[3] },
            scale = { (o[7] or 1) * mul[1], (o[8] or 1) * mul[2], (o[9] or 1) * mul[3] },
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

--- Attachment configuration { bone, offsets, scale } for a worn bag, or nil when the bag type has no rows.
--- Bags use upstream's per-skin spine rows (categoryData.bag_offsets = { x, y, z, rx, ry, rz, sx, sy, sz }).
--- Upstream left an untuned skin with no bag at all; the port borrows the nearest tuned skin's row (M.skins).
---@param uname string
---@param skin number|nil ped model of the wearer
---@param bagOffsetsOf function|nil uname -> the bag type's bag_offsets table (or nil)
---@return table|nil
function M.bagConfig(uname, skin, bagOffsetsOf)
    local bySkin = bagOffsetsOf and bagOffsetsOf(uname)
    local o = bySkin and rowFor(bySkin, skin)
    if not o then
        return nil
    end
    return {
        bone = 1,
        offsets = { o[1], o[2], o[3], o[4], o[5], o[6] },
        scale = { o[7] or 1, o[8] or 1, o[9] or 1 },
    }
end

return M
