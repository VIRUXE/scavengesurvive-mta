-- World items as client-side objects with a name label, from the server's per-player sync deltas.
-- ctx = { models, ammo, tent, clothes, geometry, cooking } from client/main.lua. A pitched TentPack is six objects
-- (shared/logic/tent.lua) placed with upstream's SA-MP rotations as they are: SA-MP's CreateObject and MTA's
-- createObject both go through GTA's own ZXY CMatrix::SetRotate (#55). A campfire burns and a barbecue's burners
-- burn while it cooks (#95): GTA "fire" effects, since upstream's fire objects (18701) are SA-MP particles.
return function(ctx)
    local models = ctx.models
    local ammo = ctx.ammo
    local tent = ctx.tent
    local clothes = ctx.clothes
    local geometry = ctx.geometry
    local cooking = ctx.cooking
    local small = ctx.small
    local gardening = ctx.gardening
    local machines = ctx.machines
    local furniture = ctx.furniture
    local SIGN_RANGE = 25 -- metres a sign's text can be read from
    local objects = {} -- id -> { obj | parts, pitched, row, uname, hp, x, y, z, name, fires, plant }
    local lockersOpen = {} -- locker item id -> true while someone has it open (lockerToggled, #143)
    local labelVisibility = {} -- id -> { visible, checkedAt }
    local shaders = {} -- tent material key -> shader, or false when its texture could not be read
    local typeCache = {}

    local function itemType(uname)
        if typeCache[uname] == nil then
            typeCache[uname] = exports.data:itemType(uname) or false
        end
        return typeCache[uname] or nil
    end

    local function calibreName(cal)
        return exports.data:calibreName(cal)
    end

    local function defaultAmmo(cal)
        local list = cal and exports.data:ammoTypesForCalibre(cal)
        return list and list[1] or nil
    end

    local function isPitchedTent(r)
        if r.uname ~= "TentPack" or not r.data then
            return false
        end
        if r.data.pitched == true then
            return true
        end
        if type(r.data) == "table" and r.data[1] and r.data[1].pitched == true then
            return true
        end
        return false
    end

    -- a built defence (building resource): data.defence, either JSON shape; nil while the item just lies there
    local function builtDefence(r)
        local data = type(r.data) == "table" and r.data or nil
        local def = data and (data.defence or (type(data[1]) == "table" and data[1].defence))
        return type(def) == "table" and def.active == true and def or nil
    end

    local function formatName(t, r)
        -- upstream labels a built defence with its hitpoints (defences.pwn SetItemLabel "%d/%d")
        if t and builtDefence(r) then
            local hp = math.floor(tonumber(r.hp) or 0)
            return string.format("%s\n%d/%d", t.name, hp, t.maxHitpoints or 0)
        end
        if isPitchedTent(r) then
            return "Pitched Tent"
        end
        if clothes and r.uname == "Clothes" then
            return clothes.label(clothes.skinFor(r.id, r.data))
        end
        if cooking.isFood(t) then
            return cooking.label(t, t.name, r.data)
        end
        if r.uname == "Note" then
            return small.noteLabel(t and t.name or r.uname, r.data)
        end
        if r.uname == "CodePart" then
            return small.codeLabel(t and t.name or r.uname, r.data)
        end
        if r.uname == "StunGun" then
            return small.stunLabel(t and t.name or r.uname, r.data)
        end
        if r.uname == gardening.BAG then
            return gardening.seedLabel(t and t.name or r.uname, gardening.seedsFor(r.id, r.data))
        end
        if ammo and t then
            local defA = t.categoryData and defaultAmmo(t.categoryData.calibre) or nil
            return ammo.displayName(t, r.data, itemType, calibreName, defA)
        end
        return t and t.name or r.uname
    end

    local function forget(id)
        local e = objects[id]
        if e then
            if isElement(e.obj) then
                destroyElement(e.obj)
            end
            for _, part in ipairs(e.parts or {}) do
                if isElement(part) then
                    destroyElement(part)
                end
            end
            for _, fx in ipairs(e.fires or {}) do
                if isElement(fx) then
                    destroyElement(fx)
                end
            end
            if isElement(e.plant) then
                destroyElement(e.plant)
            end
            if isElement(e.smoke) then
                destroyElement(e.smoke)
            end
            if isElement(e.shown) then
                destroyElement(e.shown)
            end
            if isElement(e.covering) then
                destroyElement(e.covering)
            end
            objects[id] = nil
        end
        labelVisibility[id] = nil
    end

    -- Upstream retextures the tent parts with stock GTA textures (SetDynamicObjectMaterial); here a replace
    -- shader carries the same texture, read from the stock model that owns it.
    local function materialShader(key)
        if shaders[key] == nil then
            local m = tent.MATERIALS[key]
            local found = engineGetModelTextures(m.model, m.texture)
            local texture = found and found[m.texture]
            local shader = texture and dxCreateShader("client/replace.fx") or nil
            if shader then
                dxSetShaderValue(shader, "Tex", texture)
            end
            shaders[key] = shader or false
        end
        return shaders[key] or nil
    end

    local function place(obj, r)
        setElementCollisionsEnabled(obj, false)
        setElementInterior(obj, r.interior or 0)
        setElementDimension(obj, r.dimension or 0)
    end

    -- The pitched tent: six objects around the pack. None collide, so whoever pitched it from the middle walks out.
    local function createTentParts(r)
        local parts = {}
        for _, p in ipairs(tent.parts(r.x, r.y, r.z, r.rz or 0)) do
            local model = models.forSamp(p.model) or models.FALLBACK
            local obj = createObject(model, p.x, p.y, p.z, p.rx, p.ry, p.rz)
                or createObject(models.FALLBACK, p.x, p.y, p.z, p.rx, p.ry, p.rz)
            if obj then
                place(obj, r)
                local shader = materialShader(p.material)
                if shader then
                    engineApplyShaderToWorldTexture(shader, "*", obj)
                end
                parts[#parts + 1] = obj
            end
        end
        return parts
    end

    -- The type's rest rotation added to the row's heading (upstream CreateItemInWorld with applyrotoffsets), then
    -- turned onto the slope it lies on (ground_nx / ground_ny, set by the death drop and /dropall; false when flat).
    local function orient(obj, r, t)
        -- loose items are walked through; a built defence is a wall (upstream's defence objects collide), and so are a
        -- Locker, which stands as tall as a player, and the furniture (#148)
        local def = builtDefence(r)
        setElementCollisionsEnabled(obj, def ~= nil or r.uname == small.LOCKER.uname or furniture.is(r.uname))
        if def then
            -- its row already holds the raised z and full heading, data the pose
            setElementPosition(obj, r.x, r.y, r.z)
            setElementRotation(obj, def.rx or 0, def.ry or 0, r.rz or 0)
            return
        end
        setElementPosition(obj, r.x, r.y, r.z + (t and t.modelz or 0))
        setElementRotation(obj, t and t.rotx or 0, t and t.roty or 0, (r.rz or 0) + (t and t.rotz or 0))
        local face = r.uname == "Dice" and small.diceFace(r.data)
        if face then -- thrown dice lie on the face they rolled
            local rx, ry = small.diceRotation(face)
            setElementRotation(obj, rx, ry, r.rz or 0)
        elseif r.uname == "Shield" and small.isPlaced(r.data) then -- a planted shield stands facing its owner
            setElementRotation(obj, small.SHIELD_RX, 0, r.rz or 0)
        end
        local nx, ny = tonumber(r.ground_nx) or 0, tonumber(r.ground_ny) or 0
        if nx ~= 0 or ny ~= 0 then
            setElementMatrix(obj, geometry.tilt(getElementMatrix(obj), nx, ny))
        end
    end

    -- the fire a row shows: a campfire always, a barbecue while its cook runs (data.doneAt)
    local function updateFires(e, r)
        for _, fx in ipairs(e.fires or {}) do
            if isElement(fx) then
                destroyElement(fx)
            end
        end
        e.fires = {}
        local spots = {}
        if r.uname == "Campfire" then
            spots[1] = { x = r.x, y = r.y, z = r.z }
        elseif r.uname == "Barbecue" and cooking.decode(r.data).doneAt then
            spots = cooking.burnerSpots(r.x, r.y, r.z, r.rz)
        end
        for _, s in ipairs(spots) do
            local fx = createEffect("fire", s.x, s.y, s.z)
            if fx then
                setElementInterior(fx, r.interior or 0)
                setElementDimension(fx, r.dimension or 0)
                e.fires[#e.fires + 1] = fx
            end
        end
    end

    -- the smoke a machine gives off while it cooks (#145; upstream object 18726 at z - 1): data.machine.cooking
    local function updateSmoke(e, r)
        if isElement(e.smoke) then
            destroyElement(e.smoke)
        end
        e.smoke = nil
        if not machines.isMachine(r.uname) or not machines.state(r.data).cooking then
            return
        end
        local fx = createEffect(machines.SMOKE_EFFECT, r.x, r.y, r.z + 0.5)
        if fx then
            setElementInterior(fx, r.interior or 0)
            setElementDimension(fx, r.dimension or 0)
            e.smoke = fx
        end
    end

    -- the plant a pot grows (#142): a sprout rising with the growth, then the kind's plant
    local function updatePlant(e, r)
        if isElement(e.plant) then
            destroyElement(e.plant)
        end
        e.plant = nil
        if r.uname ~= gardening.POT then
            return
        end
        local model, lift = gardening.plantObject(gardening.pot(r.data))
        if not model then
            return
        end
        local obj = createObject(model, r.x, r.y, r.z + lift, 0, 0, r.rz or 0)
        if obj then
            place(obj, r)
            e.plant = obj
        end
    end

    -- the item a gun case or cupboard shows (#148): data.display, lying in the case
    local function updateShown(e, r)
        if isElement(e.shown) then
            destroyElement(e.shown)
        end
        e.shown = nil
        local shown = furniture.isDisplay(r.uname) and furniture.display(r.data)
        local st = shown and itemType(shown)
        if not st then
            return
        end
        local x, y, z, rx, ry, rz = furniture.displayPose(r, itemType(r.uname), st)
        local obj = createObject(models.forType(st), x, y, z, rx, ry, rz)
        if obj then
            place(obj, r)
            models.applyTint(obj, st)
            e.shown = obj
        end
    end

    -- the panel over a built Large Frame (upstream largeframe.pwn: SA-MP 19908 at z + 2.6, rotated 0, 90, rz), while
    -- data.defence.covered; it is a roof, so it collides
    local function updateCovering(e, r)
        if isElement(e.covering) then
            destroyElement(e.covering)
        end
        e.covering = nil
        local def = r.uname == "LargeFrame" and builtDefence(r)
        local model = def and def.covered == true and models.forSamp(19908)
        if not model then
            return
        end
        local obj = createObject(model, r.x, r.y, r.z + 2.6, 0, 90, r.rz or 0)
        if obj then
            place(obj, r)
            e.covering = obj
        end
    end

    -- a locker draws its open twin while someone has it open
    local function modelFor(r, t)
        if r.uname == small.LOCKER.uname then
            return models.forSamp(small.lockerModel(lockersOpen[r.id])) or models.forType(t)
        end
        return models.forType(t)
    end

    local function createItemObject(r, t)
        local obj = createObject(modelFor(r, t), r.x, r.y, r.z) or createObject(models.FALLBACK, r.x, r.y, r.z)
        if obj then
            place(obj, r)
            orient(obj, r, t)
            models.applyTint(obj, t)
        end
        return obj
    end

    addEventHandler("inventorySynced", resourceRoot, function(delta)
        for _, id in ipairs(delta.remove or {}) do
            forget(id)
        end
        for _, r in ipairs(delta.add or {}) do
            local t = itemType(r.uname)
            local isPitched = isPitchedTent(r)
            local e = objects[r.id]
            if e and e.pitched ~= isPitched then
                forget(r.id) -- pitched or packed in place: the row comes again and the objects are rebuilt
                e = nil
            end
            if e then
                e.name = formatName(t, r)
                if isElement(e.obj) then -- the row came again because it moved or turned (a door swung)
                    orient(e.obj, r, t)
                end
                e.row = r
                updateFires(e, r)
                updatePlant(e, r)
                updateSmoke(e, r)
                updateShown(e, r)
                updateCovering(e, r)
            else
                e = {
                    pitched = isPitched,
                    row = r,
                    uname = r.uname,
                    hp = r.hp,
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    name = formatName(t, r),
                }
                if isPitched then
                    e.parts = createTentParts(r)
                else
                    e.obj = createItemObject(r, t)
                end
                updateFires(e, r)
                updatePlant(e, r)
                updateSmoke(e, r)
                updateShown(e, r)
                updateCovering(e, r)
                objects[r.id] = e
            end
        end
    end)

    -- the SA-MP model pack came or went: world objects switch between real models and stand-ins in place
    models.onChanged(function()
        for _, e in pairs(objects) do
            if e.parts then
                for _, part in ipairs(e.parts) do
                    if isElement(part) then
                        destroyElement(part)
                    end
                end
                e.parts = createTentParts(e.row)
            elseif isElement(e.obj) then
                local t = itemType(e.uname)
                setElementModel(e.obj, modelFor(e.row, t))
                models.applyTint(e.obj, t)
            end
            updateCovering(e, e.row)
        end
    end)

    addEventHandler("onClientRender", root, function()
        local px, py, pz = getElementPosition(localPlayer)
        local cx, cy, cz = getCameraMatrix()
        local now = getTickCount()
        local _, sh = guiGetScreenSize()
        for _, e in pairs(objects) do
            local dx, dy, dz = e.x - px, e.y - py, e.z - pz
            local d2 = dx * dx + dy * dy + dz * dz
            -- a sign's text, upstream's material text on the sign object, hangs above it here
            if e.uname == "Sign" and d2 < SIGN_RANGE * SIGN_RANGE then
                local text = small.text(e.row.data)
                if text ~= "" then
                    local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 1.2, 0, false)
                    if sx then
                        local scale = (sh / 1080) * math.max(0.6, 1.6 - math.sqrt(d2) / SIGN_RANGE)
                        local lines = table.concat(small.signLines(text), "\n")
                        local white, shadow = tocolor(255, 255, 255, 240), tocolor(0, 0, 0, 220)
                        dxDrawText(
                            lines,
                            sx + 1,
                            sy + 1,
                            sx + 1,
                            sy + 1,
                            shadow,
                            scale,
                            "default-bold",
                            "center",
                            "center"
                        )
                        dxDrawText(lines, sx, sy, sx, sy, white, scale, "default-bold", "center", "center")
                    end
                end
            end
            if d2 < 4 * 4 then
                local visibility = labelVisibility[e.row.id]
                if not visibility or now - visibility.checkedAt >= 300 then
                    local obj = isElement(e.obj) and e.obj or nil
                    labelVisibility[e.row.id] = {
                        visible = isLineOfSightClear(
                            cx,
                            cy,
                            cz,
                            e.x,
                            e.y,
                            e.z + 0.5,
                            true,
                            true,
                            false,
                            true,
                            true,
                            false,
                            false,
                            false,
                            obj
                        ),
                        checkedAt = now,
                    }
                    visibility = labelVisibility[e.row.id]
                end
                if visibility.visible then
                    local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 0.5, 0, false)
                    if sx then
                        local scale = (sh / 1080) * (d2 < 9 and 1.1 or 0.9)
                        dxDrawText(
                            e.name,
                            sx + 1,
                            sy + 1,
                            sx + 1,
                            sy + 1,
                            tocolor(0, 0, 0, 200),
                            scale,
                            "default-bold",
                            "center",
                            "center"
                        )
                        dxDrawText(
                            e.name,
                            sx,
                            sy,
                            sx,
                            sy,
                            tocolor(255, 255, 0, 230),
                            scale,
                            "default-bold",
                            "center",
                            "center"
                        )
                    end
                end
            end
        end
    end)

    addEventHandler("lockerToggled", resourceRoot, function(id, open)
        lockersOpen[id] = open and true or nil
        local e = objects[id]
        if e and isElement(e.obj) and e.uname == small.LOCKER.uname then
            setElementModel(e.obj, modelFor(e.row, itemType(e.uname)))
        end
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        for id in pairs(objects) do
            forget(id)
        end
    end)

    -- A campfire or barbecue within reach of the local player (the hud's "Cook" hint), nil when none.
    local M = {}
    function M.nearbyCooker(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for _, e in pairs(objects) do
            if e.uname == "Campfire" or e.uname == "Barbecue" then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 then
                    return e.uname
                end
            end
        end
        return nil
    end

    -- A Sign or a body (Torso) lying within reach of the local player: the hud edits or investigates it on a tap
    -- of F and picks it up on a hold. Returns id, uname; nil when none.
    local INSPECTABLE = { Sign = true, Torso = true, PlantPot = true }
    function M.nearbyInspectable(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for id, e in pairs(objects) do
            if INSPECTABLE[e.uname] then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 then
                    return id, e.uname
                end
            end
        end
        return nil
    end

    -- the machine within reach (hud: a tap opens it, a hold its menu), or nil
    function M.nearbyMachine(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for id, e in pairs(objects) do
            if machines.isMachine(e.uname) then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 then
                    return id
                end
            end
        end
        return nil
    end

    function M.nearbyBag(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local nearest, nearestDist = nil, reach * reach
        for id, e in pairs(objects) do
            local t = itemType(e.uname)
            if t and t.category == "bag" then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local dist = dx * dx + dy * dy + dz * dz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and math.abs(dz) < 3 and dist < nearestDist then
                    nearest, nearestDist = id, dist
                end
            end
        end
        return nearest
    end

    -- the distance to the nearest world item in the player's world, or false: world's buttons give way to an item
    -- lying nearer (upstream items are buttons too and the nearest one wins)
    function M.nearestItemDistance()
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local best = nil
        for _, e in pairs(objects) do
            local r = e.row
            if (r.dimension or 0) == dim and (r.interior or 0) == int then
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local dist = dx * dx + dy * dy + dz * dz
                if not best or dist < best then
                    best = dist
                end
            end
        end
        return best and math.sqrt(best) or false
    end
    return M
end
