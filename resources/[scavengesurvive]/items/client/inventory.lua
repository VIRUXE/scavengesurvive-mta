-- The inventory and bag dialogs (inventory-dialog.inc / container-dialog.inc through the ui resource) and the
-- action-text messages the server sends. The hand is not listed: upstream shows it in the gear tiles, and the
-- held item is used, put away or dropped with the keys.
return function()
    local MESSAGES = {
        HANDS_FULL = "You are already holding an item",
        NOT_IN_WORLD = "It is gone",
        CONTAINER_FULL = "Extra slots required",
        PUT_AWAY = "Put away",
        BAG_WORN = "You put on the bag",
        BAG_SLOT_USED = "You already wear a bag",
        NOT_HELD = "Nothing in hand",
        ATE = "You ate it",
        DB_ERROR = "Server error",
        NOT_OWNER = "Not yours",
        NOT_OWNED = "Not yours",
        NOT_IN_CONTAINER = "It is not there any more",
        SELF_CONTAINMENT = "It does not fit inside itself",
    }
    local view = "inventory" -- which dialog is up: "inventory" or "bag"
    local last = nil -- the last payload, re-rendered when the view switches

    addEventHandler("onClientItemsHeld", root, function()
        -- the dialog's contents depend on the hand (Equip empties a slot): ask for a fresh one
        if exports.ui:listIsOpen() then
            triggerServerEvent("onItemsRequestOpenInventory", localPlayer)
        end
    end)

    addEventHandler("onClientItemsToast", root, function(code)
        exports.ui:actionTextShow(MESSAGES[code] or tostring(code), 3000)
    end)

    local function itemType(uname)
        return exports.data:itemType(uname)
    end

    -- "[%02d]%s": the type size then the name, one "<Empty>" per free slot
    local function rowsFor(list, cap)
        local rows = {}
        for _, it in ipairs(list or {}) do
            local t = itemType(it.uname)
            rows[#rows + 1] = {
                id = it.id,
                label = string.format("[%02d]%s", t and t.size or 1, t and t.name or it.uname),
                actions = { { id = "take", label = "Equip" }, { id = "use", label = "Use" } },
            }
        end
        for _ = 1, math.max(0, (cap.size or 0) - (cap.used or 0)) do
            rows[#rows + 1] = { label = "<Empty>", empty = true }
        end
        return rows
    end

    local function open(p)
        local title, rows
        if view == "bag" and p.bag then
            title = string.format("Bag (%d/%d)", p.capacity.bag.used, p.capacity.bag.size)
            rows = rowsFor(p.bag, p.capacity.bag)
            rows[#rows + 1] = { id = "nav:inventory", label = "My Inventory >" }
        else
            view = "inventory"
            title = string.format("Inventory (%d/%d)", p.capacity.inv.used, p.capacity.inv.size)
            rows = rowsFor(p.inventory, p.capacity.inv)
            if p.bag then
                rows[#rows + 1] = { id = "nav:bag", label = "Bag >" }
            end
        end
        exports.ui:listOpen("inventory", title, rows)
    end

    addEventHandler("onClientItemsInventory", root, function(p)
        last = p
        open(p)
    end)

    addEventHandler("onClientUiListAction", root, function(listId, rowId, actionId)
        if listId ~= "inventory" then
            return
        end
        if actionId == "select" then
            if rowId == "nav:bag" then
                view = "bag"
            elseif rowId == "nav:inventory" then
                view = "inventory"
            end
            if last then
                open(last)
            end
        elseif actionId == "take" then
            triggerServerEvent("onItemsRequestTake", localPlayer, rowId)
        elseif actionId == "use" then
            triggerServerEvent("onItemsRequestUse", localPlayer, rowId)
        end
    end)

    addEventHandler("onClientUiListClosed", root, function(listId)
        if listId == "inventory" then
            view = "inventory"
        end
    end)
end
