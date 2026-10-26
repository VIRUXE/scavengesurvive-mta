-- Pure recipe matching logic for in-hand combining, ground construction, and workbench crafting.
-- Ported from upstream Scavenge & Survive (core/server/init.pwn, core/world/craft-construct.pwn).
local M = { RECIPES = {}, byName = {} }

local function addRecipe(r)
    M.RECIPES[#M.RECIPES + 1] = r
    M.byName[r.name] = r
end

-- 1. In-Hand Combine Recipes
addRecipe({
    name = "Bandage",
    kind = "combine",
    ingredients = {
        { uname = "Knife", count = 1, keep = true },
        { uname = "Clothes", count = 1, keep = false },
    },
    result = { uname = "Bandage", count = 1 },
})

addRecipe({
    name = "MolotovEmpty",
    kind = "combine",
    ingredients = {
        { uname = "Bottle", count = 1, keep = false },
        { uname = "Bandage", count = 1, keep = false },
    },
    result = { uname = "MolotovEmpty", count = 1 },
})

addRecipe({
    name = "ParaBag",
    kind = "combine",
    ingredients = {
        { uname = "Knife", count = 1, keep = true },
        { uname = "Parachute", count = 1, keep = false },
    },
    result = { uname = "ParaBag", count = 1 },
})

-- 2. Ground Construction Recipes
addRecipe({
    name = "Campfire",
    kind = "ground",
    tool = "FireLighter",
    buildTime = 3000,
    ingredients = {
        { uname = "WoodLog", count = 2, keep = false },
    },
    result = { uname = "Campfire", count = 1 },
    removalTool = "Crowbar",
    removalTime = 3000,
    deconstructIngredients = {
        { uname = "WoodLog", count = 1 },
    },
})

addRecipe({
    name = "Barricade",
    kind = "ground",
    tool = "Hammer",
    buildTime = 4000,
    ingredients = {
        { uname = "WoodLog", count = 3, keep = false },
    },
    result = { uname = "Barricade", count = 1 },
    removalTool = "Crowbar",
    removalTime = 5000,
    deconstructIngredients = {
        { uname = "WoodLog", count = 2 },
    },
})

addRecipe({
    name = "SmallBox",
    kind = "ground",
    tool = "Hammer",
    buildTime = 4000,
    ingredients = {
        { uname = "WoodLog", count = 2, keep = false },
    },
    result = { uname = "SmallBox", count = 1 },
    removalTool = "Crowbar",
    removalTime = 5000,
    deconstructIngredients = {
        { uname = "WoodLog", count = 1 },
    },
})

addRecipe({
    name = "Workbench",
    kind = "ground",
    tool = "Hammer",
    buildTime = 8000,
    ingredients = {
        { uname = "WoodLog", count = 2, keep = false },
        { uname = "CorPanel", count = 2, keep = false },
    },
    result = { uname = "Workbench", count = 1 },
    removalTool = "Crowbar",
    removalTime = 8000,
    deconstructIngredients = {
        { uname = "WoodLog", count = 1 },
        { uname = "CorPanel", count = 1 },
    },
})

addRecipe({
    name = "LargeFrame",
    kind = "ground",
    tool = "Hammer",
    buildTime = 6000,
    ingredients = {
        { uname = "CorPanel", count = 4, keep = false },
    },
    result = { uname = "LargeFrame", count = 1 },
    removalTool = "Crowbar",
    removalTime = 10000,
    deconstructIngredients = {
        { uname = "CorPanel", count = 2 },
    },
})

addRecipe({
    name = "Door",
    kind = "ground",
    tool = "Screwdriver",
    buildTime = 5000,
    ingredients = {
        { uname = "LargeFrame", count = 1, keep = false },
        { uname = "CrateDoor", count = 1, keep = false },
    },
    result = { uname = "Door", count = 1 },
    removalTool = "Crowbar",
    removalTime = 8000,
    deconstructIngredients = {
        { uname = "LargeFrame", count = 1 },
        { uname = "CrateDoor", count = 1 },
    },
})

addRecipe({
    name = "MetalGate",
    kind = "ground",
    tool = "Wrench",
    buildTime = 6000,
    ingredients = {
        { uname = "LargeFrame", count = 1, keep = false },
        { uname = "MetalFrame", count = 1, keep = false },
    },
    result = { uname = "MetalGate", count = 1 },
    removalTool = "Crowbar",
    removalTime = 10000,
    deconstructIngredients = {
        { uname = "LargeFrame", count = 1 },
        { uname = "MetalFrame", count = 1 },
    },
})

addRecipe({
    name = "PlotPole",
    kind = "ground",
    tool = "Screwdriver",
    buildTime = 8000,
    ingredients = {
        { uname = "CorPanel", count = 2, keep = false },
        { uname = "Battery", count = 1, keep = false },
    },
    result = { uname = "PlotPole", count = 1 },
    removalTool = "Crowbar",
    removalTime = 15000,
    deconstructIngredients = {
        { uname = "CorPanel", count = 1 },
        { uname = "Battery", count = 1 },
    },
})

-- 3. Workbench Recipes (crafted in Workbench 16-slot container)
addRecipe({
    name = "Keypad",
    kind = "workbench",
    tool = "Screwdriver",
    buildTime = 5000,
    ingredients = {
        { uname = "Battery", count = 1, keep = false },
        { uname = "CorPanel", count = 1, keep = false },
    },
    result = { uname = "Keypad", count = 1 },
})

addRecipe({
    name = "AdvancedKeypad",
    kind = "workbench",
    tool = "Screwdriver",
    buildTime = 5000,
    ingredients = {
        { uname = "Keypad", count = 1, keep = false },
        { uname = "Battery", count = 1, keep = false },
    },
    result = { uname = "AdvancedKeypad", count = 1 },
})

addRecipe({
    name = "LocksmithKit",
    kind = "workbench",
    tool = "Wrench",
    buildTime = 6000,
    ingredients = {
        { uname = "CorPanel", count = 1, keep = false },
        { uname = "Screwdriver", count = 1, keep = false },
        { uname = "Hammer", count = 1, keep = false },
    },
    result = { uname = "LocksmithKit", count = 1 },
})

addRecipe({
    name = "LockBreaker",
    kind = "workbench",
    tool = "Wrench",
    buildTime = 6000,
    ingredients = {
        { uname = "Crowbar", count = 1, keep = false },
        { uname = "Battery", count = 1, keep = false },
    },
    result = { uname = "LockBreaker", count = 1 },
})

addRecipe({
    name = "HackDevice",
    kind = "workbench",
    tool = "Screwdriver",
    buildTime = 8000,
    ingredients = {
        { uname = "Keypad", count = 1, keep = false },
        { uname = "Battery", count = 1, keep = false },
    },
    result = { uname = "HackDevice", count = 1 },
})

addRecipe({
    name = "Shield",
    kind = "workbench",
    tool = "Hammer",
    buildTime = 6000,
    ingredients = {
        { uname = "CorPanel", count = 2, keep = false },
        { uname = "WoodLog", count = 1, keep = false },
    },
    result = { uname = "Shield", count = 1 },
})

addRecipe({
    name = "Armour",
    kind = "workbench",
    tool = "Hammer",
    buildTime = 8000,
    ingredients = {
        { uname = "CorPanel", count = 3, keep = false },
        { uname = "Clothes", count = 2, keep = false },
    },
    result = { uname = "Armour", count = 1 },
})

addRecipe({
    name = "Backpack",
    kind = "workbench",
    tool = "Knife",
    buildTime = 5000,
    ingredients = {
        { uname = "Clothes", count = 3, keep = false },
    },
    result = { uname = "Backpack", count = 1 },
})

addRecipe({
    name = "Rucksack",
    kind = "workbench",
    tool = "Knife",
    buildTime = 7000,
    ingredients = {
        { uname = "Clothes", count = 5, keep = false },
    },
    result = { uname = "Rucksack", count = 1 },
})

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

local function hasIngredients(availableCounts, recipeIngredients)
    for _, ing in ipairs(recipeIngredients) do
        local have = availableCounts[ing.uname] or 0
        if have < ing.count then
            return false
        end
    end
    return true
end

function M.matchGround(availableCounts, toolUname)
    local matches = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "ground" then
            if (not r.tool or r.tool == toolUname) and hasIngredients(availableCounts, r.ingredients) then
                matches[#matches + 1] = r
            end
        end
    end
    return matches
end

function M.matchWorkbench(containerCounts, toolUname)
    local matches = {}
    for _, r in ipairs(M.RECIPES) do
        if r.kind == "workbench" then
            if (not r.tool or r.tool == toolUname) and hasIngredients(containerCounts, r.ingredients) then
                matches[#matches + 1] = r
            end
        end
    end
    return matches
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

function M.getDeconstructInfo(productUname, toolUname)
    for _, r in ipairs(M.RECIPES) do
        if r.result.uname == productUname and r.removalTool then
            if not toolUname or r.removalTool == toolUname then
                return {
                    recipe = r,
                    tool = r.removalTool,
                    duration = r.removalTime or 5000,
                    ingredients = r.deconstructIngredients or {},
                }
            end
        end
    end
    return nil
end

return M
