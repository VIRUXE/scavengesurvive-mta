-- The inventory, bag and trunk dialogs (inventory-dialog.inc / container-dialog.inc through the ui resource) and
-- the action-text messages the server sends.
return function(ctx)
    local ammo = ctx and ctx.ammo
    local apparel = ctx and ctx.apparel
    local clothes = ctx and ctx.clothes -- shared/logic/clothes.lua: which skin a Clothes item holds
    local models = ctx and ctx.models -- client/models.lua: which model id draws an item type on this client
    local preview = ctx and ctx.preview -- client/preview.lua: live dxDrawModel3D previews inside the gear tiles
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
        EQUIPPED = "Equipped",
        REMOVED = "Removed",
        NOT_WEARABLE = "This item cannot be worn",
        NOT_WORN = "Nothing equipped in that slot",
        INVENTORY_FULL = "Inventory is full",
        CLOTHESWRGE = "Wrong gender for clothes",
        CLOTHES_ON_DUTY = "Go off duty before changing clothes",
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
        CONTAINER_NOT_EMPTY = "Container is not empty",
        TENT_PITCHED = "Pitched tent",
        TENT_PACKED = "Packed tent",
        TENT_NOT_EMPTY = "The tent must be empty to pack it away",
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
        PLOTPOLEENT = "Entering claimed territory",
        PLOTPOLEEXT = "Leaving claimed territory",
    }
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
        if clothes and it.uname == "Clothes" then
            name = clothes.label(clothes.skinFor(it.id, it.data))
        elseif ammo and t then
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
            local actions = { { id = "take", label = "Equip" }, { id = "use", label = "Use" } }
            if apparel and apparel.isWearable(it.uname) then
                actions[#actions + 1] = { id = "wear", label = "Wear" }
            end
            if last and last.held then
                actions[#actions + 1] = { id = "combine", label = "Combine" }
            end
            rows[#rows + 1] = {
                id = it.id,
                label = formatLabel(t, it),
                actions = actions,
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
            if p.containerWorldItemId and #p.trunk == 0 then
                rows[#rows + 1] = {
                    id = "action:pickup_container:" .. tostring(p.containerWorldItemId),
                    label = "[Pick up container]",
                }
            end
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

    addEventHandler("inventoryOpened", root, function(p)
        last = p
        if p.trunk and view ~= "inventory" and view ~= "bag" then
            view = "trunk"
        elseif not p.trunk and view == "trunk" then
            view = "inventory"
        end
        open(p)
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
            { id = "hat", name = "HEAD", item = gear.hat, col = 0, row = 0 },
            { id = "mask", name = "FACE", item = gear.mask, col = 1, row = 0 },
            { id = "held", name = "HAND", item = last.held, col = 0, row = 1 },
            { id = "holster", name = "HOLSTER", item = gear.holster, col = 1, row = 1 },
            { id = "armour", name = "TORSO", item = gear.armour, col = 0, row = 2 },
            { id = "bag", name = "BACK", item = last.capacity and last.capacity.bag, col = 1, row = 2 },
        }
    end

    local function tileRect(L, sl)
        return L.gearX + sl.col * L.pitchX, L.gearY + sl.row * L.pitchY, L.tileW, L.tileH
    end

    -- upstream caption: the item name in capitals, "<EMPTY>", the hand slot as "(size) NAME" with weapon state
    local function tileCaption(sl)
        if not sl.item then
            return "<EMPTY>"
        end
        local t = itemType(sl.item.uname)
        local name = t and t.name or sl.item.uname
        if sl.id == "held" then
            local state = (formatLabel(t, sl.item):gsub("^%[%d+%]", ""))
            name = string.format("(%02d) %s", t and t.size or 1, state)
        end
        return string.upper(name)
    end

    local function renderBodyPanel(px, py, pw, ph, s)
        drawPanel(px, py, pw, ph)
        dxDrawRectangle(px, py, pw, 18 * s, tocolor(50, 50, 50, 255))
        dxDrawText(
            "Health Status",
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
        local parts = {
            { name = "Head", count = (lastHitPart == 9 and 1 or 0) },
            { name = "Torso", count = (lastHitPart == 3 and wounds or 0) },
            { name = "Arm R", count = (lastHitPart == 6 and 1 or 0) },
            { name = "Arm L", count = (lastHitPart == 5 and 1 or 0) },
            { name = "Groin", count = (lastHitPart == 4 and 1 or 0) },
            { name = "Leg R", count = (lastHitPart == 8 and 1 or 0) },
            { name = "Leg L", count = (lastHitPart == 7 and 1 or 0) },
        }
        if wounds > 0 and lastHitPart == nil then
            parts[2].count = wounds
        end

        local startY = py + 22 * s
        local lineH = 13 * s
        for i, pt in ipairs(parts) do
            local col = pt.count > 0 and tocolor(255, 60, 60, 255) or tocolor(220, 220, 220, 255)
            dxDrawText(
                string.format("%s: %d", pt.name, pt.count),
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
        local bleedCol = bleed > 0 and tocolor(255, 60, 60, 255) or tocolor(50, 220, 50, 255)
        dxDrawText(
            string.format("Bleed: %.2f", bleed),
            px + 8 * s,
            statusY,
            px + pw,
            statusY + lineH,
            bleedCol,
            0.85 * s,
            "default-bold"
        )
        local foodCol = food < 20 and tocolor(255, 60, 60, 255)
            or (food < 50 and tocolor(255, 200, 50, 255) or tocolor(50, 220, 50, 255))
        dxDrawText(
            string.format("Hunger: %d%%", math.floor(food)),
            px + 8 * s,
            statusY + lineH,
            px + pw,
            statusY + lineH * 2,
            foodCol,
            0.85 * s,
            "default-bold"
        )

        local footerY = py + ph - 18 * s
        dxDrawRectangle(px, footerY, pw, 18 * s, tocolor(50, 50, 50, 255))
        local koChance = math.min(100, (wounds + 1) * 0.2 * ((bleed * 50) + 1) * 10)
        dxDrawText(
            string.format("%.1f%% Unconscious", koChance),
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
            dxDrawText(sl.name, tx, ty, tx + tw, ty + L.titleH, white, 0.85 * s, "default-bold", "center", "center")
            local t = sl.item and itemType(sl.item.uname)
            if t and preview and models then
                local area = preview.logic.area(tx, ty, tw, th, L.titleH)
                entries[#entries + 1] = { model = models.forType(t), area = area }
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
                    triggerServerEvent("itemPutAwayRequested", localPlayer)
                elseif sl.id ~= "bag" and sl.id ~= "held" then
                    local isEquipped = last.gear and last.gear[sl.id]
                    if isEquipped then
                        triggerServerEvent("itemUnwearRequested", localPlayer, sl.id)
                    elseif last.held and apparel and apparel.slotFor(last.held.uname) == sl.id then
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
