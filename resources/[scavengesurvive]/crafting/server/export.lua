-- The /recipes window as data for the Discord bot's /recipe command (docs/runbooks/discord-bridge.md): every recipe
-- the window lists (shared/logic/craft.lua, then the items resource's machines, cooking and gathering), with its
-- texts already written out in every language, goes to recipes.json in this resource's folder whenever crafting or
-- items starts, and the relay reads that file. A file for the same reasons as dashboard's live.json: no HTTP
-- export, no network, nothing a player can reach. Nothing in it changes while the resources run.
local FILE = "recipes.json"

local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=crafting/" .. path))()
end

local craft = loadModule("shared/logic/craft.lua")
local ICONS = loadModule("client/icons.lua")
local KINDS = { "combine", "ground", "workbench", "machines", "cooking", "gathering" }
-- the window's own texts (client/recipes.lua), the ones the bot shows
-- lang:begin
local KIND_NAMES = {
    combine = "Combination",
    ground = "Construction",
    workbench = "Workbench",
    machines = "Machines",
    cooking = "Cooking",
    gathering = "Gathering",
}
local LABELS = {
    need = "You need:",
    kept = "kept",
    tool = "tool",
    place = "place",
    steps = "How to make it:",
    none = "No recipe matches.",
    removal = "Can be taken down again with a %s.",
}
-- lang:end

-- texts in a language by its code (lib's lang module works per player)
local function text(code, english)
    return exports.data:translate(code, english)
end

local function format(code, fmt, ...)
    local ok, out = pcall(string.format, text(code, fmt), ...)
    return ok and out or string.format(fmt, ...)
end

local function itemName(code, uname)
    local name = exports.data:itemName(code, uname)
    return (name and name ~= "") and name or uname
end

-- the places a recipe is made at (a machine, a cooker) are not carried
local function isPlace(r)
    return r.kind == "machines" or r.kind == "cooking"
end

local function recipesIn(code)
    local byKind = {}
    for _, kind in ipairs(KINDS) do
        byKind[kind] = craft.ofKind(kind)
    end
    for _, r in ipairs(exports.items:getProductionRecipesIn(code) or {}) do
        if byKind[r.kind] then
            table.insert(byKind[r.kind], r)
        end
    end
    local names = {}
    local function item(uname, count)
        if not names[uname] then
            names[uname] = itemName(code, uname)
        end
        return { uname = uname, name = names[uname], count = count or 1, icon = ICONS[uname] or false }
    end
    local out = {}
    for _, kind in ipairs(KINDS) do
        for _, r in ipairs(byKind[kind]) do
            local needs = {}
            for _, ing in ipairs(r.ingredients) do
                local n = item(ing.uname, ing.count)
                n.keep = ing.keep == true
                needs[#needs + 1] = n
            end
            if r.tool then
                local n = item(r.tool)
                n.tool, n.place = true, isPlace(r)
                needs[#needs + 1] = n
            end
            local steps = {}
            for i, step in ipairs(craft.steps(r) or {}) do
                local args = {}
                for j, a in ipairs(step.args) do
                    args[j] = type(a) == "table" and item(a.item).name or a
                end
                steps[i] = format(code, step.fmt, unpack(args))
            end
            out[#out + 1] = {
                id = r.name,
                kind = r.kind,
                result = item(r.result.uname, r.result.count),
                needs = needs,
                steps = steps,
                instructions = r.instructions or false,
                note = r.note and text(code, r.note) or false,
                removal = r.removalTool and format(code, LABELS.removal, item(r.removalTool).name) or false,
            }
        end
    end
    return out
end

local function write()
    local langs = {}
    for _, code in ipairs(exports.data:languages()) do
        local kinds, labels = {}, {}
        for k, v in pairs(KIND_NAMES) do
            kinds[k] = text(code, v)
        end
        for k, v in pairs(LABELS) do
            labels[k] = text(code, v)
        end
        langs[code] = { kinds = kinds, labels = labels, recipes = recipesIn(code) }
    end
    local f = fileCreate(FILE)
    if not f then
        return
    end
    -- toJSON wraps its argument in an outer array; the reader unwraps it
    fileWrite(f, toJSON({ at = getRealTime().timestamp, order = KINDS, langs = langs }, true))
    fileClose(f)
end

addEventHandler("onResourceStart", root, function(res)
    if res == getThisResource() or getResourceName(res) == "items" then
        write()
    end
end)
