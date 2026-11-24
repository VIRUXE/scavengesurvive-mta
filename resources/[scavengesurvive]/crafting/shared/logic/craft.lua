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

-- lang:begin
local NOTES = {
    padlockKey = "Gives the padlock a new lock and you its key. The kit is kept; an older key no longer fits.",
    lockChain = "The padlock needs its key first. The lock locks a bike or other doorless vehicle, "
        .. "and the padlock's key opens it.",
    comboChain = "The padlock has to be open. Set a code you'll remember on it first: the lock locks a bike or "
        .. "other doorless vehicle, and only that code opens it.",
}
-- the numbered steps the /recipes window shows (M.steps)
local STEPS = {
    combine = "Equip the %s, then choose Combine on the %s in your inventory.",
    hold = "Hold the %s.",
    drop = "Drop the items above on the ground, close together.",
    holdF = "Stand next to them and hold [F] for about %d seconds.",
    findBench = "Find a Workbench, or build one (see Construction).",
    fillBench = "Put only the items above in the Workbench.",
    benchF = "Stand at the Workbench and hold [F] for about %d seconds.",
}
-- lang:end

-- 1. Items created by hand: { result, consumed, kept, data = result data, note = text for the recipe page,
-- rekey = a kept ingredient that gets a new lock code the result (a Key) is cut to, copyData = the ingredient whose
-- lock code the result takes }
local COMBINE = {
    { "ParaBag", { Parachute = 1 }, { Knife = 1 } },
    { "MolotovEmpty", { Bottle = 1, Bandage = 1 } },
    { "Bandage", { Clothes = 1 }, { Knife = 1 } },
    -- upstream locksmith.pwn cut the Lock and Chain itself with the kit; the port builds it from a Chain and a Padlock
    -- the kit has keyed, so its key is the padlock's
    { "Key", nil, { LocksmithKit = 1, Padlock = 1 }, rekey = "Padlock", note = NOTES.padlockKey },
    { "WheelLock", { Chain = 1, Padlock = 1 }, copyData = "Padlock", note = NOTES.lockChain },
    -- the combination padlock goes on open (its shackle through the end links) and carries its code to the chain
    { "ComboLockChain", { Chain = 1, ComboPadlock = 1 }, copyData = "ComboPadlock", note = NOTES.comboChain },
    -- upstream's Bottle + Bottle keeps both and makes a third: the liquid merge it stood for is commented out in
    -- liquid-container.pwn, so all it does there is duplicate bottles; not ported
}
for _, c in ipairs(COMBINE) do
    local r = { name = c[1], kind = "combine", ingredients = ingredientRows(c[2], c[3]) }
    r.result = { uname = c[1], count = 1, data = c.data }
    r.note, r.rekey, r.copyData = c.note, c.rekey, c.copyData
    addRecipe(r)
end

-- 2. Items created by using a tool on them in the world (SetCraftSetConstructible): { result, tool, build ms,
-- consumed, kept, remove = Crowbar ms, tweak, defence }. Every removal tool upstream is the Crowbar; a set without
-- one cannot be taken down. Upstream gives the RefineMachine the ScrapMachine's very parts, so the ScrapMachine always
-- won and no RefineMachine could be built; here it takes a Metal Panel as well (2026-10-30), a fifth item, which also
-- tells the two apart under upstream's exact-count match.
local MACHINE = { Canister = 1, Motor = 1, Fluctuator = 1, PowerSupply = 1 }
local REFINER = { Canister = 1, Motor = 1, Fluctuator = 1, PowerSupply = 1, MetPanel = 1 }
local POLE = { Canister = 1, RadioPole = 1, Fluctuator = 1, PowerSupply = 1 }
local GROUND = {
    { "Campfire", "FireLighter", 5000, { WoodLog = 3 }, tweak = false },
    { "PlotPole", "Screwdriver", 20000, POLE, remove = 30000, tweak = false },
    { "ScrapMachine", "Screwdriver", 30000, MACHINE, remove = 25000 },
    { "RefineMachine", "Screwdriver", 30000, REFINER, remove = 25000 },
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
    { "Explosive", "Screwdriver", { Dynamite = 3 } }, -- port recipe: upstream Dynamite had no use
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

-- which ingredient of a two-item combine goes in the hand and which is picked in the inventory: the kept tool is
-- held, else the first by name; the server matches either way round
function M.combineOrder(r)
    local a, b = r.ingredients[1], r.ingredients[2]
    if b and b.keep and not a.keep then
        return b.uname, a.uname
    end
    return a.uname, b and b.uname
end

-- How to make a recipe, as numbered steps: { { fmt = English format, args = { { item = uname } | number, ... } } }.
-- nil for a recipe that brings its own text (the items resource's machines, cooking and gathering: r.instructions).
function M.steps(r)
    local function item(uname)
        return { item = uname }
    end
    local function seconds(ms)
        return math.max(1, math.floor(ms / 1000 + 0.5))
    end
    if r.kind == "combine" and #r.ingredients == 2 then
        local held, other = M.combineOrder(r)
        return { { fmt = STEPS.combine, args = { item(held), item(other) } } }
    elseif r.kind == "ground" then
        return {
            { fmt = STEPS.drop, args = {} },
            { fmt = STEPS.hold, args = { item(r.tool) } },
            { fmt = STEPS.holdF, args = { seconds(r.buildTime) } },
        }
    elseif r.kind == "workbench" then
        return {
            { fmt = STEPS.findBench, args = {} },
            { fmt = STEPS.fillBench, args = {} },
            { fmt = STEPS.hold, args = { item(r.tool) } },
            { fmt = STEPS.benchF, args = { seconds(M.workbenchTime(r)) } },
        }
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

-- a workbench set laid out on the ground with its tool in hand: upstream workbench.pwn OnPlayerConstruct refuses it
-- with NEEDWORKBE; nil when no workbench set lies there
function M.matchNeedsWorkbench(availableCounts, toolUname)
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "workbench" and r.tool == toolUname and hasIngredients(availableCounts, r) then
            return r
        end
    end
    return nil
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

-- The recipes of one kind ("combine", "ground", "workbench") in definition order.
function M.ofKind(kind)
    local out = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == kind then
            out[#out + 1] = r
        end
    end
    return out
end

-- A recipe's ingredients as text lines ("3x Wood Log", "Knife (kept)"); nameOf maps an item uname to its name,
-- keptWord is "kept" in the reader's language.
function M.ingredientLines(r, nameOf, keptWord)
    local lines = {}
    for _, ing in ipairs(r.ingredients) do
        local name = nameOf(ing.uname)
        local line = ing.count > 1 and (ing.count .. "x " .. name) or name
        lines[#lines + 1] = ing.keep and (line .. " (" .. (keptWord or "kept") .. ")") or line
    end
    return lines
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
