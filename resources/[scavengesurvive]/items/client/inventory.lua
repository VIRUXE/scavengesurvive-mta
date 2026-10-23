-- The inventory, bag and trunk dialogs (inventory-dialog.inc / container-dialog.inc through the ui resource) and
-- the action-text messages the server sends.
return function(ctx)
    local ammo = ctx and ctx.ammo
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
        WEAPNOAMMOL = "There is no ammo loaded in this weapon",
        WEAPAUNLOAD = "Weapon is already unloaded",
        AMWRONGCALI = "Calibre does not match weapon",
        AMDIFFATYPE = "Ammo type does not match weapon's loaded ammo",
        AMMIXINTINS = "You cannot mix two ammo types in one tin",
        CUFFED = "Handcuffed player",
        UNCUFFED = "Removed handcuffs",
        DISARMED = "Disarmed player",
        -- Vehicles
        TRUNKLOCKED = "Trunk is locked",
        NO_TRUNK = "This vehicle has no trunk",
        DOORLOCKED = "Door is locked",
        LOCKUSECROW = "This vehicle is locked, maybe you could break it with a crowbar",
        LOCKCUSTOML = "This vehicle has a custom lock, you need a key to open it",
        LOCKBREAKNO = "This lock is reinforced, a crowbar will not work",
        LOCKNODOORS = "This vehicle does not have doors to lock",
        LOCKALREADY = "This vehicle already has a lock",
        LOCKVNOLOCK = "This vehicle does not have a lock",
        LOCKKEYNCUT = "This key is not cut for any lock",
        LOCKKEYNFIT = "This key does not fit this lock",
        NEEDANOTOOL = "You need another tool to continue repairing this vehicle",
        LOCKED = "Vehicle locked",
        UNLOCKED = "Vehicle unlocked",
        LOCKBROKEN = "Lock broken",
        KEY_CRAFTED = "Key crafted",
        REFUELLED = "Refuelled",
        REPAIRED = "Vehicle repaired",
        TANKFULL = "Tank is full",
        EMPTY = "Empty",
        NO_FUEL = "Out of fuel",
        ENGINE_BROKEN = "Engine is broken",
        ENGINE_STALL = "Engine stalled",
        NO_HITCH = "This vehicle has no trailer hitch",
        NO_TRAILER_NEAR = "No trailer in range",
        TRAILER_ATTACHED = "Trailer attached",
        TRAILER_DETACHED = "Trailer detached",
        VEH_FULL_REPAIR = "Vehicle is already fully repaired",
    }
    local view = "inventory" -- which dialog is up: "inventory", "bag" or "trunk"
    local last = nil -- the last payload, re-rendered when the view switches

    addEventHandler("onClientItemsHeld", root, function()
        -- the dialog's contents depend on the hand (Equip empties a slot): ask for a fresh one
        if exports.ui:listIsOpen() then
            triggerServerEvent("onItemsRequestOpenInventory", localPlayer)
        end
    end)

    addEventHandler("onClientItemsToast", root, function(code)
        local n = type(code) == "string" and code:match("^AMTRANS:(%d+)$")
        local msg = n and string.format("Transferred %d rounds", tonumber(n) or 0) or MESSAGES[code] or tostring(code)
        exports.ui:actionTextShow(msg, 3000)
    end)

    local function itemType(uname)
        return exports.data:itemType(uname)
    end

    local function calibreName(cal)
        return exports.data:calibreName(cal)
    end

    local function defaultAmmo(cal)
        local list = cal and exports.data:ammoTypesForCalibre(cal)
        return list and list[1] or nil
    end

    local function formatLabel(t, it)
        local name = t and t.name or it.uname
        if ammo and t then
            local defA = t.categoryData and defaultAmmo(t.categoryData.calibre) or nil
            name = ammo.displayName(t, it.data, itemType, calibreName, defA)
        end
        return string.format("[%02d]%s", t and t.size or 1, name)
    end

    -- "[%02d]%s": the type size then the name, one "<Empty>" per free slot
    local function rowsFor(list, cap)
        local rows = {}
        for _, it in ipairs(list or {}) do
            local t = itemType(it.uname)
            rows[#rows + 1] = {
                id = it.id,
                label = formatLabel(t, it),
                actions = { { id = "take", label = "Equip" }, { id = "use", label = "Use" } },
            }
        end
        for _ = 1, math.max(0, (cap.size or 0) - (cap.used or 0)) do
            rows[#rows + 1] = { label = "<Empty>", empty = true }
        end
        return rows
    end

    local function bagName(p)
        local uname = p.capacity and p.capacity.bag and p.capacity.bag.uname
        local t = uname and itemType(uname)
        return t and t.name or "Bag"
    end

    local function open(p)
        local title, rows
        local bname = bagName(p)
        local tname = p.capacity and p.capacity.trunk and p.capacity.trunk.uname or "Trunk"
        if view == "trunk" and p.trunk then
            title = string.format("%s (%d/%d)", tname, p.capacity.trunk.used, p.capacity.trunk.size)
            rows = rowsFor(p.trunk, p.capacity.trunk)
            rows[#rows + 1] = { id = "nav:inventory", label = "My Inventory >" }
        elseif view == "bag" and p.bag then
            title = string.format("%s (%d/%d)", bname, p.capacity.bag.used, p.capacity.bag.size)
            rows = rowsFor(p.bag, p.capacity.bag)
            rows[#rows + 1] = { id = "nav:inventory", label = "My Inventory >" }
        else
            view = "inventory"
            title = string.format("Inventory (%d/%d)", p.capacity.inv.used, p.capacity.inv.size)
            rows = rowsFor(p.inventory, p.capacity.inv)
            if p.bag then
                rows[#rows + 1] = { id = "nav:bag", label = bname .. " >" }
            end
            if p.trunk then
                rows[#rows + 1] = { id = "nav:trunk", label = tname .. " >" }
            end
        end
        exports.ui:listOpen("inventory", title, rows)
    end

    addEventHandler("onClientItemsInventory", root, function(p)
        last = p
        if p.trunk and view ~= "inventory" and view ~= "bag" then
            view = "trunk"
        elseif not p.trunk and view == "trunk" then
            view = "inventory"
        end
        open(p)
    end)

    addEventHandler("onClientUiListAction", root, function(listId, rowId, actionId)
        if listId ~= "inventory" then
            return
        end
        if actionId == "select" then
            if rowId == "nav:bag" then
                view = "bag"
            elseif rowId == "nav:trunk" then
                view = "trunk"
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
            if last and last.trunk then
                triggerServerEvent("onVehiclesRequestCloseTrunk", localPlayer)
            end
            view = "inventory"
            last = nil
        end
    end)
end
