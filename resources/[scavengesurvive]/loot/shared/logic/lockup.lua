-- The SF lockup's stash, pure logic. Upstream's code hunt (world/puzzles/codehunt.pwn) promised "high value loot
-- spawn in each lockup" and gave the SF lockup four ordinary world_survivor points. Here the four code parts lead to a
-- stash crate in the lockup, stocked on every world start (with the new code) and never refilled before the next
-- one: whoever solves the hunt first takes the haul. Every section of the haul is always there, the rolls only pick
-- which variant: a long gun and a sidearm with full magazines and full spare tins, armour and a helmet, night or
-- thermal optics, a big bag, medical supplies, ordnance, a Hack Interface (the way into Area 69's keypads) and the
-- stash keeper's valuables; now and then a heavy weapon on top.
local lockup = {}

lockup.KIND = "lockup"
-- the stash crate, in the middle of the lockup room (codehunt.pwn LoadLockup_SF's interior at z 1036)
lockup.POS = { -2497.9, 313.4, 1035.87 }
-- its slots are drops.LOCKUP_CRATE_SIZE (80 item size units; the largest haul, minigun included, is about 70)

-- a pick of one variant: { weight, unames... } or { weight, { uname, count }... }
lockup.SECTIONS = {
    -- long gun, loaded, with three full tins of its own ammunition
    {
        gun = true,
        tins = 3,
        { 30, "SniperRifle" },
        { 25, "M16Rifle" },
        { 25, "AK47Rifle" },
        { 12, "Model70Rifle" },
        { 8, "LenKnocksRifle" },
    },
    -- sidearm, loaded, with two full tins
    { gun = true, tins = 2, { 50, "DesertEagle" }, { 50, "M9PistolSD" } },
    { { 60, "SpecialArmour", "HelmArmy" }, { 40, "SpecialArmour", "SwatHelmet" } },
    { { 60, "NightVision" }, { 40, "ThermalVision" } },
    { { 60, "LargeBackpack" }, { 40, "ParaBag" } },
    { { 100, { "Medkit", 2 }, "AutoInjec", "AntiSepBandage" } },
    {
        { 30, { "Grenade", 2 } },
        { 20, { "TntTimebomb", 2 } },
        { 25, { "EmpProxMine", 2 } },
        { 25, { "IedTripMine", 2 } },
    },
    -- the way into Area 69: the Hack Interface tries a keypad's code (area69.lua), the lockpick a vehicle's
    { { 100, "HackDevice" } },
    { { 50, "LockBreaker" }, { 50, "LocksmithKit" } },
    -- the stash keeper's valuables
    { { 40, { "Money", 3 }, "Whisky" }, { 35, { "Money", 5 } }, { 25, { "Money", 2 }, "Champagne", "MeteoriteBar" } },
}

-- the heavy weapon on top, 15 % of the time: { uname, tins of its ammo }
lockup.JACKPOT_CHANCE = 0.15
lockup.JACKPOTS = {
    { 45, "RocketLauncher", tins = 3 },
    { 35, "Heatseeker", tins = 2 },
    { 20, "Minigun", tins = 4 },
}

local function weighted(list, rng)
    local total = 0
    for _, v in ipairs(list) do
        total = total + v[1]
    end
    local r = rng() * total
    for _, v in ipairs(list) do
        r = r - v[1]
        if r < 0 then
            return v
        end
    end
    return list[#list]
end

-- The haul: { { uname = ..., data = json or nil }, ... }. def(uname) is the item type (data's itemType), ammo(calibre)
-- the ammo unames of a calibre (data's ammoTypesForCalibre); rng() a float in [0, 1). A gun comes with a full
-- magazine of its first ammo type and its tins full; an item whose data is nil gets the loot defaults (medical
-- rolls and the like) from the caller.
function lockup.haul(def, ammo, rng)
    local out = {}
    local function add(uname, data)
        if def(uname) then
            out[#out + 1] = { uname = uname, data = data }
        end
    end
    local function gun(uname, tins)
        local d = def(uname)
        local cd = d and d.categoryData
        local list = cd and cd.calibre and ammo(cd.calibre)
        local tin = type(list) == "table" and list[1] or nil
        local tinDef = tin and def(tin)
        if not d then
            return
        end
        if tin and (tonumber(cd.magSize) or 0) > 0 then
            add(uname, string.format('{"mag":%d,"reserve":0,"ammoItem":%q}', cd.magSize, tin))
        else
            add(uname, '{"mag":0,"reserve":0}')
        end
        local rounds = tinDef and tinDef.categoryData and tonumber(tinDef.categoryData.rounds) or 1
        for _ = 1, tin and tins or 0 do
            add(tin, string.format('{"rounds":%d}', math.max(1, math.floor(rounds))))
        end
    end
    for _, section in ipairs(lockup.SECTIONS) do
        local pick = weighted(section, rng)
        for i = 2, #pick do
            local e = pick[i]
            if section.gun then
                gun(e, section.tins)
            elseif type(e) == "table" then
                for _ = 1, e[2] do
                    add(e[1])
                end
            else
                add(e)
            end
        end
    end
    if rng() < lockup.JACKPOT_CHANCE then
        local j = weighted(lockup.JACKPOTS, rng)
        gun(j[2], j.tins)
    end
    return out
end

return lockup
