-- The sound of breathing through a mask (shared/logic/masks.lua, sounds from tools/make_breath_sounds.py).
-- The local player hears the worn mask's own loop, heavier the better the mask protects: quiet and slow at rest,
-- louder and faster the more out of breath they are (sprinting and jumping wind them, the more so the more the
-- mask restricts), with a wheeze on top once the filter is spent. Players close by hear a respirator or a gas
-- mask on someone else, faintly.
-- ctx = { masks, worn(player) -> uname, data or nil }
-- luacheck: read globals getPedMoveState setSoundSpeed setSoundMaxDistance playSound3D
return function(ctx)
    local masks, worn = ctx.masks, ctx.worn
    local TICK_MS = 250
    local WIND_S = 9 -- seconds of sprinting to be fully out of breath (at restriction 1; longer with less)
    local REST_S = 12 -- seconds of rest to get the breath back
    local VOLUME = 0.125 -- of the loops as recorded: louder than that drowned the game out
    local QUIET, LOUD = 0.22, 1.0 -- share of the mask's volume at rest and out of breath
    local SLOW, FAST = 0.85, 1.55 -- the loop's speed at rest and out of breath
    local NEAR = 9 -- metres: how far someone else's mask is heard
    local OTHERS_VOLUME = 0.04
    local AUDIBLE = { respirator = true, gasmask = true } -- loops other players hear

    local own = { uname = nil, sound = nil, wheeze = nil }
    local effort = 0 -- 0 rested .. 1 out of breath
    local others = {} -- player -> sound

    local function stop(sound)
        if isElement(sound) then
            destroyElement(sound)
        end
    end

    local function file(spec)
        return "sounds/breath_" .. spec.sound .. ".wav"
    end

    local function silenceOwn()
        stop(own.sound)
        stop(own.wheeze)
        own.uname, own.sound, own.wheeze = nil, nil, nil
    end

    local function updateOwn()
        local uname, data = worn(localPlayer)
        local spec = uname and masks.spec(uname)
        if not spec or isPedDead(localPlayer) or getElementData(localPlayer, "staff.duty") == true then
            effort = 0
            return silenceOwn()
        end
        local restriction = masks.restriction(uname, data)
        -- out of breath: sprinting or in the air winds the player, standing or walking gives the breath back
        local state = getPedMoveState(localPlayer)
        local dt = TICK_MS / 1000
        if state == "sprint" or state == "jump" or state == "climb" then
            effort = math.min(1, effort + dt * (0.4 + restriction) / WIND_S)
        else
            effort = math.max(0, effort - dt / REST_S)
        end
        if own.uname ~= uname then
            silenceOwn()
            own.uname = uname
            own.sound = playSound(file(spec), true)
        end
        if isElement(own.sound) then
            setSoundVolume(own.sound, VOLUME * (0.35 + restriction) * (QUIET + (LOUD - QUIET) * effort))
            setSoundSpeed(own.sound, SLOW + (FAST - SLOW) * effort)
        end
        -- a spent filter whistles
        local spent = spec.kind == "filtered" and (tonumber(data.filter) or 100) <= 0
        if spent and not isElement(own.wheeze) then
            own.wheeze = playSound("sounds/breath_wheeze.wav", true)
        elseif not spent and own.wheeze then
            stop(own.wheeze)
            own.wheeze = nil
        end
        if isElement(own.wheeze) then
            setSoundVolume(own.wheeze, VOLUME * (0.35 + 0.45 * effort))
            setSoundSpeed(own.wheeze, SLOW + (FAST - SLOW) * effort)
        end
    end

    local function updateOthers()
        local x, y, z = getElementPosition(localPlayer)
        local seen = {}
        for _, player in ipairs(getElementsByType("player", root, true)) do
            if player ~= localPlayer and not isPedDead(player) then
                local uname = worn(player)
                local spec = uname and masks.spec(uname)
                local px, py, pz = getElementPosition(player)
                if spec and AUDIBLE[spec.sound] and getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= NEAR then
                    seen[player] = true
                    if not isElement(others[player]) then
                        local sound = playSound3D(file(spec), px, py, pz, true)
                        if sound then
                            attachElements(sound, player, 0, 0, 0.6)
                            setSoundMaxDistance(sound, NEAR)
                            setSoundVolume(sound, OTHERS_VOLUME)
                            others[player] = sound
                        end
                    end
                end
            end
        end
        for player, sound in pairs(others) do
            if not seen[player] then
                stop(sound)
                others[player] = nil
            end
        end
    end

    setTimer(function()
        updateOwn()
        updateOthers()
    end, TICK_MS, 0)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        silenceOwn()
        for _, sound in pairs(others) do
            stop(sound)
        end
    end)
end
