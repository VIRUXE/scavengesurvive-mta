-- Crafting holds (the progress bar, broken by walking off or dying) and upstream's /recipes book
-- (player/recipes.pwn): combination, construction and workbench recipes, each with its tool and ingredients.
local activeAction = nil
local lastPos = nil

local function cancelAction(tellServer)
    if activeAction then
        activeAction = nil
        lastPos = nil
        exports.ui:progressCancel()
        if tellServer then
            triggerServerEvent("craftHoldCancelled", localPlayer)
        end
    end
end

addEventHandler("craftHoldStarted", root, function(label, durationMs)
    activeAction = label
    local x, y, z = getElementPosition(localPlayer)
    lastPos = { x = x, y = y, z = z }
    exports.ui:progressStart(label, durationMs)
end)

addEventHandler("craftHoldStopped", root, function()
    cancelAction(false)
end)

addEventHandler("onClientRender", root, function()
    if not activeAction or not lastPos then
        return
    end
    if isPedDead(localPlayer) then
        return cancelAction(true)
    end
    local x, y, z = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, lastPos.x, lastPos.y, lastPos.z) > 0.8 then
        cancelAction(true)
    end
end)

-- /recipes ------------------------------------------------------------------------------------------------------

local KINDS = {
    { kind = "combine", label = "Combination Recipes" },
    { kind = "construct", label = "Construction Recipes" },
    { kind = "workbench", label = "Workbench Recipes" },
}

local HELP = {
    "Crafting is a way to create new items from existing items.",
    "There are three ways to combine items in Scavenge and Survive:",
    "In inventory screens (combining): select 'Combine...' from an item's options, then 'Combine with ...' on",
    "another item. If a recipe needs more than two items, just repeat.",
    "On the ground (constructing): place all the ingredients on the ground, hold the recipe's tool and press",
    "the interact key close to them.",
    "At a workbench: place all the ingredients in the workbench, hold the recipe's tool and press the interact",
    "key at the workbench.",
}

local YELLOW, GREEN = { 255, 255, 0 }, { 51, 170, 51 }

local function typeName(uname)
    local t = exports.data:itemType(uname)
    return t and t.name ~= "" and t.name or uname
end

local function showKinds()
    local rows = {}
    for _, k in ipairs(KINDS) do
        rows[#rows + 1] = { id = "kind:" .. k.kind, label = k.label }
    end
    rows[#rows + 1] = { id = "help", label = "Help", colour = GREEN }
    exports.ui:listOpen("recipes", "Recipes", rows)
end

local function showKind(kind)
    local rows = {}
    for i, r in ipairs(exports.data:recipes()) do
        if r.kind == kind then
            rows[#rows + 1] = { id = "set:" .. i, label = string.format("%d. %s", i - 1, typeName(r.result)) }
        end
    end
    rows[#rows + 1] = { id = "back", label = "< Back" }
    exports.ui:listOpen("recipes", "Craftsets", rows)
end

local function showSet(index)
    local r = exports.data:recipes()[index]
    if not r then
        return
    end
    local rows = {}
    if r.tool then
        rows[#rows + 1] = { id = "info", label = "Tool: " .. typeName(r.tool), colour = YELLOW }
    end
    rows[#rows + 1] = { id = "info", label = "Ingredients:" }
    for _, ing in ipairs(r.ingredients) do
        rows[#rows + 1] = { id = "info", label = "    " .. typeName(ing.uname), colour = YELLOW }
    end
    rows[#rows + 1] = { id = "kind:" .. r.kind, label = "< Back" }
    exports.ui:listOpen("recipes", typeName(r.result), rows)
end

local function showHelp()
    local rows = {}
    for _, line in ipairs(HELP) do
        rows[#rows + 1] = { id = "info", label = line }
    end
    rows[#rows + 1] = { id = "back", label = "< Back" }
    exports.ui:listOpen("recipes", "Crafting Help", rows)
end

addEventHandler("uiListActionSelected", root, function(listId, rowId, actionId)
    if listId ~= "recipes" or actionId ~= "select" then
        return
    end
    local kind = rowId:match("^kind:(%a+)$")
    local set = tonumber(rowId:match("^set:(%d+)$"))
    if kind then
        showKind(kind)
    elseif set then
        showSet(set)
    elseif rowId == "help" then
        showHelp()
    elseif rowId == "back" then
        showKinds()
    end
end)

addCommandHandler("recipes", showKinds)
