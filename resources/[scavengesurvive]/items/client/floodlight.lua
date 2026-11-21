-- luacheck: read globals createLight
-- The Flood Light on the client (shared/logic/floodlight.lua has the rules, server/floodlight.lua the power): a lit
-- one lying in the world lights the walls and objects round it through the world resource's blackout shader
-- (world:setLight), peds and vehicles through a GTA point light (createLight), and its face glows (a corona). The
-- interaction chooser offers to switch it on or off and to take its battery out (floodLightActionRequested).
-- ctx = { flood, lang } from client/main.lua.
return function(ctx)
    local flood, lang = ctx.flood, ctx.lang

    -- the extras a lit one draws with, on its world entry e: e.light (the point light), e.corona
    local function clear(id, e)
        if isElement(e.light) then
            destroyElement(e.light)
        end
        if isElement(e.corona) then
            destroyElement(e.corona)
        end
        e.light, e.corona = nil, nil
        local res = getResourceFromName("world")
        if e.lit and res and getResourceState(res) == "running" then
            exports.world:removeLight("flood:" .. id)
        end
        e.lit = nil
    end

    -- the row came (again): lit, it shines from its lamp along its aim
    local function update(id, e, r)
        clear(id, e)
        if r.uname ~= flood.UNAME or not flood.isLit(r.data) or not isElement(e.obj) then
            return
        end
        local x, y, z, dx, dy, dz = flood.lampPose(getElementMatrix(e.obj))
        local c = flood.COLOUR
        local int, dim = r.interior or 0, r.dimension or 0
        -- the point light for peds and vehicles sits a little in front of the face, so the light's own stand is lit
        local light = createLight(0, x + dx * 0.5, y + dy * 0.5, z + dz * 0.5, flood.PED_LIGHT_RADIUS, 255, 240, 210)
        if light then
            setElementInterior(light, int)
            setElementDimension(light, dim)
            e.light = light
        end
        local corona = createMarker(x + dx * 0.03, y + dy * 0.03, z + dz * 0.03, "corona", 0.45, 255, 244, 220, 150)
        if corona then
            setElementInterior(corona, int)
            setElementDimension(corona, dim)
            e.corona = corona
        end
        local res = getResourceFromName("world")
        if res and getResourceState(res) == "running" then
            local rad = flood.RADIUS
            exports.world:setLight("flood:" .. id, x, y, z, dx, dy, dz, rad, c[1], c[2], c[3], int, dim)
        end
        e.lit = true
    end

    -- the label over it: whether it has a battery and how much is left
    local function label(name, data)
        local b = flood.battery(data)
        if not b then
            return lang.format("%s (no battery)", name)
        end
        return lang.format("%s (battery %d%%)", name, flood.percent(b))
    end

    -- the chooser's entries for a Flood Light within reach (client/world.lua interactionActions)
    local function actions(id, e, name, obj)
        local out = {
            {
                id = "flood:" .. id .. ":toggle",
                label = (flood.isLit(e.row.data) and lang.text("Switch off") or lang.text("Switch on"))
                    .. " · "
                    .. name,
                event = "floodLightActionRequested",
                target = id,
                action = "toggle",
                element = obj,
                item = true,
            },
        }
        if flood.battery(e.row.data) then
            out[#out + 1] = {
                id = "flood:" .. id .. ":battery",
                label = lang.text("Take the battery out") .. " · " .. name,
                event = "floodLightActionRequested",
                target = id,
                action = "battery",
                element = obj,
                item = true,
            }
        end
        return out
    end

    return { update = update, clear = clear, label = label, actions = actions }
end
