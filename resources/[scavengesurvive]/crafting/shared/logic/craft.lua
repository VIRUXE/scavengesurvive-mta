-- Pure recipe matching logic for in-hand combining, ground construction, and workbench crafting.
-- Ported from upstream Scavenge & Survive: the recipes are core/server/init.pwn's CRAFTING SET DEFINITIONS, line for
-- line and in the same order (the first set that matches wins, as upstream _craft_FindCraftset), the rules
-- core/world/craft-construct.pwn and core/item/workbench.pwn.
local M = { RECIPES = {}, byName = {} }

-- upstream ingredients are a list of item types, each consumed or kept; here { uname = n } of the consumed ones and
-- `keep` of the kept ones, turned into { uname, count, keep } rows sorted by name so the order is deterministic
local function ingredientRows(consumed, kept)
    local rows = {}
    for _, set in ipairs({ { consumed or {}, false }, { kept or {}, true } }) do
        local names = {}
        for uname in pairs(set[1]) do
            names[#names + 1] = uname
        end
        table.sort(names)
        for _, uname in ipairs(names) do
            rows[#rows + 1] = { uname = uname, count = set[1][uname], keep = set[2] }
        end
    end
    return rows
end

local function addRecipe(r)
    M.RECIPES[#M.RECIPES + 1] = r
    M.byName[r.name] = r
end

-- 1. Items created by hand: { result, consumed, kept }
local COMBINE = {
    { "ParaBag", { Parachute = 1 }, { Knife = 1 } },
    { "MolotovEmpty", { Bottle = 1, Bandage = 1 } },
    { "Bandage", { Clothes = 1 }, { Knife = 1 } },
    -- upstream also cuts the lock (array data cell 0 = 1); the port's WheelLock carries no cut state yet
    { "WheelLock", { WheelLock = 1, LocksmithKit = 1 } },
    -- upstream's Bottle + Bottle keeps both and makes a third: the liquid merge it stood for is commented out in
    -- liquid-container.pwn, so all it does there is duplicate bottles; not ported
}
for _, c in ipairs(COMBINE) do
    local r = { name = c[1], kind = "combine", ingredients = ingredientRows(c[2], c[3]) }
    r.result = { uname = c[1], count = 1 }
    addRecipe(r)
end

-- 2. Items created by using a tool on them in the world (SetCraftSetConstructible): { result, tool, build ms,
-- consumed, kept, remove = Crowbar ms, tweak, defence }. Every removal tool upstream is the Crowbar; a set without
-- one cannot be taken down. RefineMachine has the ScrapMachine's parts, so as upstream the ScrapMachine wins.
local MACHINE = { Canister = 1, Motor = 1, Fluctuator = 1, PowerSupply = 1 }
local POLE = { Canister = 1, RadioPole = 1, Fluctuator = 1, PowerSupply = 1 }
local GROUND = {
    { "Campfire", "FireLighter", 5000, { WoodLog = 3 }, tweak = false },
    { "PlotPole", "Screwdriver", 20000, POLE, remove = 30000, tweak = false },
    { "ScrapMachine", "Screwdriver", 30000, MACHINE, remove = 25000 },
    { "RefineMachine", "Screwdriver", 30000, MACHINE, remove = 25000 },
    { "WaterMachine", "Screwdriver", 30000, { Canister = 1, Motor = 1, Bucket = 1, PowerSupply = 1 }, remove = 25000 },
    { "Workbench", "Hammer", 30000, { RefinedMetal = 2, WoodLog = 4 }, remove = 25000 },
    { "Locker", "Sledgehammer", 30000, { MetalFrame = 2, RefinedMetal = 1 }, remove = 25000 },
    { "Desk", "Screwdriver", 26500, { RefinedMetal = 1, WoodLog = 3 }, remove = 25000 },
    { "Table", "Screwdriver", 28500, { RefinedMetal = 1, WoodLog = 4 }, remove = 25000 },
    { "Barstool", "Screwdriver", 22500, { RefinedMetal = 1, WoodLog = 2, Clothes = 1 }, remove = 22000 },
    { "SmallTable", "Screwdriver", 22500, { WoodLog = 4 }, remove = 22000 },
    -- a key copy: the cut key stays and the new key takes its data (upstream locksmith.pwn OnPlayerConstructed)
    { "Key", "Screwdriver", 18500, { Key = 1, Motor = 1 }, { Key = 1 }, tweak = false, copyData = "Key" },
    { "LargeFrame", "Sledgehammer", 30000, { RefinedMetal = 4 }, remove = 22000, defence = "horizontal" },
}
for _, g in ipairs(GROUND) do
    local r = { name = g[1], kind = "ground", tool = g[2], buildTime = g[3], result = { uname = g[1], count = 1 } }
    r.ingredients = ingredientRows(g[4], g[5])
    r.tweak, r.defence, r.copyData = g.tweak, g.defence, g.copyData
    if g.remove then
        r.removalTool, r.removalTime = "Crowbar", g.remove
    end
    addRecipe(r)
end

-- 3. Items created with a workbench (SetConstructionSetWorkbench): { result, tool, consumed }. Upstream passes each a
-- build time but workbench.pwn never reads it: the hold is 3.6 s per item on the bench (M.workbenchTime).
local WORKBENCH = {
    { "IedBomb", "Screwdriver", { FireworkBox = 1, PowerSupply = 1 } },
    { "TntTimebomb", "Screwdriver", { Explosive = 1, Timer = 1 } },
    { "TntTripMine", "Screwdriver", { Explosive = 1, Accelerometer = 1 } },
    { "TntProxMine", "Screwdriver", { Explosive = 1, MotionSense = 1 } },
    { "TntPhoneBomb", "Screwdriver", { Explosive = 1, MobilePhone = 1 } },
    { "IedTimebomb", "Screwdriver", { IedBomb = 1, Timer = 1 } },
    { "IedTripMine", "Screwdriver", { IedBomb = 1, Accelerometer = 1 } },
    { "IedProxMine", "Screwdriver", { IedBomb = 1, MotionSense = 1 } },
    { "IedPhoneBomb", "Screwdriver", { IedBomb = 1, MobilePhone = 1 } },
    { "EmpTimebomb", "Screwdriver", { Fluctuator = 1, Timer = 1 } },
    { "EmpTripMine", "Screwdriver", { Fluctuator = 1, Accelerometer = 1 } },
    { "EmpProxMine", "Screwdriver", { Fluctuator = 1, MotionSense = 1 } },
    { "EmpPhoneBomb", "Screwdriver", { Fluctuator = 1, MobilePhone = 1 } },
    { "PowerSupply", "Screwdriver", { Battery = 1, Fusebox = 1 } },
    { "StorageUnit", "Screwdriver", { Timer = 1, HardDrive = 1 } },
    { "Fluctuator", "Screwdriver", { StunGun = 1, RadioPole = 1 } },
    { "IoUnit", "Screwdriver", { MobilePhone = 1, Keypad = 1 } },
    { "FluxCap", "Screwdriver", { PowerSupply = 1, Fluctuator = 1 } },
    { "DataInterface", "Screwdriver", { StorageUnit = 1, IoUnit = 1 } },
    { "HackDevice", "Screwdriver", { FluxCap = 1, DataInterface = 1 } },
    { "Motor", "Screwdriver", { PowerSupply = 1, Timer = 1 } },
    { "LocksmithKit", "Screwdriver", { Key = 1, Motor = 1 } },
    { "StarterMotor", "Screwdriver", { Motor = 1, Fluctuator = 1 } },
    { "AdvancedKeypad", "Screwdriver", { IoUnit = 1, PowerSupply = 1 } },
    { "Locator", "Screwdriver", { MobilePhone = 1, RadioPole = 1, DataInterface = 1, PowerSupply = 1 } },
    { "MetalFrame", "Hammer", { RefinedMetal = 4 } },
    { "Canister", "Hammer", { MetalFrame = 1, RefinedMetal = 2 } },
    { "LockBreaker", "Screwdriver", { LocksmithKit = 1, FluxCap = 1, RefinedMetal = 2, PowerSupply = 1 } },
}
for _, w in ipairs(WORKBENCH) do
    local r = { name = w[1], kind = "workbench", tool = w[2], ingredients = ingredientRows(w[3]) }
    r.result = { uname = w[1], count = 1 }
    addRecipe(r)
end

-- how many of each item type a recipe takes, kept ones included: { uname = n }
local function totals(r)
    local out = {}
    for _, ing in ipairs(r.ingredients) do
        out[ing.uname] = (out[ing.uname] or 0) + ing.count
    end
    return out
end

local function itemCount(r)
    local n = 0
    for _, ing in ipairs(r.ingredients) do
        n = n + ing.count
    end
    return n
end

function M.matchCombine(unameA, unameB)
    if not unameA or not unameB then
        return nil
    end
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "combine" and #r.ingredients == 2 then
            local i1, i2 = r.ingredients[1], r.ingredients[2]
            if i1.uname == unameA and i2.uname == unameB then
                return { recipe = r, consumeA = not i1.keep, consumeB = not i2.keep }
            elseif i1.uname == unameB and i2.uname == unameA then
                return { recipe = r, consumeA = not i2.keep, consumeB = not i1.keep }
            end
        end
    end
    return nil
end

local function hasIngredients(availableCounts, r)
    for uname, n in pairs(totals(r)) do
        if (availableCounts[uname] or 0) < n then
            return false
        end
    end
    return true
end

-- Upstream takes every item in reach and needs them to be exactly one set; the port reaches 2.5 m, so stray items
-- nearby are allowed and the set that uses the most of what lies there comes first (4 logs and a Refined Metal make a
-- Table, not a Desk), ties in definition order.
function M.matchGround(availableCounts, toolUname)
    local matches = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "ground" and r.tool == toolUname and hasIngredients(availableCounts, r) then
            matches[#matches + 1] = r
        end
    end
    local order = {}
    for i, r in ipairs(matches) do
        order[r] = i
    end
    table.sort(matches, function(a, b)
        local na, nb = itemCount(a), itemCount(b)
        if na ~= nb then
            return na > nb
        end
        return order[a] < order[b]
    end)
    return matches
end

-- the workbench's contents must be exactly one set (upstream _craft_FindCraftset), and the held item its tool
function M.matchWorkbench(containerCounts, toolUname)
    local matches = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "workbench" and r.tool == toolUname then
            local need, exact = totals(r), true
            for uname, n in pairs(containerCounts) do
                if need[uname] ~= n then
                    exact = false
                end
            end
            if exact and hasIngredients(containerCounts, r) then
                matches[#matches + 1] = r
            end
        end
    end
    return matches
end

-- upstream workbench.pwn: GetPlayerSkillTimeModifier(playerid, itemcount * 3600, uniqueid)
function M.workbenchTime(r)
    return itemCount(r) * 3600
end

-- The tools the ground recipes are built with, as a set: { Hammer = true, ... }.
function M.groundTools()
    local out = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "ground" and r.tool then
            out[r.tool] = true
        end
    end
    return out
end

function M.deconstructables(toolUname)
    local out = {}
    for _, r in ipairs(M.RECIPES) do
        if r.removalTool and (not toolUname or r.removalTool == toolUname) then
            out[#out + 1] = r.result.uname
        end
    end
    return out
end

-- Taking a constructed item down gives back every ingredient that was used up building it, one row per item; the
-- kept ones never left the builder (upstream craft-construct.pwn OnHoldActionFinish).
function M.getDeconstructInfo(productUname, toolUname)
    for _, r in ipairs(M.RECIPES) do
        if r.result.uname == productUname and r.removalTool then
            if not toolUname or r.removalTool == toolUname then
                local back = {}
                for _, ing in ipairs(r.ingredients) do
                    for _ = 1, ing.keep and 0 or ing.count do
                        back[#back + 1] = { uname = ing.uname, count = 1 }
                    end
                end
                return { recipe = r, tool = r.removalTool, duration = r.removalTime, ingredients = back }
            end
        end
    end
    return nil
end

return M
