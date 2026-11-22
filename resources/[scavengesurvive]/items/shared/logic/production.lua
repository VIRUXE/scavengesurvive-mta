-- luacheck: max line length 260
-- The production catalog of the recipe browser: what machines, cooking and gathering make, derived from the
-- gameplay rules. Read on the client (the /recipes window, exports.items:getProductionRecipes) and on the server
-- (the Discord copy of the window, crafting's recipe export), so it takes everything as arguments:
-- build({ tr = English text -> text in the reader's language, unames = exports.data:itemTypes() (the unames in
--         order), itemType = uname -> exports.data:itemType(uname),
--         machines, cooking, gardening, small, fishing = the logic modules })

local function build(ctx)
    local tr = ctx.tr
    -- tr's template formatted, the English one when the translation does not take the arguments (as lang.format)
    local function L(template, ...)
        if select("#", ...) == 0 then
            return tr(template)
        end
        local ok, out = pcall(string.format, tr(template), ...)
        return ok and out or string.format(template, ...)
    end
    local machines, cooking, gardening, small, fishing =
        ctx.machines, ctx.cooking, ctx.gardening, ctx.small, ctx.fishing
    local out = {}
    local function add(id, kind, result, inputs, equipment, instructions)
        out[#out + 1] = {
            name = id,
            kind = kind,
            result = { uname = result, count = 1 },
            ingredients = inputs or {},
            tool = equipment,
            instructions = instructions,
        }
    end
    local function ingredient(uname, count, keep)
        return { uname = uname, count = count or 1, keep = keep }
    end
    for uname, value in pairs(machines.SCRAP) do
        add(
            "scrap:" .. uname,
            "machines",
            machines.RESULTS.scrap,
            { ingredient(uname) },
            "ScrapMachine",
            L("Scrap value: %s. Batch output capped at %s items.", value, machines.MAX_ITEMS - 1)
        )
    end
    add(
        "refine",
        "machines",
        "RefinedMetal",
        { ingredient("ScrapMetal") },
        "RefineMachine",
        L("Each Scrap Metal produces one Refined Metal.")
    )
    add(
        "purify",
        "machines",
        "Bottle",
        { ingredient("Bottle") },
        "WaterMachine",
        L("Requires a bottle of sea water; produces purified water with the same volume.")
    )
    local machineHelp = L(
        "Load the machine, refuel with Petrol, then select Start. Uses %s fuel per input item; takes %s seconds per input plus up to %s seconds.",
        machines.FUEL_PER_ITEM,
        machines.COOK_S_PER_ITEM,
        machines.COOK_JITTER_S
    )
    for _, r in ipairs(out) do
        r.instructions = r.instructions .. "\n\n" .. machineHelp
    end
    for _, uname in ipairs(ctx.unames) do
        if cooking.canCook(ctx.itemType(uname)) then
            for _, cooker in ipairs({ "Campfire", "Barbecue" }) do
                local text = L(
                    "Place uncooked food on the lit cooker. Produces cooked food in %s seconds.",
                    tostring(cooker == "Campfire" and cooking.CAMPFIRE_COOK_S or cooking.BBQ_COOK_S)
                )
                if cooker == "Barbecue" then
                    text = text
                        .. "\n"
                        .. L(
                            "Two grill spots. Refuel with %s L Petrol for %s cooks.",
                            cooking.PETROL_PER_FILL,
                            cooking.FUEL_PER_FILL
                        )
                end
                add("cook:" .. cooker .. ":" .. uname, "cooking", uname, { ingredient(uname) }, cooker, text)
            end
        end
    end
    for i, seed in ipairs(gardening.SEEDS) do
        if seed.crop then
            add(
                "grow:" .. i,
                "gathering",
                seed.crop,
                { ingredient(gardening.BAG), ingredient(gardening.POT, 1, true) },
                "Knife",
                L(
                    "Use seeds of this crop in a Plant Pot, water it, and harvest the mature plant with a Knife. Growth: %s steps of %s seconds.",
                    seed.grows,
                    gardening.GROW_MS / 1000
                )
            )
        end
    end
    add(
        "molotov:fill",
        "combine",
        small.MOLOTOV_TO,
        { ingredient(small.MOLOTOV_FROM) },
        "GasCan",
        L("Use a Petrol Can on the empty Molotov; consumes %s L Petrol.", small.MOLOTOV_LITRES)
    )
    add(
        "fishing",
        "gathering",
        fishing.CATCH,
        {},
        fishing.ROD,
        L(
            "Cast into water. Wait %s–%s seconds before skill modifiers, then reel in. A catch is not guaranteed.",
            fishing.MIN_WAIT_MS / 1000,
            fishing.MAX_WAIT_MS / 1000
        )
    )
    -- world/shared/logic/trees.lua: a held Chainsaw fells GTA's trees, a felled one grows back after RESPAWN_S
    add(
        "fell:tree",
        "gathering",
        "WoodLog",
        {},
        "Chainsaw",
        L(
            "Hold [F] next to a tree with a fuelled Chainsaw until it falls; the Wood Logs land around the trunk. Fuel the Chainsaw at a Petrol Can on the ground. A felled tree grows back after three weeks."
        )
    )
    add(
        "harvest:meat",
        "gathering",
        "Meat",
        {},
        "Knife",
        L("Use a Knife on a Torso for 3 seconds to harvest raw meat. Each torso can be harvested once within a day.")
    )
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out
end

return { build = build }
