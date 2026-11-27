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
    local floodlight = ctx.floodlight
    local power = ctx.power
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local surface = loadstring(exports.lib:getModule("surface"), "=lib/surface.lua")()
    local SIGN_RANGE = 25 -- metres a sign's text can be read from
    local LABEL_RANGE = 4 -- metres an item's name shows from
    local DEFENCE_LABEL_RANGE = 10 -- a built defence's hitpoints, which other walls do not hide
    local objects = {} -- id -> { obj | parts, pitched, row, uname, hp, x, y, z, name, fires, plant }
    local lockersOpen = {} -- locker item id -> true while someone has it open (lockerToggled, #143)
    local labelVisibility = {} -- id -> { visible, checkedAt }
    local reachCache = {} -- id -> { ok, at, tool }: no wall between the player and the item
    local passCache = {} -- id -> { ok, at }: the item fits through the way to the player
    local itemElements = setmetatable({}, { __mode = "k" }) -- elements world items draw: never a wall
    -- except these: a built defence (and a Large Frame's covering) is a wall, so a box behind one is out of reach
    local defenceElements = setmetatable({}, { __mode = "k" })
    local paneOf = setmetatable({}, { __mode = "k" }) -- a snack machine's intact pane -> the machine's item id
    local shaders = {} -- tent material key -> shader, or false when its texture could not be read
    local typeCache = {} -- uname -> item type with its names in the local player's language (lang.itemType)
    -- Items riding in a towed walk-in trailer (the vehicles resource lists them in the trailer's "vehicles.cargo"
    -- element data as { id, lx, ly, lz, lrz }: their stored spot in the trailer's frame): id -> { vehicle, lx, ly, lz,
    -- lrz, attached, dz }. Their objects hang on the trailer until the list drops them and their row comes again.
    local riding = {}
    -- A staff member's /replay hides the live items for that client only (setWorldHidden): their elements move to a
    -- dimension nobody is in, and elements built for the replay itself (buildReplayRow) ignore it.
    local HIDE_DIM = 65000
    local hidden = false
    local replayEntries = {} -- handle -> entry built by buildReplayRow, never listed in `objects`
    local nextReplayHandle = 0

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

    -- What empty hands do to a built defence (building handleDefenceInteract), which is never picked up again: a
    -- motor moves it (behind its keypad's code when it has one), a Large Frame puts its covering on or takes it off,
    -- anything else does nothing (nil)
    local function defenceVerb(uname, def)
        if def.motor then
            return lang.text("Activate")
        elseif uname == "LargeFrame" then
            return lang.text("Use")
        end
        return nil
    end

    local function formatName(t, r)
        -- upstream labels a built defence with its hitpoints (defences.pwn SetItemLabel "%d/%d"); a third line names
        -- what is fitted to it: its Motor, and the keypad on it (a keypad needs the motor)
        local def = t and builtDefence(r)
        if def then
            local hp = math.floor(tonumber(r.hp) or 0)
            local label = string.format("%s\n%d/%d", t.name, hp, t.maxHitpoints or 0)
            local fitted = {}
            if def.motor then
                fitted[#fitted + 1] = lang.itemName("Motor")
            end
            local keypad = tonumber(def.keypad)
            if keypad then
                fitted[#fitted + 1] = lang.itemName(keypad == 2 and "AdvancedKeypad" or "Keypad")
            end
            if #fitted > 0 then
                label = label .. "\n" .. table.concat(fitted, " + ")
            end
            return label
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
            return small.carBatteryLabel(
                t and t.name or r.uname,
                small.carBatteryCharge(r.id, r.data),
                small.carBatteryCapacity(r.id, r.data)
            )
        end
        if r.uname == "Key" then
            return small.keyLabel(t and t.name or r.uname, r.data, vehicleTypeByModel)
        end
        if r.uname == "WheelLock" or r.uname == "Padlock" then
            return small.lockLabel(t and t.name or r.uname, r.data)
        end
        if r.uname == "ComboPadlock" then
            return small.comboLabel(t and t.name or r.uname, r.data)
        end
        if r.uname == "FloodLight" then
            return floodlight.label(t and t.name or r.uname, r.data)
        end
        if r.uname == machines.GENERATOR_UNAME then
            return power.label(t and t.name or r.uname, r.data)
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

    -- every element an item draws with, destroyed (a row that left the world, or a replay's version of one)
    local function destroyEntry(e, id)
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
        if not e.replay then
            floodlight.clear(id, e)
            power.clear(id, e)
        end
        if isElement(e.shown) then
            destroyElement(e.shown)
        end
        if isElement(e.covering) then
            destroyElement(e.covering)
        end
    end

    local function forget(id)
        local e = objects[id]
        if e then
            destroyEntry(e, id)
            objects[id] = nil
        end
        labelVisibility[id] = nil
        reachCache[id] = nil
        passCache[id] = nil
    end

    local REACH_CACHE_MS = 250
    local REACH_RAY_STEPS = 6 -- items and held objects a ray may pass through before it counts as blocked
    local SINK_ALLOW = 0.25 -- a surface this close to the origin is the ground the item is clipped into, not a floor
    local PANEL_SUNK, PANEL_SUNK_Z = 0.45, 0.8 -- how far behind a wall a Crowbar still reaches a built defence
    local F = false

    -- a ray from the chest to a point; items and carried objects are passed through, anything else blocks it, and
    -- so does a built defence other than the target's own model (ign): a motor that moved it aside moved it off the ray.
    -- blocked, the blocking surface's z, that element, and the surface's x and y. Steps that run out count as
    -- blocked with no surface.
    local function rayCast(sx, sy, sz, tx, ty, tz, ign)
        local own = ign
        for _ = 1, REACH_RAY_STEPS do
            local left = getDistanceBetweenPoints3D(sx, sy, sz, tx, ty, tz)
            if left < 0.001 then
                return false
            end
            local hit, hx, hy, hz, el = processLineOfSight(sx, sy, sz, tx, ty, tz, true, F, F, true, F, F, F, F, ign)
            if not hit then
                return false
            end
            local passable = el
                and (el == own or (not defenceElements[el] and (itemElements[el] or getElementAttachedTo(el))))
            if not passable then
                return true, hz, el, hx, hy
            end
            local k = math.min(0.001, getDistanceBetweenPoints3D(hx, hy, hz, tx, ty, tz)) / left
            sx, sy, sz = hx + (tx - sx) * k, hy + (ty - sy) * k, hz + (tz - sz) * k
            ign = el
        end
        return true
    end

    local function rayClear(sx, sy, sz, tx, ty, tz, ign)
        return not rayCast(sx, sy, sz, tx, ty, tz, ign)
    end

    -- The higher target helps with uneven ground. A surface within SINK_ALLOW of the origin is ground the item is
    -- clipped into, so the raised aim may cross it. A hit further above, or any built defence, stays a floor or roof.
    local function reachable(id, e, fresh)
        local now = getTickCount()
        local cached = reachCache[id]
        local tool = ctx.heldUname and ctx.heldUname() or nil
        if not fresh and cached and cached.tool == tool and now - cached.at < REACH_CACHE_MS then
            return cached.ok
        end
        local sx, sy, sz = getElementPosition(localPlayer)
        sz = sz + 0.5
        local own = isElement(e.obj) and e.obj or nil
        local low, high = e.z + 0.05, e.z + 0.6
        local ok = rayClear(sx, sy, sz, e.x, e.y, low, own)
        local raised = false
        if not ok then
            local blocked, hz, el = rayCast(e.x, e.y, low, e.x, e.y, high, own)
            local skin = blocked and hz ~= nil and hz <= e.z + SINK_ALLOW and not (el and defenceElements[el])
            raised = not blocked or skin
            ok = raised and rayClear(sx, sy, sz, e.x, e.y, high, own)
        end
        -- A mounted panel sits sunk into the wall or the window it covers: built by a player pressed against it,
        -- its centre lies 20 to 30 cm behind that surface. Crowbar work reaches it through a surface up to
        -- PANEL_SUNK in front of it, measured flat so a panel high on the wall counts the same (and no more than
        -- PANEL_SUNK_Z above or below the aim, so no floor or ceiling); another built defence still blocks, and
        -- loose-item pickup never gets this allowance. The server still checks the tool, inside face, distance
        -- and hold before removing a defence.
        if not ok and e.defence and tool == "Crowbar" then
            for _, height in ipairs({ 0.15, 0.6 }) do
                local tz = e.z + height
                local blocked, hz, el, hx, hy = rayCast(sx, sy, sz, e.x, e.y, tz, own)
                local sunk = blocked
                    and hx ~= nil
                    and not (el and defenceElements[el])
                    and (hx - e.x) ^ 2 + (hy - e.y) ^ 2 <= PANEL_SUNK * PANEL_SUNK
                    and math.abs(hz - tz) <= PANEL_SUNK_Z
                if not blocked or sunk then
                    ok = true
                    break
                end
            end
        end
        -- Large loose items may have a visible edge even when their origin lies in masonry, and so may a mounted
        -- panel turned off the wall's line (one end in the room, its centre deeper than the inset above): the
        -- Crowbar reaches that end. Sample inside their transformed bounds; every sample still needs an
        -- unobstructed ray.
        local t = itemType(e.uname)
        local looseLarge = raised and not e.defence and t and (t.size or 0) >= 9
        local skewedPanel = e.defence and tool == "Crowbar"
        if not ok and own and (looseLarge or skewedPanel) then
            local ax, ay, az, bx, by, bz = models.bounds(own)
            local m = getElementMatrix(own)
            if ax and m then
                local samples = {
                    { 0.1, 0.5, 0.5 },
                    { 0.9, 0.5, 0.5 },
                    { 0.5, 0.1, 0.5 },
                    { 0.5, 0.9, 0.5 },
                    { 0.5, 0.5, 0.1 },
                    { 0.5, 0.5, 0.9 },
                }
                for _, sample in ipairs(samples) do
                    local lx = ax + (bx - ax) * sample[1]
                    local ly = ay + (by - ay) * sample[2]
                    local lz = az + (bz - az) * sample[3]
                    local tx = m[4][1] + lx * m[1][1] + ly * m[2][1] + lz * m[3][1]
                    local ty = m[4][2] + lx * m[1][2] + ly * m[2][2] + lz * m[3][2]
                    local tz = m[4][3] + lx * m[1][3] + ly * m[2][3] + lz * m[3][3]
                    if
                        getDistanceBetweenPoints3D(sx, sy, sz, tx, ty, tz) <= 2.5
                        and rayClear(sx, sy, sz, tx, ty, tz, own)
                    then
                        ok = true
                        break
                    end
                end
            end
        end
        reachCache[id] = { ok = ok, at = now, tool = tool }
        return ok
    end

    -- the point of a large item's footprint (its bounds, flat) nearest to (px, py): a table's edge is what a player
    -- standing against it faces, its centre may lie off to the side. Small items: their position.
    local function nearestFootprintPoint(e, px, py)
        local t = itemType(e.uname)
        local obj = isElement(e.obj) and e.obj or nil
        if not obj or e.defence or not t or (t.size or 0) < 9 then
            return e.x, e.y
        end
        local ax, ay, _, bx, by = models.bounds(obj)
        local m = getElementMatrix(obj)
        if not ax or not m then
            return e.x, e.y
        end
        -- the player in the object's frame (the rotation part is orthonormal: its transpose inverts it)
        local rx, ry, rz = px - m[4][1], py - m[4][2], 0
        local lx = rx * m[1][1] + ry * m[1][2] + rz * m[1][3]
        local ly = rx * m[2][1] + ry * m[2][2] + rz * m[2][3]
        lx = math.max(ax, math.min(bx, lx))
        ly = math.max(ay, math.min(by, ly))
        return m[4][1] + lx * m[1][1] + ly * m[2][1], m[4][2] + lx * m[1][2] + ly * m[2][2]
    end

    -- true when the player is turned towards the world item: within FACING_COS of the ped's heading, or so close
    -- (under FACING_FREE metres, flat) that it lies at the feet. Standing beside a box or with the back to it
    -- offers nothing. A large item is faced through the nearest point of its footprint.
    local FACING_COS = math.cos(math.rad(60))
    local FACING_FREE = 0.6
    local function faced(e)
        local px, py = getElementPosition(localPlayer)
        local tx, ty = nearestFootprintPoint(e, px, py)
        local dx, dy = tx - px, ty - py
        local len = math.sqrt(dx * dx + dy * dy)
        if len < FACING_FREE then
            return true
        end
        local _, _, rz = getElementRotation(localPlayer)
        local a = math.rad(rz)
        return (-math.sin(a) * dx + math.cos(a) * dy) / len >= FACING_COS
    end

    -- an item F acts on: faced, and no wall in between
    local function inReach(id, e)
        return faced(e) and reachable(id, e)
    end

    -- true when the item can come to the player's hands: the way to it is open at knee height (the player walks up
    -- to it), or its cross-section, carried along the line from where it lies to the hands, clears every wall. A
    -- workbench seen through a window is opened there, never lifted out through it; a can on the sill still is.
    local PASS_SHRINK = 0.8 -- the bounds are loose and a carried item may tilt a little
    local function passes(id, e, fresh)
        local now = getTickCount()
        local cached = passCache[id]
        if not fresh and cached and now - cached.at < REACH_CACHE_MS then
            return cached.ok
        end
        local own = isElement(e.obj) and e.obj or nil
        local sx, sy, sz = getElementPosition(localPlayer)
        local kz = sz - 0.5
        local ok = not own or rayClear(sx, sy, kz, e.x, e.y, math.max(kz, e.z + 0.15), own)
        if not ok then
            ok = true
            local ax, ay, az, bx, by, bz = models.bounds(own)
            local m = getElementMatrix(own)
            if ax and m then
                local lx, ly, lz = (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2
                local cx = m[4][1] + lx * m[1][1] + ly * m[2][1] + lz * m[3][1]
                local cy = m[4][2] + lx * m[1][2] + ly * m[2][2] + lz * m[3][2]
                local cz = m[4][3] + lx * m[1][3] + ly * m[2][3] + lz * m[3][3]
                local hz = sz + 0.3
                local dx, dy, dz = sx - cx, sy - cy, hz - cz
                local flat = math.sqrt(dx * dx + dy * dy)
                local len = math.sqrt(dx * dx + dy * dy + dz * dz)
                if flat > 0.05 then
                    dx, dy, dz = dx / len, dy / len, dz / len
                    -- u: across the way, level; v = d x u: up the way
                    local ux, uy, uz = -dy * len / flat, dx * len / flat, 0
                    local vx, vy, vz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux
                    local half = { (bx - ax) / 2, (by - ay) / 2, (bz - az) / 2 }
                    local wu, wv = 0, 0
                    for i = 1, 3 do
                        local a = m[i]
                        wu = wu + math.abs(a[1] * ux + a[2] * uy + a[3] * uz) * half[i]
                        wv = wv + math.abs(a[1] * vx + a[2] * vy + a[3] * vz) * half[i]
                    end
                    wu, wv = wu * PASS_SHRINK, wv * PASS_SHRINK
                    for _, i in ipairs({ -1, 0, 1 }) do
                        for _, j in ipairs({ -1, 0, 1 }) do
                            local ox = i * wu * ux + j * wv * vx
                            local oy = i * wu * uy + j * wv * vy
                            local oz = i * wu * uz + j * wv * vz
                            if ok and not rayClear(cx + ox, cy + oy, cz + oz, sx + ox, sy + oy, hz + oz, own) then
                                ok = false
                            end
                        end
                    end
                end
            end
        end
        passCache[id] = { ok = ok, at = now }
        return ok
    end

    -- an item in reach that empty hands would lift but that does not fit through the way (passes): the hold and the
    -- chooser offer no pickup and the server leaves it out of one; containers and machines still open on a tap
    local function stuck(id, e, fresh)
        if e.defence or (ctx.heldUname and ctx.heldUname()) or machines.isMachine(e.uname) then
            return false
        end
        local t = itemType(e.uname)
        return not (t and t.category == "safebox") and not passes(id, e, fresh)
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
        if e.obj then
            defenceElements[e.obj] = e.defence or nil
        end
        if e.covering then
            defenceElements[e.covering] = true
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
        setElementDimension(obj, hidden and not r.replay and HIDE_DIM or r.dimension or 0)
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
    -- A defence lying flat (built so or opened by a Motor) lies on the slope the building server measured under it
    -- (its state's gnx / gny; the row's normal for one built lying before that); a standing one stays upright, and so
    -- does a Large Frame, whose covering is drawn level over it.
    local function tiltToGround(obj, r, def)
        local nx, ny = tonumber(r.ground_nx) or 0, tonumber(r.ground_ny) or 0
        if def and def.gnx then
            nx, ny = tonumber(def.gnx) or 0, tonumber(def.gny) or 0
        end
        if nx ~= 0 or ny ~= 0 then
            setElementMatrix(obj, geometry.tilt(getElementMatrix(obj), nx, ny))
        end
    end
    local function orient(obj, r, t)
        -- loose items are walked through; a built defence is a wall (upstream's defence objects collide), and so are a
        -- Locker, which stands as tall as a player, the furniture (#148) and any type marked `collides`
        local def = builtDefence(r)
        setElementCollisionsEnabled(
            obj,
            def ~= nil
                or (t and t.collides == true)
                or r.uname == small.LOCKER.uname
                or furniture.is(r.uname)
                or vending.is(r.uname)
        )
        -- a hidden live row needs no collision change here: its hide dimension already keeps it out of reach, and
        -- turning collisions off would outlast setHidden(false)
        if def then
            -- its row already holds the raised z and full heading, data the pose
            setElementPosition(obj, r.x, r.y, r.z)
            setElementRotation(obj, def.rx or 0, def.ry or 0, r.rz or 0)
            if def.pose == "horizontal" and r.uname ~= "LargeFrame" then
                tiltToGround(obj, r, def)
            end
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
        tiltToGround(obj, r)
    end

    -- A defence a Motor (or a keypad) moves swings into its new pose over SWING_MS instead of jumping there: one turn
    -- about the line that stays put (geometry.motion), eased in and out. obj -> { mo, start }; the object's collision
    -- goes with it, and it ends exactly on the pose orient() gave it.
    local SWING_MS = 1500
    local swings = {}
    local function startSwing(obj, from)
        local mo = geometry.motion(from, getElementMatrix(obj))
        if mo.angle == 0 and math.abs(mo.slide[1]) + math.abs(mo.slide[2]) + math.abs(mo.slide[3]) < 0.01 then
            return
        end
        setElementMatrix(obj, from)
        swings[obj] = { mo = mo, start = getTickCount() }
    end
    addEventHandler("onClientPreRender", root, function()
        if next(swings) == nil then
            return
        end
        local now = getTickCount()
        for obj, sw in pairs(swings) do
            if not isElement(obj) then
                swings[obj] = nil
            else
                local s = math.min(1, (now - sw.start) / SWING_MS)
                setElementMatrix(obj, geometry.motionAt(sw.mo, s * s * (3 - 2 * s)))
                if s >= 1 then
                    swings[obj] = nil
                end
            end
        end
    end)

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
                setElementDimension(fx, hidden and not r.replay and HIDE_DIM or r.dimension or 0)
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
            setElementDimension(fx, hidden and not r.replay and HIDE_DIM or r.dimension or 0)
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
        -- a shut Combination Padlock draws its shackle down
        if r.uname == "ComboPadlock" and small.comboShut(r.data) then
            return models.forSamp(small.COMBO_SHUT_MODEL) or models.forType(t)
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

    -- the world resource (re)started with no lights of its own: every lit Flood Light registers with it again
    addEventHandler("onClientResourceStart", root, function(res)
        if getResourceName(res) ~= "world" then
            return
        end
        for id, e in pairs(objects) do
            if e.uname == "FloodLight" then
                floodlight.update(id, e, e.row)
            end
        end
    end)

    -- one world item's elements built from its row: the object (or a pitched tent's parts) and whatever hangs on it
    local function buildEntry(r, t, isPitched)
        local e = {
            pitched = isPitched,
            row = r,
            uname = r.uname,
            hp = r.hp,
            x = r.x,
            y = r.y,
            z = r.z,
            name = formatName(t, r),
            defence = builtDefence(r) ~= nil,
            replay = r.replay or nil,
        }
        if isPitched then
            e.parts = createTentParts(r)
        else
            e.obj = createItemObject(r, t)
        end
        updateFires(e, r)
        updatePlant(e, r)
        updateSmoke(e, r)
        if not r.replay then
            floodlight.update(r.id, e, r)
            power.update(r.id, e, r)
        end
        updateShown(e, r)
        updateCovering(e, r)
        updateVending(e, r)
        markItemElements(e)
        return e
    end

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
                    -- a built defence that changed pose swings there from wherever it is drawn now
                    local was, now = builtDefence(e.row), builtDefence(r)
                    local from = was and now and was.pose ~= now.pose and getElementMatrix(e.obj)
                    orient(e.obj, r, t)
                    if from then
                        startSwing(e.obj, from)
                    end
                end
                e.row = r
                updateFires(e, r)
                updatePlant(e, r)
                updateSmoke(e, r)
                floodlight.update(r.id, e, r)
                power.update(r.id, e, r)
                updateShown(e, r)
                updateCovering(e, r)
                updateVending(e, r)
                markItemElements(e)
            else
                e = buildEntry(r, t, isPitched)
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
        if hidden then
            return
        end
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
        for handle in pairs(replayEntries) do
            destroyEntry(replayEntries[handle], handle)
            replayEntries[handle] = nil
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

    -- The surface straight below a drop spot at ground height z (from 1 m over it to 2.5 m under it) when it is a
    -- built defence (a ramp or floor): hz, nx, ny and its object, else nil. The server's world has no built
    -- defences, so without this an item dropped on a ramp lands on the terrain under it. Loose items and carried
    -- objects are passed through: the server lays the item on those itself.
    function M.defenceSurfaceBelow(x, y, z)
        local sz, ez = z + 1.0, z - 2.5
        local ign
        for _ = 1, REACH_RAY_STEPS do
            if sz <= ez then
                return nil
            end
            local hit, _, _, hz, el, nx, ny = processLineOfSight(x, y, sz, x, y, ez, true, F, F, true, F, F, F, F, ign)
            if not hit then
                return nil
            end
            if el and defenceElements[el] then
                return hz, nx or 0, ny or 0, el
            end
            if not (el and (itemElements[el] or getElementAttachedTo(el))) then
                return nil
            end
            sz, ign = hz - 0.05, el
        end
        return nil
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
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 and inReach(id, e) then
                    return id, e.uname, machines.state(r.data).running == true
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

    -- the machine within reach (hud: a tap opens it, a hold its menu; the Generator's tap tells its fuel, the hold
    -- lifts it): id and type, or nil
    function M.nearbyMachine(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for id, e in pairs(objects) do
            if machines.isMachine(e.uname) then
                local r = e.row
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local same = (r.dimension or 0) == dim and (r.interior or 0) == int
                if same and dx * dx + dy * dy <= reach * reach and math.abs(dz) < 3 and inReach(id, e) then
                    return id, e.uname
                end
            end
        end
        return nil
    end

    -- the nearest bag or safebox lying within reach (upstream: a tap opens it, a hold picks it up): id, category,
    -- and true when it does not fit through the way to the player (opened there, never picked up)
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
                if same and math.abs(dz) < 3 and dist < nearestDist and inReach(id, e) then
                    -- a take-only one (the snack machine) stands where it is: "fixed", opened but never picked up
                    local fixed = t.categoryData and t.categoryData.takeOnly
                    nearest, nearestDist, nearestCategory = id, dist, fixed and "fixed" or t.category
                end
            end
        end
        return nearest, nearestCategory, nearest and not passes(nearest, objects[nearest]) or false
    end

    -- With a Hammer in hand at a defence lying unbuilt that the player faces: the chooser's two ways of building it
    -- (building defenceBuildRequested with the pose). Upstream built it standing with a Screwdriver and lying with a
    -- Hammer; here the Hammer does both and the player picks.
    local function buildActions(uname)
        local id = uname == "Hammer" and M.buildableDefence(2.0)
        local e = id and objects[id]
        local t = e and itemType(e.uname)
        if not t then
            return {}
        end
        local obj = isElement(e.obj) and e.obj or nil
        local name = t.name
        return {
            {
                id = "build:" .. id .. ":1",
                label = lang.text("Build standing up") .. " · " .. name,
                event = "defenceBuildRequested",
                target = id,
                action = "vertical",
                element = obj,
            },
            {
                id = "build:" .. id .. ":2",
                label = lang.text("Build lying flat") .. " · " .. name,
                event = "defenceBuildRequested",
                target = id,
                action = "horizontal",
                element = obj,
            },
        }
    end

    -- Explicit targets for the shared interaction chooser; never substitute a nearer item on selection. With
    -- something in hand (uname) only the build entries of a Hammer.
    function M.interactionActions(uname)
        if uname == power.CORD_UNAME then
            return power.heldActions(uname)
        end
        if uname then
            return buildActions(uname)
        end
        local actions = {}
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        for id, e in pairs(objects) do
            local r, t = e.row, itemType(e.uname)
            local dx, dy, dz = e.x - px, e.y - py, e.z - pz
            local def = e.defence and builtDefence(r)
            local defVerb = def and defenceVerb(e.uname, def)
            -- a pitched tent is no container and only a Crowbar packs it: the items lying in it are the targets
            if
                t
                and not e.pitched
                and (not def or defVerb)
                and (r.dimension or 0) == dim
                and (r.interior or 0) == int
                and dx * dx + dy * dy + dz * dz <= 4
                and inReach(id, e)
            then
                local verb = lang.text("Pick up")
                local event = "itemPickupRequested"
                local obj = isElement(e.obj) and e.obj or nil
                if def then
                    verb = defVerb
                elseif t.category == "bag" or t.category == "safebox" then
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
                elseif e.uname == power.CORD_UNAME and power.isPlugged(id) then
                    -- a plugged cord comes out only at its ends: here at the box, or at its Generator
                    verb, event = lang.text("Unplug the cord"), "cordUnplugRequested"
                elseif e.uname == machines.GENERATOR_UNAME then
                    for _, a in ipairs(power.generatorActions(id, obj)) do
                        actions[#actions + 1] = a
                    end
                    -- the lift is the carry entry below
                    verb = machines.state(r.data).running and lang.text("Stop generator")
                        or lang.text("Start generator")
                elseif machines.isMachine(e.uname) then
                    verb = lang.text("Access machine")
                end
                if e.uname == "FloodLight" then
                    for _, a in ipairs(floodlight.actions(id, e, t.name, obj)) do
                        actions[#actions + 1] = a
                    end
                end
                if e.uname == "Welder" then
                    actions[#actions + 1] = {
                        id = "torch:" .. id,
                        label = lang.text("Take torch") .. " · " .. t.name,
                        event = "weldTorchGrabRequested",
                        target = id,
                        element = obj,
                        item = true,
                    }
                end
                -- a plain pickup of an item that does not fit through the way is not offered
                local lifts = event == "itemPickupRequested" and verb == lang.text("Pick up")
                if not (lifts and stuck(id, e)) then
                    actions[#actions + 1] = {
                        id = "item:" .. id,
                        label = verb .. " · " .. t.name,
                        event = event,
                        target = id,
                        element = obj, -- hud outlines the selected entry's object in the world
                        -- not an item to pick up: the HUD shows this label on F instead of "Pick up"
                        item = not def,
                    }
                end
                local carried = e.uname == machines.GENERATOR_UNAME
                    or (
                        (t.category == "bag" or t.category == "safebox")
                        and not (t.categoryData and t.categoryData.takeOnly)
                    )
                if carried and passes(id, e) then
                    actions[#actions + 1] = {
                        id = "carry:" .. id,
                        label = lang.text("Pick up") .. " · " .. t.name,
                        event = "itemLongPickupRequested",
                        target = id,
                        element = obj,
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
            local def = e.defence and builtDefence(r)
            -- a built defence F does nothing to is no item in reach
            local inert = def and not defenceVerb(e.uname, def)
            if not inert and (r.dimension or 0) == dim and (r.interior or 0) == int then
                local dx, dy, dz = e.x - px, e.y - py, e.z - pz
                local dist = dx * dx + dy * dy + dz * dz
                if (not best or dist < best) and (dist > 9 or inReach(id, e)) then
                    best = dist
                end
            end
        end
        return best and math.sqrt(best) or false
    end

    -- What a Crowbar's F works on: a built defence it reaches (flat, the server's 2 m pickup radius, no wall between)
    -- or a constructed item it takes apart (crafting's removal recipes, its 2.5 m deconstruct radius) that the player
    -- faces. The one the camera looks at wins, else the one nearest the view centre within CROWBAR_AIM_COS, else the
    -- nearest. The hud outlines and names it and sends its id with the press, so the server works on that one.
    -- Checked at most every CROWBAR_TARGET_MS: id, object, uname, or false.
    local CROWBAR_AIM_COS = 0.94
    local CROWBAR_TARGET_MS = 100
    local deconstructSet = nil
    local crowbarPick = { at = -math.huge }
    local function deconstructable(uname)
        if not deconstructSet then
            local res = getResourceFromName("crafting")
            local list = res and getResourceState(res) == "running" and exports.crafting:deconstructables("Crowbar")
            if type(list) ~= "table" then
                return false -- asked again next time: crafting may not have started yet
            end
            deconstructSet = {}
            for _, u in ipairs(list) do
                deconstructSet[u] = true
            end
        end
        return deconstructSet[uname] == true
    end
    function M.crowbarTarget()
        local now = getTickCount()
        if now - crowbarPick.at < CROWBAR_TARGET_MS then
            local e = crowbarPick.id and objects[crowbarPick.id]
            if not e then
                return false
            end
            return crowbarPick.id, isElement(e.obj) and e.obj or false, e.uname
        end
        crowbarPick = { at = now }
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local cands = {}
        for id, e in pairs(objects) do
            local r = e.row
            if (r.dimension or 0) == dim and (r.interior or 0) == int and math.abs(e.z - pz) < 3 and not e.pitched then
                local dx, dy = e.x - px, e.y - py
                local flat = dx * dx + dy * dy
                local built = e.defence and builtDefence(r)
                if built and flat <= 4.0 and reachable(id, e) then
                    cands[#cands + 1] = { id = id, e = e, dist = flat }
                elseif not built and flat <= 6.0 and deconstructable(e.uname) and inReach(id, e) then
                    cands[#cands + 1] = { id = id, e = e, dist = flat }
                end
            end
        end
        if #cands == 0 then
            return false
        end
        local pick = nil
        if #cands > 1 then
            local cx, cy, cz, lx, ly, lz = getCameraMatrix()
            local fx, fy, fz = lx - cx, ly - cy, lz - cz
            local flen = math.sqrt(fx * fx + fy * fy + fz * fz)
            if flen > 0.001 then
                fx, fy, fz = fx / flen, fy / flen, fz / flen
                local yes, no = true, false
                local ex, ey, ez = cx + fx * 20, cy + fy * 20, cz + fz * 20
                local hit, _, _, _, el =
                    processLineOfSight(cx, cy, cz, ex, ey, ez, yes, no, no, yes, no, no, no, no, localPlayer)
                local bestCos = CROWBAR_AIM_COS
                for _, c in ipairs(cands) do
                    if hit and el and el == c.e.obj then
                        pick = c
                        break
                    end
                    local vx, vy, vz = c.e.x - cx, c.e.y - cy, c.e.z - cz
                    local len = math.sqrt(vx * vx + vy * vy + vz * vz)
                    local cos = len > 0.001 and (vx * fx + vy * fy + vz * fz) / len or -1
                    if cos > bestCos then
                        pick, bestCos = c, cos
                    end
                end
            end
        end
        if not pick then
            for _, c in ipairs(cands) do
                if not pick or c.dist < pick.dist then
                    pick = c
                end
            end
        end
        crowbarPick.id = pick.id
        return pick.id, isElement(pick.e.obj) and pick.e.obj or false, pick.e.uname
    end

    -- the world object of a world item, or false (the hud and a hold outline it)
    function M.objectOf(id)
        local e = objects[tonumber(id)]
        return e and isElement(e.obj) and e.obj or false
    end

    -- the nearest defence item lying unbuilt that the player faces and reaches (the server's pickup radius, flat):
    -- its id, else false. With a Hammer in hand the interaction chooser offers to build it (buildActions).
    function M.buildableDefence(reach)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local bestDist, bestId = reach * reach, nil
        for id, e in pairs(objects) do
            local r, t = e.row, itemType(e.uname)
            -- e.defence marks a built one only: an unbuilt defence is told by its type
            if t and t.defence and not builtDefence(r) and (r.dimension or 0) == dim and (r.interior or 0) == int then
                local dx, dy = e.x - px, e.y - py
                local dist = dx * dx + dy * dy
                if dist <= bestDist and math.abs(e.z - pz) < 3 and inReach(id, e) then
                    bestDist, bestId = dist, id
                end
            end
        end
        return bestId or false
    end

    local function pickupDistanceSquared(e, px, py, pz, dim, int)
        local r = e.row
        if (r.dimension or 0) == dim and (r.interior or 0) == int and not e.pitched then
            return (e.x - px) ^ 2 + (e.y - py) ^ 2 + (e.z - pz) ^ 2
        end
    end

    -- Only offer items that are present and reachable when F fires, including in a crowded loot pile.
    function M.pickupCandidates(reach, targetId)
        local px, py, pz = getElementPosition(localPlayer)
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local candidates, blocked = {}, false
        local tool = ctx.heldUname and ctx.heldUname()
        for id, e in pairs(objects) do
            local dist = pickupDistanceSquared(e, px, py, pz, dim, int)
            if dist and dist <= reach * reach then
                local aimedDefence = id == targetId and tool == "Crowbar" and e.defence
                if (aimedDefence or faced(e)) and reachable(id, e, true) and not stuck(id, e, true) then
                    candidates[#candidates + 1] = { id = id, dist = (id == targetId) and -1 or dist }
                else
                    blocked = true
                end
            end
        end
        table.sort(candidates, function(a, b)
            return a.dist < b.dist or (a.dist == b.dist and a.id < b.id)
        end)
        local ids = {}
        for i = 1, math.min(#candidates, 64) do
            ids[i] = candidates[i].id
        end
        return ids, blocked
    end

    function M.canCarryWorldItem(id, reach)
        local e = objects[id]
        if not e then
            return false
        end
        local px, py, pz = getElementPosition(localPlayer)
        local dist =
            pickupDistanceSquared(e, px, py, pz, getElementDimension(localPlayer), getElementInterior(localPlayer))
        return dist and dist <= reach * reach and faced(e) and reachable(id, e, true) and passes(id, e, true)
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

    -- /replay (staff): the live world items go away for this client only while a replay shows the world as it was.
    -- Their elements move to a dimension nobody is in (visibility and collision both follow), then come back.
    function M.setHidden(flag)
        flag = flag == true
        if hidden == flag then
            return
        end
        hidden = flag
        for _, e in pairs(objects) do
            local dim = flag and HIDE_DIM or e.row.dimension or 0
            for _, el in ipairs(elementsOf(e)) do
                setElementDimension(el, dim)
            end
        end
    end

    -- the model an item row draws with (a locker's open twin, a shut padlock, the type's stand-in), or false
    function M.modelOf(row)
        local t = itemType(row.uname)
        return t and modelFor(row, t) or false
    end

    -- A replay draws a row exactly as the live world does (same objects, tilts, tents, coverings, vending panes), but
    -- apart from the live ones: no labels, reach checks, lights or power. Returns a handle and the main element.
    function M.buildReplayRow(row)
        local t = itemType(row.uname)
        if not t then
            return false
        end
        row.replay = true
        local e = buildEntry(row, t, isPitchedTent(row))
        nextReplayHandle = nextReplayHandle + 1
        replayEntries[nextReplayHandle] = e
        return nextReplayHandle, e.obj or (e.parts and e.parts[1]) or false
    end

    function M.destroyReplayRow(handle)
        local e = replayEntries[handle]
        if e then
            destroyEntry(e, handle)
            replayEntries[handle] = nil
        end
    end

    function M.destroyReplayRows()
        for handle in pairs(replayEntries) do
            M.destroyReplayRow(handle)
        end
    end

    return M
end
