-- Held items and worn gear as client-side objects placed on the player's bones every frame, from the upstream
-- SA-MP attach data (item type: boneid + attx/y/z + attrx/y/z; bag: per-skin spine offsets with scale; hat, mask and
-- armour: per-skin wearOffsets, see shared/logic/apparel.lua).
-- The server only publishes what is carried: element data "items.held" / "items.bag" = type uname or false.
-- ctx = { models } from client/main.lua (client/models.lua).
return function(ctx)
    local models, apparel = ctx.models, ctx.apparel
    local SLOTS = {
        ["items.held"] = "held",
        ["items.bag"] = "bag",
        ["character.cuffed"] = "cuffs",
        ["items.hat"] = "hat",
        ["items.mask"] = "mask",
        ["items.armour"] = "armour",
        ["items.holster"] = "holster",
    }
    -- SA-MP SetPlayerAttachedObject bone -> GTA:SA bone id (getElementBoneMatrix)
    local SAMP_BONE = {
        [1] = 3, -- spine -> BONE_SPINE1
        [2] = 5, -- head: GTA node 5 is the head pivot whose X axis runs up the skull (8 is the face, X forward)
        [3] = 32, -- left upper arm
        [4] = 22, -- right upper arm
        [5] = 34, -- left hand (BONE_LEFTWRIST is the hand bone)
        [6] = 24, -- right hand
        [7] = 41, -- left thigh
        [8] = 51, -- right thigh
        [9] = 43, -- left foot
        [10] = 53, -- right foot
        [11] = 52, -- right calf
        [12] = 42, -- left calf
        [13] = 33, -- left forearm
        [14] = 23, -- right forearm
        [15] = 31, -- left clavicle
        [16] = 21, -- right clavicle
        [17] = 5, -- neck
        [18] = 7, -- jaw
    }
    local BAG_BONE = 1 -- upstream wears every bag on the spine

    local tracked = {} -- player -> { held = attachment, bag = attachment }
    local typeCache = {}

    local function itemType(uname)
        if typeCache[uname] == nil then
            typeCache[uname] = exports.data:itemType(uname) or false
        end
        return typeCache[uname] or nil
    end

    local function mul3(a, b)
        local m = {}
        for i = 1, 3 do
            m[i] = {}
            for j = 1, 3 do
                m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
            end
        end
        return m
    end

    -- 4x4 row-major with the position in row 4 (getElementMatrix layout); v_world = v_local * L * B.
    -- SA-MP's client applies RwMatrixRotate(bone, X), then Y, then Z, each pre-concatenated (rotation in the bone's
    -- local space), so the object-space rotation is Rz * Ry * Rx: a vertex is rotated about Z first, then Y, then X.
    local function rotationMatrix(rx, ry, rz)
        local cx, sx = math.cos(math.rad(rx)), math.sin(math.rad(rx))
        local cy, sy = math.cos(math.rad(ry)), math.sin(math.rad(ry))
        local cz, sz = math.cos(math.rad(rz)), math.sin(math.rad(rz))
        local X = { { 1, 0, 0 }, { 0, cx, sx }, { 0, -sx, cx } }
        local Y = { { cy, 0, -sy }, { 0, 1, 0 }, { sy, 0, cy } }
        local Z = { { cz, sz, 0 }, { -sz, cz, 0 }, { 0, 0, 1 } }
        return mul3(mul3(Z, Y), X)
    end

    local function multiply(l, b)
        local w = {}
        for i = 1, 4 do
            w[i] = {}
            for j = 1, 3 do
                local s = l[i][1] * b[1][j] + l[i][2] * b[2][j] + l[i][3] * b[3][j]
                if i == 4 then
                    s = s + b[4][j]
                end
                w[i][j] = s
            end
            w[i][4] = i == 4 and 1 or 0
        end
        return w
    end

    -- offsets = { x, y, z, rx, ry, rz }
    local function attachment(uname, bone, offsets, scale)
        local t = itemType(uname)
        local obj = createObject(models.forType(t), 0, 0, 0) or createObject(models.FALLBACK, 0, 0, 0)
        if not obj then
            return nil
        end
        setElementCollisionsEnabled(obj, false)
        models.applyTint(obj, t)
        if scale then
            setObjectScale(obj, scale[1], scale[2], scale[3])
        end
        local r = rotationMatrix(offsets[4], offsets[5], offsets[6])
        local l = { r[1], r[2], r[3], { offsets[1], offsets[2], offsets[3] } }
        return {
            obj = obj,
            uname = uname,
            sampBone = SAMP_BONE[bone] and bone or 6,
            bone = SAMP_BONE[bone] or SAMP_BONE[6],
            offsets = { unpack(offsets, 1, 6) },
            scale = scale and { scale[1], scale[2], scale[3] } or { 1, 1, 1 },
            localMatrix = l,
            interior = -1,
            dimension = -1,
        }
    end

    -- attachedit preview: slot -> { offsets, scale } replacing the configured values on the local player only
    local preview = {}

    local function applyPreview(a, p)
        a.offsets = { unpack(p.offsets, 1, 6) }
        a.scale = { p.scale[1], p.scale[2], p.scale[3] }
        setObjectScale(a.obj, a.scale[1], a.scale[2], a.scale[3])
        local r = rotationMatrix(a.offsets[4], a.offsets[5], a.offsets[6])
        a.localMatrix = { r[1], r[2], r[3], { a.offsets[1], a.offsets[2], a.offsets[3] } }
    end

    local function heldAttachment(uname)
        local t = itemType(uname)
        -- GTA draws real weapons in the hand itself (the server gives the weapon); only custom models are attached
        if t and t.category == "weapon" and t.categoryData and (t.categoryData.baseWeapon or 0) > 0 then
            return nil
        end
        local o = {
            t and t.attx or 0,
            t and t.atty or 0,
            t and t.attz or 0,
            t and t.attrx or 0,
            t and t.attry or 0,
            t and t.attrz or 0,
        }
        return attachment(uname, t and t.boneid or 6, o)
    end

    -- Skins whose mesh carries its own hat, cap or helmet have a hatless twin in the models pack (peds.lua, #75).
    -- A twin whose head was rebuilt bare (#89, exports.models:bareSkin) is how that skin always looks: the hat is
    -- an item of its own (#77). The other twins are only shown while a hat covers them. This client swaps
    -- locally: setElementModel on this side is never synced, so the server and every other client keep the real
    -- skin. swapped[player] holds the real skin meanwhile, and every per-skin row is looked up by it.
    local swapped = {} -- player -> base skin while shown on its hatless twin
    local swapping = false

    local function baseSkin(player)
        return swapped[player] or getElementModel(player)
    end

    local function setModelLocally(player, model)
        swapping = true
        setElementModel(player, model)
        swapping = false
    end

    local function applyHatSwap(player, uname)
        local base = baseSkin(player)
        local twin = exports.models:bareSkin(base) or (uname and exports.models:hatlessSkin(base))
        if twin then
            swapped[player] = base
            if getElementModel(player) ~= twin then
                setModelLocally(player, twin)
            end
        elseif swapped[player] then
            swapped[player] = nil
            if getElementModel(player) ~= base then
                setModelLocally(player, base)
            end
        end
    end

    local function bagOffsetsOf(uname)
        local t = itemType(uname)
        return t and t.categoryData and t.categoryData.bag_offsets
    end

    local function bagAttachment(uname, player)
        -- the wearer's upstream row, or a similar skin's (shared/logic/apparel.lua bagConfig, skins.lua)
        local cfg = apparel and apparel.bagConfig(uname, baseSkin(player), bagOffsetsOf)
        local o = cfg and cfg.offsets or { 0, 0, 0, 0, 0, 0 }
        return attachment(uname, BAG_BONE, o, cfg and cfg.scale or { 1, 1, 1 })
    end

    local function clearSlot(player, slot)
        local slots = tracked[player]
        local a = slots and slots[slot]
        if a then
            if isElement(a.obj) then
                destroyElement(a.obj)
            end
            slots[slot] = nil
        end
    end

    local function cuffAttachment()
        return attachment("HandCuffs", 6, { 0.030, 0.048, -0.017, -8.7, -25.8, 83.8 }, { 1.027, 3.037, 1.622 })
    end

    local function wearOffsetsOf(uname)
        local t = itemType(uname)
        return t and t.wearOffsets
    end

    local function apparelAttachment(slot, uname, player)
        if not apparel then
            return nil
        end
        local cfg = apparel.attachConfig(slot, uname, baseSkin(player), wearOffsetsOf)
        if not cfg then
            return nil
        end
        return attachment(uname, cfg.bone, cfg.offsets, cfg.scale)
    end

    local function setSlot(player, slot, uname)
        clearSlot(player, slot)
        if slot == "hat" then
            applyHatSwap(player, uname or nil)
        end
        if not uname or uname == false then
            return
        end
        tracked[player] = tracked[player] or {}
        if slot == "bag" then
            tracked[player][slot] = bagAttachment(uname, player)
        elseif slot == "cuffs" then
            tracked[player][slot] = cuffAttachment()
        elseif slot == "hat" or slot == "mask" or slot == "armour" or slot == "holster" then
            tracked[player][slot] = apparelAttachment(slot, uname, player)
        else
            tracked[player][slot] = heldAttachment(uname)
        end
        local a = tracked[player][slot]
        if a and player == localPlayer and preview[slot] then
            applyPreview(a, preview[slot])
        end
    end

    local function forgetPlayer(player)
        if tracked[player] then
            for _, slot in pairs(SLOTS) do
                clearSlot(player, slot)
            end
            tracked[player] = nil
        end
        if swapped[player] then
            local base = swapped[player]
            swapped[player] = nil
            if isElement(player) then
                setModelLocally(player, base)
            end
        end
    end

    local function trackPlayer(player)
        for key, slot in pairs(SLOTS) do
            local uname = getElementData(player, key)
            setSlot(player, slot, uname)
        end
    end

    local function place(a, player)
        local b = getElementBoneMatrix(player, a.bone)
        if not b then
            return
        end
        setElementMatrix(a.obj, multiply(a.localMatrix, b))
        local int, dim = getElementInterior(player), getElementDimension(player)
        if int ~= a.interior or dim ~= a.dimension then
            a.interior, a.dimension = int, dim
            setElementInterior(a.obj, int)
            setElementDimension(a.obj, dim)
        end
    end

    -- the SA-MP model pack came or went: attached objects switch between real models and stand-ins in place
    models.onChanged(function()
        for player, slots in pairs(tracked) do
            for _, a in pairs(slots) do
                if isElement(a.obj) then
                    local t = itemType(a.uname)
                    setElementModel(a.obj, models.forType(t))
                    models.applyTint(a.obj, t)
                end
            end
            -- hatless twins came or went with the pack
            if isElement(player) then
                applyHatSwap(player, slots.hat and slots.hat.uname or nil)
            end
        end
        for _, p in ipairs(getElementsByType("player", root, true)) do
            if not tracked[p] then -- no worn gear, but its skin may have a bare twin
                applyHatSwap(p, nil)
            end
        end
    end)

    addEventHandler("onClientPedsProcessed", root, function()
        for player, slots in pairs(tracked) do
            if isElement(player) and (player == localPlayer or isElementStreamedIn(player)) then
                for _, a in pairs(slots) do
                    if isElement(a.obj) then
                        place(a, player)
                    end
                end
            end
        end
    end)

    addEventHandler("onClientElementDataChange", root, function(key, _, value)
        local slot = SLOTS[key]
        if not slot or getElementType(source) ~= "player" then
            return
        end
        if source == localPlayer or isElementStreamedIn(source) then
            setSlot(source, slot, value)
        end
    end)

    addEventHandler("onClientElementStreamIn", root, function()
        if getElementType(source) == "player" then
            trackPlayer(source)
        end
    end)

    addEventHandler("onClientElementStreamOut", root, function()
        if getElementType(source) == "player" then
            forgetPlayer(source)
        end
    end)

    addEventHandler("onClientPlayerQuit", root, function()
        forgetPlayer(source)
    end)

    -- bag, hat, mask and armour offsets are per skin
    local PER_SKIN =
        { ["items.bag"] = "bag", ["items.hat"] = "hat", ["items.mask"] = "mask", ["items.armour"] = "armour" }
    addEventHandler("onClientElementModelChange", root, function()
        if swapping or getElementType(source) ~= "player" then
            return -- our own switch to or from a hatless twin changes no row
        end
        swapped[source] = nil -- the server gave the player a new real skin
        applyHatSwap(source, tracked[source] and tracked[source].hat and tracked[source].hat.uname or nil)
        if tracked[source] then
            for key, slot in pairs(PER_SKIN) do
                if tracked[source][slot] then
                    setSlot(source, slot, getElementData(source, key))
                end
            end
        end
    end)

    addEventHandler("onClientResourceStart", resourceRoot, function()
        for _, p in ipairs(getElementsByType("player", root, true)) do
            trackPlayer(p)
        end
        trackPlayer(localPlayer)
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        for player in pairs(tracked) do
            forgetPlayer(player)
        end
    end)

    local SLOT_KEY = {}
    for key, slot in pairs(SLOTS) do
        SLOT_KEY[slot] = key
    end

    local M = {}

    -- the local player's attachment in slot: { slot, uname, skin, bone (SA-MP id), gtaBone, offsets, scale,
    -- preview }, or nil when the slot is empty or GTA draws the item itself (a real weapon)
    function M.getConfig(slot)
        local a = tracked[localPlayer] and tracked[localPlayer][slot]
        if not a or not isElement(a.obj) then
            return nil
        end
        return {
            slot = slot,
            uname = a.uname,
            skin = baseSkin(localPlayer),
            bone = a.sampBone,
            gtaBone = a.bone,
            offsets = { unpack(a.offsets, 1, 6) },
            scale = { a.scale[1], a.scale[2], a.scale[3] },
            preview = preview[slot] ~= nil,
        }
    end

    -- offsets = { x, y, z, rx, ry, rz }, scale = { sx, sy, sz } (default 1); offsets nil clears the preview and
    -- rebuilds the slot from its configured values. Returns getConfig(slot) afterwards.
    function M.setPreview(slot, offsets, scale)
        if not SLOT_KEY[slot] then
            return nil
        end
        if offsets then
            preview[slot] = { offsets = offsets, scale = scale or { 1, 1, 1 } }
            local a = tracked[localPlayer] and tracked[localPlayer][slot]
            if a and isElement(a.obj) then
                applyPreview(a, preview[slot])
            end
        elseif preview[slot] then
            preview[slot] = nil
            setSlot(localPlayer, slot, getElementData(localPlayer, SLOT_KEY[slot]))
        end
        return M.getConfig(slot)
    end

    return M
end
