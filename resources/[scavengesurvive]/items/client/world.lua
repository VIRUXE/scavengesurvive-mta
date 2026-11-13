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
    local vending = ctx.vending
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local surface = loadstring(exports.lib:getModule("surface"), "=lib/surface.lua")()
    local SIGN_RANGE = 25 -- metres a sign's text can be read from
    local LABEL_RANGE = 4 -- metres an item's name shows from
    local DEFENCE_LABEL_RANGE = 10 -- a built defence's hitpoints, which other walls do not hide
    local objects = {} -- id -> { obj | parts, pitched, row, uname, hp, x, y, z, name, fires, plant }
    local lockersOpen = {} -- locker item id -> true while someone has it open (lockerToggled, #143)
    local labelVisibility = {} -- id -> { visible, checkedAt }
    local reachCache = {} -- id -> { ok, at }: no wall between the player and the item
    local itemElements = setmetatable({}, { __mode = "k" }) -- elements world items draw: never a wall
    local paneOf = setmetatable({}, { __mode = "k" }) -- a snack machine's intact pane -> the machine's item id
    local shaders = {} -- tent material key -> shader, or false when its texture could not be read
    local typeCache = {} -- uname -> item type with its names in the local player's language (lang.itemType)
    -- Items riding in a towed walk-in trailer (the vehicles resource lists them in the trailer's "vehicles.cargo"
    -- element data as { id, lx, ly, lz, lrz }: their stored spot in the trailer's frame): id -> { vehicle, lx, ly, lz,
    -- lrz, attached, dz }. Their objects hang on the trailer until the list drops them and their row comes again.
    local riding = {}

    local function itemType(uname)
        if typeCache[uname] == nil then
            typeCache[uname] = lang.itemType(uname) or false
        end
        return typeCache[uname] or nil
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
            return lang.text("Pitched Tent")
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
        if r.uname == "Battery" then
            return small.carBatteryLabel(t and t.name or r.uname, small.carBatteryCharge(r.id, r.data))
        end
        if r.uname == "Key" then
            return small.keyLabel(t and t.name or r.uname, r.data, vehicleTypeByModel)
        end
        if r.uname == "WheelLock" then
            return small.lockLabel(t and t.name or r.uname, r.data)
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

    -- /lang: the labels already made are rebuilt in the new language
    lang.onChange(function()
        typeCache = {}
        for _, e in pairs(objects) do
            if e.row then
                e.name = formatName(itemType(e.row.uname), e.row)
            end
        end
    end)

    -- every element an item draws with: the object or tent parts, and its fires, plant, smoke, shown item, cover
    local function elementsOf(e)
        local list = {}
        if isElement(e.obj) then
            list[#list + 1] = e.obj
        end
        for _, part in ipairs(e.parts or {}) do
            list[#list + 1] = part
        end
        for _, fx in ipairs(e.fires or {}) do
            list[#list + 1] = fx
        end
        for _, key in ipairs({ "plant", "smoke", "shown", "covering", "glass" }) do
            if isElement(e[key]) then
                list[#list + 1] = e[key]
            end
        end
        for _, obj in ipairs(e.snacks or {}) do
            if isElement(obj) then
                list[#list + 1] = obj
            end
        end
        return list
    end

    -- hangs an item's elements on its trailer: each keeps its offset from the item's stored spot, turned into the
    -- trailer's frame, so an item drawn mid-trip (it came into range then) lands where it rides
    local function attachRider(id)
        local e, c = objects[id], riding[id]
        if not e or not c or c.attached or not isElement(c.vehicle) then
            return
        end
        local r = e.row
        local a = math.rad(r.rz or 0)
        local ca, sa = math.cos(a), math.sin(a)
        local b = math.rad(c.lrz)
        local cb, sb = math.cos(b), math.sin(b)
        for _, el in ipairs(elementsOf(e)) do
            local ex, ey, ez = getElementPosition(el)
            local rx, ry, rz = getElementRotation(el)
            local dx, dy = ex - r.x, ey - r.y
            local ux, uy = dx * ca + dy * sa, -dx * sa + dy * ca -- the offset in the item's own frame
            local ox, oy = c.lx + ux * cb - uy * sb, c.ly + ux * sb + uy * cb
            if getElementType(el) == "object" then
                setElementCollidableWith(el, c.vehicle, false)
            end
            attachElements(el, c.vehicle, ox, oy, c.lz + ez - r.z, rx, ry, rz - (r.rz or 0) + c.lrz)
        end
        if isElement(e.obj) then
            local _, _, oz = getElementPosition(e.obj)
            c.dz = oz - r.z
        end
        c.attached = true
    end

    -- lets an item's elements go where they are; its row comes again and puts them on its stored spot
    local function detachRider(id)
        local e, c = objects[id], riding[id]
        if not c or not c.attached then
            return
        end
        c.attached = false
        for _, el in ipairs(e and elementsOf(e) or {}) do
            detachElements(el)
            if getElementType(el) == "object" and isElement(c.vehicle) then
                setElementCollidableWith(el, c.vehicle, true)
            end
        end
    end

    -- a trailer's cargo list changed: its riders attach, the ones it dropped let go
    local function applyCargo(vehicle)
        local list = getElementData(vehicle, "vehicles.cargo")
        local now = {}
        for _, row in ipairs(type(list) == "table" and list or {}) do
            local id = tonumber(row[1])
            if id then
                now[id] = true
                local c = riding[id]
                if not c or c.vehicle ~= vehicle then
                    detachRider(id)
                    riding[id] = {
                        vehicle = vehicle,
                        lx = row[2],
                        ly = row[3],
                        lz = row[4],
                        lrz = row[5],
                        attached = false,
                    }
                end
                attachRider(id)
            end
        end
        for id, c in pairs(riding) do
            if c.vehicle == vehicle and not now[id] then
                detachRider(id)
                riding[id] = nil
            end
        end
    end

    addEventHandler("onClientElementDataChange", root, function(key)
        if key == "vehicles.cargo" and getElementType(source) == "vehicle" then
            applyCargo(source)
        end
    end)

    addEventHandler("onClientElementDestroy", root, function()
        if getElementType(source) ~= "vehicle" then
            return
        end
        for id, c in pairs(riding) do
            if c.vehicle == source then
                detachRider(id)
                riding[id] = nil
            end
        end
    end)

    -- a rider's label and reach checks follow it: its spot is where its object is now (less the model's lift)
    addEventHandler("onClientPreRender", root, function()
        for id, c in pairs(riding) do
            local e = objects[id]
            if c.attached and e and isElement(e.obj) then
                local x, y, z = getElementPosition(e.obj)
                e.x, e.y, e.z = x, y, z - (c.dz or 0)
            end
        end
    end)

    -- a snack machine's pane and the snacks in its coils (updateVending), all attached to its object
    local function clearVending(e)
        if isElement(e.glass) then
            destroyElement(e.glass)
        end
        for _, obj in ipairs(e.snacks or {}) do
            if isElement(obj) then
                destroyElement(obj)
            end
        end
        e.glass, e.snacks = nil, nil
    end

    local function forget(id)
        local e = objects[id]
        if e then
            clearVending(e)
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
        reachCache[id] = nil
    end

    local REACH_CACHE_MS = 250
    local REACH_RAY_STEPS = 6 -- items and held objects a ray may pass through before it counts as blocked
    local F = false

    -- a ray from the chest to a point; items and carried objects are passed through, anything else blocks it
    local function rayClear(sx, sy, sz, tx, ty, tz, ign)
        for _ = 1, REACH_RAY_STEPS do
            local left = getDistanceBetweenPoints3D(sx, sy, sz, tx, ty, tz)
            if left < 0.1 then
                return true
            end
            local hit, hx, hy, hz, el = processLineOfSight(sx, sy, sz, tx, ty, tz, true, F, F, true, F, F, F, F, ign)
            if not hit then
                return true
            end
            if not (el and (itemElements[el] or getElementAttachedTo(el))) then
                return false
            end
            local k = 0.05 / math.max(left, 0.05)
            sx, sy, sz = hx + (tx - sx) * k, hy + (ty - sy) * k, hz + (tz - sz) * k
            ign = el
        end
        return false
    end

    -- true when no wall or map object lies between the player and the world item (a carton in a pile, a table or a
    -- low kerb does not count): the server picks by distance alone and cannot test this
    local function reachable(id, e)
        local now = getTickCount()
        local cached = reachCache[id]
        if cached and now - cached.at < REACH_CACHE_MS then
            return cached.ok
        end
        local sx, sy, sz = getElementPosition(localPlayer)
        sz = sz + 0.5
        local own = isElement(e.obj) and e.obj or nil
        local ok = rayClear(sx, sy, sz, e.x, e.y, e.z + 0.15, own) or rayClear(sx, sy, sz, e.x, e.y, e.z + 0.6, own)
        reachCache[id] = { ok = ok, at = now }
        return ok
    end

    -- every element the item draws, so that a ray passes through it
    local function markItemElements(e)
        for _, el in ipairs({
            e.obj or false,
            e.plant or false,
            e.shown or false,
            e.covering or false,
            e.glass or false,
        }) do
            if el then
                itemElements[el] = true
            end
        end
        for _, obj in ipairs(e.snacks or {}) do
            itemElements[obj] = true
        end
        for _, part in ipairs(e.parts or {}) do
            itemElements[part] = true
        end
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
        setElementCollisionsEnabled(
            obj,
            def ~= nil or r.uname == small.LOCKER.uname or furniture.is(r.uname) or vending.is(r.uname)
        )
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
            setElementCollisionsEnabled(obj, true)
            e.covering = obj
        end
    end

    -- a snack machine (shared/logic/vending.lua): its pane, whole or broken, and a snack in each coil data.shelf
    -- names, all hung on the cabinet
    local function updateVending(e, r)
        clearVending(e)
        if not vending.is(r.uname) or not isElement(e.obj) then
            return
        end
        local broken = vending.isBroken(r.data)
        local paneModel = models.forSamp(broken and vending.MODEL_BROKEN or vending.MODEL_GLASS)
        local pane = paneModel and createObject(paneModel, r.x, r.y, r.z)
        if pane then
            place(pane, r)
            attachElements(pane, e.obj, 0, 0, 0)
            if not broken then -- fists, clubs and bullets land on it (client/vending.lua hears the hits)
                setElementCollisionsEnabled(pane, true)
                paneOf[pane] = r.id
            end
            e.glass = pane
        end
        e.snacks = {}
        local shelf = type(r.data) == "table" and type(r.data.shelf) == "table" and r.data.shelf or {}
        for coil = 1, vending.SLOTS do
            local st = shelf[coil] and shelf[coil] ~= "" and itemType(shelf[coil])
            if st then
                local obj = createObject(models.forType(st), r.x, r.y, r.z)
                if obj then
                    place(obj, r)
                    attachElements(obj, e.obj, vending.slotPose(coil, st.uname))
                    e.snacks[#e.snacks + 1] = obj
                end
            end
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

    -- rows the server flags `snap` lie on an untrusted z (item_ground_snap): measure the ground under each once it is
    -- near enough for its collision to be loaded, and report it (itemGroundMeasured); the server moves the row
    local toMeasure = {} -- id -> true
    local MEASURE_RANGE, MEASURE_PER_TICK = 60, 5
    setTimer(function()
        if not next(toMeasure) then
            return
        end
        local px, py = getElementPosition(localPlayer)
        local sent = 0
        for id in pairs(toMeasure) do
            local e = objects[id]
            if not e then
                toMeasure[id] = nil
            elseif getDistanceBetweenPoints2D(px, py, e.x, e.y) <= MEASURE_RANGE then
                local obj = e.obj
                local solid = isElement(obj) and getElementCollisionsEnabled(obj)
                if solid then
                    setElementCollisionsEnabled(obj, false) -- the ray must pass the item itself
                end
                local _, _, hz, nx, ny = surface.below(e.x, e.y, e.z, 1.5, 6)
                if solid then
                    setElementCollisionsEnabled(obj, true)
                end
                if hz then
                    toMeasure[id] = nil
                    triggerServerEvent("itemGroundMeasured", localPlayer, id, hz, nx, ny)
                    sent = sent + 1
                    if sent >= MEASURE_PER_TICK then
                        return
                    end
                end
            end
        end
    end, 1000, 0)

    addEventHandler("inventorySynced", resourceRoot, function(delta)
        for _, id in ipairs(delta.remove or {}) do
            toMeasure[id] = nil
            forget(id)
        end
        for _, r in ipairs(delta.add or {}) do
            if r.snap == 1 or r.snap == true then
                toMeasure[r.id] = true
            end
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
                detachRider(r.id) -- the row came again: drawn on its stored spot, then hung on its trailer again
                e.name = formatName(t, r)
                e.defence = builtDefence(r) ~= nil
                e.x, e.y, e.z = r.x or e.x, r.y or e.y, r.z or e.z -- a built defence stands higher than it lay
                if isElement(e.obj) then -- the row came again because it moved or turned (a door swung)
                    orient(e.obj, r, t)
                end
                e.row = r
                updateFires(e, r)
                updatePlant(e, r)
                updateSmoke(e, r)
                updateShown(e, r)
                updateCovering(e, r)
                updateVending(e, r)
                markItemElements(e)
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
                    defence = builtDefence(r) ~= nil,
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
                updateVending(e, r)
                markItemElements(e)
                objects[r.id] = e
            end
            attachRider(r.id)
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
            updateVending(e, e.row)
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
            local range = e.defence and DEFENCE_LABEL_RANGE or LABEL_RANGE
            if d2 < range * range then
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
                            not e.defence, -- a wall in a stack would hide the labels of the walls behind it
                            true,
                            false,
                            false,
                            obj -- its own model: a standing wall's label point lies inside it
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

    -- true when no wall or map object lies between the player's chest and a drop spot at ground height z (items and
    -- carried objects do not count, as for a pickup)
    function M.dropSpotReachable(x, y, z)
        local sx, sy, sz = getElementPosition(localPlayer)
        sz = sz + 0.5
        return rayClear(sx, sy, sz, x, y, z + 0.15) or rayClear(sx, sy, sz, x, y, z + 0.6)
    end

    -- the snack machines this client draws whose glass still holds: { { id, x, y, z, rz, int, dim } }
    function M.intactMachines()
        local out = {}
        for id, e in pairs(objects) do
            local r = e.row
            if r and vending.is(r.uname) and not vending.isBroken(r.data) then
                out[#out + 1] = {
                    id = id,
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    rz = r.rz or 0,
                    int = r.interior or 0,
                    dim = r.dimension or 0,
                }
            end
        end
        return out
    end

    -- the snack machine whose intact pane this element is, or nil
    function M.machineOfPane(el)
        return paneOf[el]
    end

    -- where a machine stands, for the shatter (client/vending.lua): x, y, z, rz or nil
    function M.machineAt(id)
        local e = objects[id]
        local r = e and e.row
        if r and vending.is(r.uname) then
            return r.x, r.y, r.z, r.rz or 0
        end
    end

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
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 and reachable(id, e) then
                    return id, e.uname
                end
            end
        end
        return nil
    end

    -- the objects of every world item of type uname this client has: { [item id] = object }
    function M.objectsOfType(uname)
        local out = {}
        for id, e in pairs(objects) do
            if e.uname == uname and isElement(e.obj) then
                out[id] = e.obj
            end
        end
        return out
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
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 and reachable(id, e) then
                    return id
                end
            end
        end
        return nil
    end

    -- the nearest bag or safebox lying within reach (upstream: a tap opens it, a hold picks it up): id, category
    function M.nearbyContainerItem(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local nearest, nearestDist, nearestCategory = nil, reach * reach, nil
        for id, e in pairs(objects) do
            local t = itemType(e.uname)
            if t and (t.category == "bag" or t.category == "safebox") then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local dist = dx * dx + dy * dy + dz * dz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and math.abs(dz) < 3 and dist < nearestDist and reachable(id, e) then
                    -- a take-only one (the snack machine) stands where it is: "fixed", opened but never picked up
                    local fixed = t.categoryData and t.categoryData.takeOnly
                    nearest, nearestDist, nearestCategory = id, dist, fixed and "fixed" or t.category
                end
            end
        end
        return nearest, nearestCategory
    end

    -- Explicit targets for the shared interaction chooser; never substitute a nearer item on selection.
    function M.interactionActions()
        local actions = {}
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for id, e in pairs(objects) do
            local r, t = e.row, itemType(e.uname)
            local dx, dy, dz = e.x - px, e.y - py, e.z - pz
            if
                t
                and (r.dimension or 0) == dim
                and (r.interior or 0) == int
                and dx * dx + dy * dy + dz * dz <= 4
                and reachable(id, e)
            then
                local verb = lang.text("Pick up")
                local event = "itemPickupRequested"
                if t.category == "bag" or t.category == "safebox" then
                    verb = lang.text("Open")
                    if t.category == "bag" then
                        event = "itemBagOpenRequested"
                    end
                elseif e.uname == "Sign" then
                    verb, event = lang.text("Edit sign"), "signEditRequested"
                elseif e.uname == "PlantPot" then
                    verb, event = lang.text("Inspect plant pot"), "potInspectRequested"
                elseif e.uname == "Torso" then
                    verb, event = lang.text("Investigate"), "bodyInspectRequested"
                elseif machines.isMachine(e.uname) then
                    verb = lang.text("Access machine")
                end
                if e.uname == "Welder" then
                    actions[#actions + 1] = {
                        id = "torch:" .. id,
                        label = lang.text("Take torch") .. " · " .. t.name,
                        event = "weldTorchGrabRequested",
                        target = id,
                        item = true,
                    }
                end
                actions[#actions + 1] = {
                    id = "item:" .. id,
                    label = verb .. " · " .. t.name,
                    event = event,
                    target = id,
                    item = true,
                }
                if
                    (t.category == "bag" or t.category == "safebox")
                    and not (t.categoryData and t.categoryData.takeOnly)
                then
                    actions[#actions + 1] = {
                        id = "carry:" .. id,
                        label = lang.text("Pick up") .. " · " .. t.name,
                        event = "itemLongPickupRequested",
                        target = id,
                        item = true,
                    }
                end
            end
        end
        table.sort(actions, function(a, b)
            return a.id < b.id
        end)
        return actions
    end

    -- the distance to the nearest world item in the player's world, or false: world's buttons give way to an item
    -- lying nearer (upstream items are buttons too and the nearest one wins)
    function M.nearestItemDistance()
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local best = nil
        for id, e in pairs(objects) do
            local r = e.row
            if (r.dimension or 0) == dim and (r.interior or 0) == int then
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local dist = dx * dx + dy * dy + dz * dz
                if (not best or dist < best) and (dist > 9 or reachable(id, e)) then
                    best = dist
                end
            end
        end
        return best and math.sqrt(best) or false
    end

    -- the ids of the world items within reach that a wall hides (at most 32): the server leaves them out of a pickup
    function M.blockedNear(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local blocked = {}
        for id, e in pairs(objects) do
            local r = e.row
            local dx, dy, dz = e.x - px, e.y - py, e.z - pz
            local same = (r.dimension or 0) == dim and (r.interior or 0) == int
            if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 and not reachable(id, e) then
                blocked[#blocked + 1] = id
                if #blocked >= 32 then
                    break
                end
            end
        end
        return blocked
    end
    -- the objects (a pitched tent's every part) of the world items within radius of (x, y, z) in the player's world
    function M.itemObjectsNear(x, y, z, radius)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local out = {}
        for _, e in pairs(objects) do
            local r = e.row
            local dx, dy, dz = e.x - x, e.y - y, e.z - z
            local same = (r.dimension or 0) == dim and (r.interior or 0) == int
            if same and dx * dx + dy * dy + dz * dz <= radius * radius then
                if isElement(e.obj) then
                    out[#out + 1] = e.obj
                end
                for _, part in ipairs(e.parts or {}) do
                    if isElement(part) then
                        out[#out + 1] = part
                    end
                end
            end
        end
        return out
    end

    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if getElementData(vehicle, "vehicles.cargo") then
            applyCargo(vehicle)
        end
    end

    return M
end
