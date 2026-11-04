-- The inventory, bag and trunk dialogs (inventory-dialog.inc / container-dialog.inc through the ui resource) and
-- the action-text messages the server sends.
return function(ctx)
    local ammo = ctx and ctx.ammo
    local apparel = ctx and ctx.apparel
    local clothes = ctx and ctx.clothes -- shared/logic/clothes.lua: which skin a Clothes item holds
    local models = ctx and ctx.models -- client/models.lua: which model id draws an item type on this client
    local preview = ctx and ctx.preview -- client/preview.lua: live dxDrawModel3D previews inside the gear tiles
    local cooking = ctx and ctx.cooking -- shared/logic/cooking.lua: "(Cooked)" / "(Uncooked)" on food
    local small = ctx and ctx.small -- shared/logic/smallitems.lua: the Note's message and the Stun Gun's charge
    local gardening = ctx and ctx.gardening -- shared/logic/gardening.lua: what a bag of Seeds holds
    local liquids = ctx and ctx.liquids -- shared/logic/liquids.lua: "(Water 0.4/0.50)" on liquid containers
    local gas = ctx and ctx.gas -- shared/logic/gas.lua: "(6.3/11 kg)" on a Gas Bottle
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")() -- names in the player's language
    -- lang:begin
    local MESSAGES = {
        HANDS_FULL = "You are already holding an item",
        LIQUID_EMPTY = "It is empty",
        CARRY_NO_VEHICLE = "Put that down before getting in",
        NOT_IN_WORLD = "It is gone",
        CONTAINER_FULL = "Extra slots required",
        PUT_AWAY = "Put away",
        BAG_WORN = "You put on the bag",
        BAG_SLOT_USED = "You already wear a bag",
        NOT_HELD = "Nothing in hand",
        NOBODY_NEAR = "Nobody is close enough",
        TARGET_BUSY = "They cannot take it right now",
        TARGET_HANDS_FULL = "Their hands are full",
        GAVE_ITEM = "You handed it over",
        GOT_ITEM = "You were handed an item",
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
        EQUIPPED = "Equipped",
        REMOVED = "Removed",
        NOT_WEARABLE = "This item cannot be worn",
        PARABAGWORN = "You can't wear a parachute while you are wearing a bag",
        PARAWORN = "You are already wearing a parachute",
        BAGPARAWORN = "You can't wear a bag while you are wearing a parachute",
        NOT_WORN = "Nothing equipped in that slot",
        INVENTORY_FULL = "Inventory is full",
        TOO_BIG = "Too big to put away, it goes in a vehicle or a box",
        CLOTHESWRGE = "Wrong gender for clothes",
        CLOTHES_ON_DUTY = "Go off duty before changing clothes",
        -- Cooking (#95): upstream's texts where it had one
        FIRELITSTAR = "Food added\n1 minute cook time",
        BBQFOODADDE = "Food added",
        BBQALREADYC = "Food already cooked",
        BBQADDPETRO = "1L of petrol added\n10 BBQ uses",
        BBQFUELEMPT = "Needs fuel from a Petrol Can",
        BBQLITSTART = "BBQ Lit\nCook time: 30 seconds",
        PETROLEMPTY = "Petrol can empty",
        BBQ_FULL = "The grill is full",
        BBQ_LIT = "It is already lit",
        BUSY = "Something is already cooking",
        COOKING = "Still cooking",
        -- Vehicles
        TRUNKLOCKED = "Trunk is locked",
        NO_TRUNK = "This vehicle has no trunk",
        DOORLOCKED = "Door is locked",
        LOCKUSECROW = "This vehicle is locked, maybe you could break it with a crowbar",
        LOCKCUSTOML = "This vehicle has a custom lock, you need a key to open it",
        LOCKBREAKNO = "This lock is reinforced, a crowbar will not work",
        LOCKNODOORS = "This vehicle does not have doors to lock",
        LOCKALREADY = "This vehicle already has a lock",
        LOCKCHNDOOR = "A lock and chain only fits a vehicle without doors, use a Locksmith Kit",
        LOCKCHNOKEY = "That lock and chain has no key. Combine it with a Locksmith Kit.",
        LOCKCHCUT = "That lock and chain is already cut",
        LOCKVNOLOCK = "This vehicle does not have a lock",
        LOCKKEYNCUT = "This key is not cut for any lock",
        LOCKKEYNFIT = "This key does not fit this lock",
        NEEDANOTOOL = "You need another tool to continue repairing this vehicle",
        LOCKED = "Vehicle locked",
        UNLOCKED = "Vehicle unlocked",
        LOCKBROKEN = "Lock broken",
        DOORARMOURED = "The door is armoured, a crowbar will not work",
        GASB_MOUNTED = "You mounted the gas bottle",
        GASB_REMOVED = "You took the gas bottle off",
        GASB_SLOTFULL = "There is a bottle on that mount already",
        GASB_NONE = "There is no bottle on that mount",
        WELD_NOPANEL = "Attach a defence first, then weld it on with the torch",
        WELD_NOGAS = "The gas hooked up to the Welder has too little left for this defence",
        WELD_NOCYLINDER = "Hook a Gas Cylinder or Gas Bottle up to the Welder",
        HOSE_ON = "Hooked up to the Welder",
        HOSE_OFF = "Unhooked from the Welder",
        HOSE_NOWELDER = "Lay a Welder down within 2.5 metres of it first",
        WELD_NOPOWER = "The Welder needs a fuelled Generator within 8 metres",
        WELDED = "Panel welded on",
        WELD_NOSLOTS = "This vehicle takes no defences",
        WELD_TORCH = "Lay the Welder down and take its torch",
        TORCH_STOWED = "The torch went back on the Welder",
        ATTACHED = "Defence attached: weld it on to fortify",
        ATTACH_MISS = "Aim at the trailer",
        ATTACH_DOOR_ONLY = "A door only goes on the trailer's door",
        ATTACH_NOT_DOOR = "Only a door goes on the trailer's door",
        ATTACH_UNSUPPORTED = "It would hang off the trailer there",
        ATTACH_BLOCKS_DOOR = "It would block the door",
        ATTACH_CLASH = "It would hit another defence",
        ATTACH_NOT_METAL = "Only metal defences can be welded on",
        ATTACH_NOT_DEFENCE = "Hold a defence to attach it",
        ATTACH_FAR = "Get closer to where it goes",
        PRIED = "Panel pried off",
        PRY_WELDED = "A welded panel will not come off with a crowbar, grind it off with an Angle Grinder",
        GRIND_NOPANEL = "No welded panel within reach to grind",
        NO_BATTERY = "The engine won't turn over: there is no battery",
        BATTERY_FLAT = "The battery is flat",
        BONNET_LOCKED = "The bonnet is locked: unlock the vehicle first",
        NO_BATTERY_IN = "There is no battery under the bonnet",
        BATTERY_ALREADY = "There is already a battery under the bonnet",
        BONNET_SHUT = "Open the bonnet first",
        BATTERY_FITTED = "Battery fitted",
        GRIND_NOBATTERY = "The Angle Grinder needs a charged Tool Battery in your inventory or bag",
        GRIND_NODISC = "The Angle Grinder needs a Grinding Disc in your inventory or bag",
        GRIND_CUT = "The panel's welds are cut through and it comes off",
        KEY_CRAFTED = "Key crafted",
        REFUELLED = "Refuelled",
        REPAIRED = "Vehicle repaired",
        PART_NOT_HERE = "Stand by that part of an unlocked, parked vehicle with its engine off",
        PART_SLOT_TAKEN = "There is a part there already. Take it off with a Tyre Wrench first",
        PART_MISSING = "There is no part left there to take off",
        PART_WRENCH = "Hold a Tyre Wrench to take a body part off",
        PART_REMOVED = "Body part taken off",
        PART_INSTALLED = "Body part fitted loosely, tighten it with a Wrench or it will shake off",
        PART_SECURED = "Body part tightened",
        PART_FAILED = "Could not change the body part, your items are kept",
        TANKFULL = "Tank is full",
        CANFULL = "Petrol can is full",
        EMPTY = "Empty",
        NO_FUEL = "Out of fuel",
        ENGINE_BROKEN = "Engine is broken",
        ENGINE_STALL = "Engine stalled",
        TRAILER_ATTACHED = "Trailer attached",
        TRAILER_DETACHED = "Trailer detached",
        VEH_FULL_REPAIR = "Vehicle is already fully repaired",
        CONTAINER_NOT_EMPTY = "Container is not empty",
        TENT_PITCHED = "Pitched tent",
        TENT_PACKED = "Packed tent",
        TENT_NOT_EMPTY = "The tent must be empty to pack it away",
        TENT_PACKING = "Someone is packing this tent",
        PICKED_UP = "Picked up",
        CRAFTED = "Crafted",
        DECONSTRUCTED = "Deconstructed",
        NO_RECIPE = "Cannot craft these items",
        NEED_TOOL = "Missing required tool",
        KEYPAD_ALREADY = "Keypad already installed",
        KEYPAD_HACKED = "Keypad hacked",
        KEYPAD_INSTALLED = "Keypad installed",
        ACCESS_GRANTED = "Access granted",
        WRONG_PASSCODE = "Incorrect passcode",
        DOOR_OPENED = "Opened",
        DOOR_CLOSED = "Closed",
        DEFENCE_BUILT = "Defence built",
        DEFENCE_REMOVED = "Defence removed",
        DEFENCE_FRONT = "You can only remove a defence from the inside",
        DEFNOTMOVAB = "You cannot install a motor on that type of defence",
        DEFINSTMOTO = "Motor installed to defence",
        DEFNEEDMOTO = "You must install a motor before installing a keypad!",
        DEFINSTKEYP = "Keypad installed to defence",
        DEFINSTADKP = "Advanced Keypad installed to defence",
        DEFMOVINGIT = "Moving defence, please stand back.",
        DEFCODEZERO = "Leaving the code at 0 will allow the code to be set again.",
        PLOTPOLEENT = "Entering claimed territory",
        LOCATORDIS = "Unable to trace the mobile phone",
        LOCATORSYNC = "Locator synced, you can now locate the phone.",
        STUNGUNCHAR = "Stun Gun Charged",
        STUNGUNOUTC = "Out of charge",
        MOLOPOURBOT = "Fuel poured in bottle",
        FUELNOTPETR = "Fuel can does not contain petrol",
        BODYDECOMPD = "The body has decomposed too much to harvest",
        FISHFISHING = "Fishing...\nPress [F] to cancel",
        FISHLINETUG = "The line is tugging...",
        FISHNCLOSER = "You need to be closer to the water",
        FISHUNLUCKY = "Unlucky!",
        POTADDSEEDS = "Added seeds to plant pot",
        POTADDWATER = "Added 1 water to plant pot",
        POTBOTEMPTY = "Bottle is empty",
        POTBOTNOWAT = "Bottle does not contain water",
        POTHARVESTE = "Plant harvested",
        POTINVASEED = "Invalid seed type.",
        POTNOACPLNT = "Pot doesn't contain an active plant.",
        POTNOTGROWN = "The plant has not fully grown yet.",
        LOCKERFRONT = "Open the locker from the front, facing its door",
        BODYHARVEST = "The body has already been harvested of the edible (tasty) parts",
        ITEMTWKFINI = "Tweaking finished",
        ITEMTWKMOVE = "Cannot move item with players nearby",
        ITEMTWKTFAR = "Too far from original build position",
        ITEMTWKBLOC = "You are blocking an item from being built, please stand back",
        PLOTPOLEEXT = "Leaving claimed territory",
    }
    -- lang:end
    -- the gear tiles' titles (upstream's captions)
    -- lang:begin
    local SLOT_NAMES = {
        hat = "HEAD",
        mask = "FACE",
        held = "HAND",
        holster = "HOLSTER",
        armour = "TORSO",
        bag = "BACK",
    }
    -- lang:end
    local view = "inventory" -- which dialog is up: "inventory", "bag" or "trunk"
    local last = nil -- the last payload, re-rendered when the view switches
    local charStats = { hp = 100, food = 100, bleed = 0, wounds = 0 }
    local lastHitPart = nil

    addEventHandler("characterStatsSynced", root, function(s)
        if s then
            charStats = s
        end
    end)

    addEventHandler("woundInflicted", root, function(_, _, bodypart)
        lastHitPart = bodypart
    end)

    addEventHandler("heldItemChanged", root, function()
        -- the dialog's contents depend on the hand (Equip empties a slot): ask for a fresh one
        if exports.ui:listIsOpen() then
            triggerServerEvent("inventoryOpenRequested", localPlayer)
        end
    end)

    addEventHandler("toastShown", root, function(code)
        local n = type(code) == "string" and code:match("^AMTRANS:(%d+)$")
        local dist = type(code) == "string" and code:match("^DISTANCE:([%d%.]+)$")
        local ground, passes = nil, nil
        if type(code) == "string" then
            ground, passes = code:match("^GRIND_PASS:(%d+):(%d+)$")
        end
        local charge = type(code) == "string" and code:match("^BATTERY_LEVEL:(%d+)$")
        local msg = charge and lang.format("Car Battery: %d%%", tonumber(charge) or 0)
            or n and lang.format("Transferred %d rounds", tonumber(n) or 0)
            or dist and lang.format("Distance: %.3f", tonumber(dist) or 0) -- upstream DISTANCEVAL
            or ground and lang.format("Grinding: %s of %s passes cut", ground, passes)
            or MESSAGES[code] and lang.text(MESSAGES[code])
            or tostring(code)
        exports.ui:actionTextShow(msg, 3000)
    end)

    local function itemType(uname)
        return lang.itemType(uname)
    end

    local function vehicleTypeByModel(model)
        return exports.data:vehicleTypeByModel(model)
    end

    local function calibreName(cal)
        return lang.calibreName(cal)
    end

    local function defaultAmmo(cal)
        local list = cal and exports.data:ammoTypesForCalibre(cal)
        return list and list[1] or nil
    end

    local function formatLabel(t, it)
        local name = t and t.name or it.uname
        if clothes and it.uname == "Clothes" then
            name = clothes.label(clothes.skinFor(it.id, it.data))
        elseif it.uname == "Pills" or it.uname == "AutoInjec" or it.uname == "DoctorBag" then
            name = exports.character:medicalLabel(it.uname, name, it.data)
        elseif small and it.uname == "Note" then
            name = small.noteLabel(name, it.data)
        elseif small and it.uname == "CodePart" then
            name = small.codeLabel(name, it.data)
        elseif small and it.uname == "StunGun" then
            name = small.stunLabel(name, it.data)
        elseif small and it.uname == "Battery" then
            name = small.carBatteryLabel(name, small.carBatteryCharge(it.id, it.data))
        elseif small and it.uname == "Key" then
            name = small.keyLabel(name, it.data, vehicleTypeByModel)
        elseif small and it.uname == "WheelLock" then
            name = small.lockLabel(name, it.data)
        elseif gardening and it.uname == gardening.BAG then
            name = gardening.seedLabel(name, gardening.seedsFor(it.id, it.data))
        elseif gas and it.uname == gas.UNAME then
            name = gas.label(name, it.data)
        elseif cooking and cooking.isFood(t) then
            name = cooking.label(t, name, it.data)
        elseif liquids and liquids.isContainer(t) then
            name = liquids.label(t, name, it.data)
        elseif ammo and t then
            local defA = t.categoryData and defaultAmmo(t.categoryData.calibre) or nil
            name = ammo.displayName(t, it.data, itemType, calibreName, defA)
        end
        return string.format("[%02d]%s", t and t.size or 1, name)
    end

    -- "[%02d]%s": the type size then the name, one "<Empty>" per free slot
    -- side: the side container (trunk, box, crate): Combine only works on the player's own inventory and bag
    local function rowsFor(list, cap, moveActions, emptyAction, side)
        local rows = {}
        for _, it in ipairs(list or {}) do
            local t = itemType(it.uname)
            local actions = { { id = "take", label = lang.text("Equip") }, { id = "use", label = lang.text("Use") } }
            if (apparel and apparel.isWearable(it.uname)) or it.uname == "Clothes" then
                actions[#actions + 1] = { id = "wear", label = lang.text("Wear") }
            end
            if moveActions then
                if moveActions.id then
                    actions[#actions + 1] = moveActions
                else
                    for _, act in ipairs(moveActions) do
                        actions[#actions + 1] = act
                    end
                end
            end
            if last and last.held and not side then
                actions[#actions + 1] = { id = "combine", label = lang.text("Combine") }
            end
            rows[#rows + 1] = {
                id = it.id,
                label = formatLabel(t, it),
                actions = actions,
            }
        end
        local emptyRow = { label = lang.text("<Empty>"), empty = true }
        if emptyAction then
            emptyRow = {
                id = emptyAction.id,
                label = lang.text("<Empty>"),
                actions = { emptyAction },
            }
        end
        for _ = 1, math.max(0, (cap.size or 0) - (cap.used or 0)) do
            rows[#rows + 1] = emptyRow
        end
        return rows
    end

    local function bagName(p)
        local uname = p.capacity and p.capacity.bag and p.capacity.bag.uname
        local t = uname and itemType(uname)
        return t and t.name or lang.text("Bag")
    end

    -- refresh: update the list already showing in place (someone else changed the container) instead of opening it;
    -- false when the inventory list is not the one open
    local function open(p, refresh)
        local title, rows
        local bname = bagName(p)
        local tname = p.capacity and p.capacity.trunk and p.capacity.trunk.uname or lang.text("Trunk")
        if view == "trunk" and p.trunk then
            title = string.format("%s (%d/%d)", tname, p.capacity.trunk.used, p.capacity.trunk.size)
            local moveActions = { { id = "move:inventory", label = lang.text("Move to Inventory") } }
            if p.bag then
                moveActions[#moveActions + 1] = { id = "move:bag", label = lang.format("Move to %s", bname) }
            end
            local emptyAction = last
                    and last.held
                    and { id = "put_held:trunk", label = lang.format("Store in %s", tname) }
                or nil
            rows = rowsFor(p.trunk, p.capacity.trunk, moveActions, emptyAction, true)
            rows[#rows + 1] = { id = "nav:inventory", label = lang.text("My Inventory") .. " >" }
            if p.bag then
                rows[#rows + 1] = { id = "nav:bag", label = bname .. " >" }
            end
            if p.containerWorldItemId and #p.trunk == 0 then
                rows[#rows + 1] = {
                    id = "action:pickup_container:" .. tostring(p.containerWorldItemId),
                    label = "[" .. lang.text("Pick up container") .. "]",
                }
            end
        elseif view == "bag" and p.bag then
            title = string.format("%s (%d/%d)", bname, p.capacity.bag.used, p.capacity.bag.size)
            local moveActions = { { id = "move:inventory", label = lang.text("Move to Inventory") } }
            if p.trunk then
                moveActions[#moveActions + 1] = { id = "move:trunk", label = lang.format("Move to %s", tname) }
            end
            local emptyAction = last
                    and last.held
                    and { id = "put_held:bag", label = lang.format("Store in %s", bname) }
                or nil
            rows = rowsFor(p.bag, p.capacity.bag, moveActions, emptyAction)
            rows[#rows + 1] = { id = "nav:inventory", label = lang.text("My Inventory") .. " >" }
            if p.trunk then
                rows[#rows + 1] = { id = "nav:trunk", label = tname .. " >" }
            end
        else
            view = "inventory"
            title = lang.format("Inventory (%d/%d)", p.capacity.inv.used, p.capacity.inv.size)
            local moveActions = {}
            if p.bag then
                moveActions[#moveActions + 1] = { id = "move:bag", label = lang.format("Move to %s", bname) }
            end
            if p.trunk then
                moveActions[#moveActions + 1] = { id = "move:trunk", label = lang.format("Move to %s", tname) }
            end
            local emptyAction = last
                    and last.held
                    and { id = "put_held:inventory", label = lang.text("Store in Inventory") }
                or nil
            rows = rowsFor(p.inventory, p.capacity.inv, #moveActions > 0 and moveActions or nil, emptyAction)
            if p.bag then
                rows[#rows + 1] = { id = "nav:bag", label = bname .. " >" }
            end
            if p.trunk then
                rows[#rows + 1] = { id = "nav:trunk", label = tname .. " >" }
            end
            -- upstream's extra list items (AddInventoryListItem): radio.pwn adds "Radio", skills.pwn "Skills"
            rows[#rows + 1] = { id = "extra:radio", label = lang.text("Radio") }
            rows[#rows + 1] = { id = "extra:skills", label = lang.text("Skills") }
        end
        if refresh then
            return exports.ui:listUpdate("inventory", rows, title)
        end
        exports.ui:listOpen("inventory", title, rows)
        return true
    end

    addEventHandler("inventoryOpened", root, function(p)
        -- a pushed refresh (another player changed the container open here) only updates a list already showing
        if p.refresh and (not last or not exports.ui:listIsOpen()) then
            return
        end
        if p.trunk and (not last or p.trunkContainerId ~= last.trunkContainerId) then
            view = "trunk"
        end
        last = p
        if not p.trunk and view == "trunk" then
            view = "inventory"
        end
        open(p, p.refresh)
    end)

    addEventHandler("uiListActionSelected", root, function(listId, rowId, actionId)
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
            elseif string.match(rowId, "^action:pickup_container:(%d+)$") then
                local itId = tonumber(string.match(rowId, "^action:pickup_container:(%d+)$"))
                triggerServerEvent("containerPickupRequested", localPlayer, itId)
                return exports.ui:listClose()
            elseif rowId == "extra:radio" then
                exports.ui:listClose()
                return exports.chat:radioOpen()
            elseif rowId == "extra:skills" then
                exports.ui:listClose()
                return exports.character:skillsOpen()
            end
            if last then
                open(last)
            end
        elseif actionId == "take" then
            triggerServerEvent("itemTakeRequested", localPlayer, rowId)
        elseif actionId == "use" then
            triggerServerEvent("itemUseRequested", localPlayer, rowId)
        elseif actionId == "wear" then
            triggerServerEvent("itemWearRequested", localPlayer, rowId)
        elseif actionId == "move:bag" then
            triggerServerEvent("itemContainerMoveRequested", localPlayer, rowId, "bag")
        elseif actionId == "move:trunk" then
            triggerServerEvent("itemContainerMoveRequested", localPlayer, rowId, "trunk")
        elseif actionId == "move:inventory" then
            triggerServerEvent("itemContainerMoveRequested", localPlayer, rowId, "inventory")
        elseif actionId == "put_held:bag" then
            triggerServerEvent("itemPutAwayRequested", localPlayer, "bag")
        elseif actionId == "put_held:trunk" then
            triggerServerEvent("itemPutAwayRequested", localPlayer, "trunk")
        elseif actionId == "put_held:inventory" then
            triggerServerEvent("itemPutAwayRequested", localPlayer, "inventory")
        elseif actionId == "combine" then
            triggerServerEvent("combineRequested", localPlayer, rowId)
        end
    end)

    local function drawPanel(x, y, w, h)
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 215))
        dxDrawLine(x, y, x + w, y, tocolor(190, 190, 190, 255))
        dxDrawLine(x, y + h, x + w, y + h, tocolor(190, 190, 190, 255))
        dxDrawLine(x, y, x, y + h, tocolor(190, 190, 190, 255))
        dxDrawLine(x + w, y, x + w, y + h, tocolor(190, 190, 190, 255))
    end

    -- Tiles: a title bar on top of a see-through square (the preview model shows through, upstream filled the
    -- tile 0xFFFFFF08) and a caption below, two columns by three rows to the right of the dialog.
    local TILE_TITLE_H, TILE_CAPTION_H = 14, 20
    local function getLayout()
        local sw, sh = guiGetScreenSize()
        local s = sh / 480
        local dialogW, dialogH = 280 * s, 203 * s
        local dialogX, dialogY = (sw - dialogW) / 2, (sh - dialogH) / 2
        local L = { s = s, panelW = 135 * s, panelH = dialogH, panelY = dialogY, gearY = dialogY }
        L.panelX = dialogX - L.panelW - 10 * s
        L.gearX = dialogX + dialogW + 10 * s
        L.tileW, L.tileH, L.gap = 65 * s, 65 * s, 6 * s
        L.titleH, L.captionH = TILE_TITLE_H * s, TILE_CAPTION_H * s
        L.pitchX, L.pitchY = L.tileW + L.gap, L.tileH + L.captionH + L.gap
        return L
    end

    local function gearSlots()
        local gear = last.gear or {}
        return {
            { id = "hat", name = SLOT_NAMES.hat, item = gear.hat, col = 0, row = 0 },
            { id = "mask", name = SLOT_NAMES.mask, item = gear.mask, col = 1, row = 0 },
            { id = "held", name = SLOT_NAMES.held, item = last.held, col = 0, row = 1 },
            { id = "holster", name = SLOT_NAMES.holster, item = gear.holster, col = 1, row = 1 },
            { id = "armour", name = SLOT_NAMES.armour, item = gear.armour, col = 0, row = 2 },
            { id = "bag", name = SLOT_NAMES.bag, item = last.capacity and last.capacity.bag, col = 1, row = 2 },
        }
    end

    local function tileRect(L, sl)
        return L.gearX + sl.col * L.pitchX, L.gearY + sl.row * L.pitchY, L.tileW, L.tileH
    end

    -- upstream caption: the item name in capitals, "<EMPTY>", the hand slot as "(size) NAME" with weapon state
    local function tileCaption(sl)
        if not sl.item then
            return string.upper(lang.text("<Empty>"))
        end
        local t = itemType(sl.item.uname)
        local name = t and t.name or sl.item.uname
        if sl.id == "held" then
            local state = (formatLabel(t, sl.item):gsub("^%[%d+%]", ""))
            name = string.format("(%02d) %s", t and t.size or 1, state)
        end
        if sl.id == "armour" and type(sl.item.data) == "table" and sl.item.data.ap then
            name = string.format("%s (%d)", name, sl.item.data.ap)
        end
        return string.upper(name)
    end

    local function renderBodyPanel(px, py, pw, ph, s)
        -- upstream ShowPlayerHealthInfo: "Food Infect" and "Wound Infect" in red, each active drug in yellow (#94)
        local extra = {}
        local infection = type(charStats.infection) == "table" and charStats.infection or {}
        if infection.food then
            extra[#extra + 1] = { lang.text("Food Infect"), tocolor(255, 0, 0, 255) }
        end
        if infection.wound then
            extra[#extra + 1] = { lang.text("Wound Infect"), tocolor(255, 0, 0, 255) }
        end
        local drugs = type(charStats.drugs) == "table" and charStats.drugs or {}
        -- lang:begin
        for _, name in ipairs({ "Antibiotic", "Painkill", "Lsd", "Air", "Morphine", "Adrenaline", "Heroin" }) do
            -- lang:end
            if drugs[name] then
                extra[#extra + 1] = { lang.text(name), tocolor(255, 255, 0, 255) }
            end
        end
        -- seven body parts, bleed and hunger, the status rows and the footer: the panel grows past its usual
        -- height when every row would not fit (a stack of drugs dropped the last ones)
        local lineH = 13 * s
        ph = math.max(ph, 22 * s + (9 + #extra) * lineH + 4 * s + 22 * s)
        drawPanel(px, py, pw, ph)
        dxDrawRectangle(px, py, pw, 18 * s, tocolor(50, 50, 50, 255))
        dxDrawText(
            lang.text("Health Status"),
            px,
            py,
            px + pw,
            py + 18 * s,
            tocolor(255, 255, 255, 255),
            1.0 * s,
            "default-bold",
            "center",
            "center"
        )

        local wounds = charStats.wounds or 0
        local bleed = charStats.bleed or 0
        local food = charStats.food or 100
        -- lang:begin
        local parts = {
            { name = "Head", count = (lastHitPart == 9 and 1 or 0) },
            { name = "Torso", count = (lastHitPart == 3 and wounds or 0) },
            { name = "Arm R", count = (lastHitPart == 6 and 1 or 0) },
            { name = "Arm L", count = (lastHitPart == 5 and 1 or 0) },
            { name = "Groin", count = (lastHitPart == 4 and 1 or 0) },
            { name = "Leg R", count = (lastHitPart == 8 and 1 or 0) },
            { name = "Leg L", count = (lastHitPart == 7 and 1 or 0) },
        }
        -- lang:end
        if wounds > 0 and lastHitPart == nil then
            parts[2].count = wounds
        end

        local startY = py + 22 * s
        for i, pt in ipairs(parts) do
            local col = pt.count > 0 and tocolor(255, 60, 60, 255) or tocolor(220, 220, 220, 255)
            dxDrawText(
                string.format("%s: %d", lang.text(pt.name), pt.count),
                px + 8 * s,
                startY + (i - 1) * lineH,
                px + pw,
                startY + i * lineH,
                col,
                0.9 * s,
                "default-bold"
            )
        end

        local statusY = startY + #parts * lineH + 4 * s
        -- bleed is only ever dealt with to two decimals: what reads 0.00 is green
        local bleedText = lang.format("Bleed: %.2f", bleed)
        local bleeding = string.format("%.2f", bleed) ~= "0.00"
        local bleedCol = bleeding and tocolor(255, 60, 60, 255) or tocolor(50, 220, 50, 255)
        dxDrawText(bleedText, px + 8 * s, statusY, px + pw, statusY + lineH, bleedCol, 0.85 * s, "default-bold")
        local foodCol = food < 20 and tocolor(255, 60, 60, 255)
            or (food < 50 and tocolor(255, 200, 50, 255) or tocolor(50, 220, 50, 255))
        dxDrawText(
            lang.format("Hunger: %d%%", math.floor(food)),
            px + 8 * s,
            statusY + lineH,
            px + pw,
            statusY + lineH * 2,
            foodCol,
            0.85 * s,
            "default-bold"
        )

        local footerY = py + ph - 18 * s
        for i, row in ipairs(extra) do
            local y = statusY + lineH * (i + 1)
            dxDrawText(row[1], px + 8 * s, y, px + pw, y + lineH, row[2], 0.85 * s, "default-bold")
        end
        dxDrawRectangle(px, footerY, pw, 18 * s, tocolor(50, 50, 50, 255))
        local koChance = math.min(100, (wounds + 1) * 0.2 * ((bleed * 50) + 1) * 10)
        dxDrawText(
            lang.format("%.1f%% Unconscious", koChance),
            px,
            footerY,
            px + pw,
            footerY + 18 * s,
            tocolor(255, 255, 255, 255),
            0.85 * s,
            "default-bold",
            "center",
            "center"
        )
    end

    local function drawTileFrame(x, y, w, h)
        dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 8))
        dxDrawLine(x, y, x + w, y, tocolor(190, 190, 190, 255))
        dxDrawLine(x, y + h, x + w, y + h, tocolor(190, 190, 190, 255))
        dxDrawLine(x, y, x, y + h, tocolor(190, 190, 190, 255))
        dxDrawLine(x + w, y, x + w, y + h, tocolor(190, 190, 190, 255))
    end

    -- Draws the six tiles and hands the models to the preview module, which draws them in world space under the
    -- see-through tile centres on the next pre-render.
    local function renderGearTiles(L)
        local s = L.s
        local white, grey = tocolor(255, 255, 255, 255), tocolor(150, 150, 150, 255)
        local entries = {}
        for _, sl in ipairs(gearSlots()) do
            local tx, ty, tw, th = tileRect(L, sl)
            drawTileFrame(tx, ty, tw, th)
            dxDrawRectangle(tx, ty, tw, L.titleH, tocolor(70, 70, 70, 255))
            local slotName = lang.text(sl.name)
            dxDrawText(slotName, tx, ty, tx + tw, ty + L.titleH, white, 0.85 * s, "default-bold", "center", "center")
            local t = sl.item and itemType(sl.item.uname)
            if t and preview and models then
                local area = preview.logic.area(tx, ty, tw, th, L.titleH)
                entries[#entries + 1] = { model = models.forType(t), area = area, itemType = t }
            end
            local cx0, cx1, cy0, cy1 = tx - 5 * s, tx + tw + 5 * s, ty + th + 2 * s, ty + th + L.captionH
            local col = sl.item and white or grey
            dxDrawText(tileCaption(sl), cx0, cy0, cx1, cy1, col, 0.65 * s, "default-bold", "center", "top", true, true)
        end
        if preview then
            preview.show(entries)
        end
    end

    addEventHandler("onClientRender", root, function()
        if not last or not exports.ui:listIsOpen() then
            if preview then
                preview.hide()
            end
            return
        end
        local L = getLayout()
        renderBodyPanel(L.panelX, L.panelY, L.panelW, L.panelH, L.s)
        renderGearTiles(L)
    end)

    addEventHandler("onClientClick", root, function(btn, pressState, mx, my)
        if btn ~= "left" or pressState ~= "down" or not last or not exports.ui:listIsOpen() then
            return
        end
        local L = getLayout()
        for _, sl in ipairs(gearSlots()) do
            local tx, ty, tw, th = tileRect(L, sl)
            if mx >= tx and mx <= tx + tw and my >= ty and my <= ty + th then
                if sl.id == "bag" and last.bag then
                    view = (view == "bag") and "inventory" or "bag"
                    open(last)
                elseif sl.id == "held" and last.held then
                    local target = (view == "bag" and "bag") or (view == "trunk" and "trunk") or nil
                    triggerServerEvent("itemPutAwayRequested", localPlayer, target)
                elseif sl.id ~= "bag" and sl.id ~= "held" then
                    local isEquipped = last.gear and last.gear[sl.id]
                    if isEquipped then
                        triggerServerEvent("itemUnwearRequested", localPlayer, sl.id)
                    elseif
                        last.held
                        and (
                            (apparel and apparel.slotFor(last.held.uname) == sl.id)
                            or (sl.id == "armour" and last.held.uname == "Clothes")
                        )
                    then
                        if last.held.uname == "Clothes" then
                            exports.ui:listClose()
                        end
                        triggerServerEvent("itemWearRequested", localPlayer, last.held.id)
                    end
                end
                break
            end
        end
    end)

    addEventHandler("uiListClosed", root, function(listId)
        if listId == "inventory" then
            if last and last.trunk then
                triggerServerEvent("trunkCloseRequested", localPlayer)
            end
            view = "inventory"
            last = nil
        end
    end)
end
