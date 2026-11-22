-- Night Vision and Thermal Vision on the wearer's screen (shared/logic/goggles.lua, server/goggles.lua). The server
-- says which vision the worn goggles show ("items.vision" element data: "nightvision", "thermalvision" or false);
-- this client then
--   switches on GTA's own vision (setCameraGoggleEffect): it relights every ped, vehicle and object the way the
--     goggles see them (all green, or the living as heat against a cold world) and adds its grain; the world's
--     buildings follow through the blackout shader (world/client/blackout.lua reads the same element data);
--   draws the goggles' picture over it (client/goggles_night.fx, goggles_thermal.fx): night vision's amplified
--     green through two tubes, thermal's heat palette on a coarse sensor, the picture dipping as the battery runs
--     low;
--   shows the battery left under the picture.
-- The goggles key (the "goggles" command, J unless rebound) asks the server to switch them on or off.
-- ctx = { goggles, lang }
-- luacheck: read globals setCameraGoggleEffect dxCreateScreenSource dxUpdateScreenSource playSFX
return function(ctx)
    local goggles, lang = ctx.goggles, ctx.lang
    local KEY = "j"
    local SHADERS = { nightvision = "client/goggles_night.fx", thermalvision = "client/goggles_thermal.fx" }
    local WARM_MS = 900 -- the picture comes up over this long
    local SENSOR_ROWS = 240 -- the thermal sensor's lines
    local CLICK = { "genrl", 143, 64 } -- GTA's own goggles click (SND_BANK_GENRL_WEAPONS, NIGHT_VISION)

    local mode = "normal"
    local vision = false -- "items.vision", kept ahead of the element data (the change event fires before it changes)
    local onDuty = false -- "staff.duty", likewise
    local screenSource, shader
    local switchedAt = 0
    local dip, dipUntil = 1, 0

    local function free()
        if isElement(shader) then
            destroyElement(shader)
        end
        if isElement(screenSource) then
            destroyElement(screenSource)
        end
        shader, screenSource = nil, nil
    end

    local function click()
        local sound = playSFX(unpack(CLICK))
        if sound then
            setSoundVolume(sound, 0.6)
        end
    end

    local function apply()
        local next = SHADERS[vision] and vision or "normal"
        if isPedDead(localPlayer) or onDuty then
            next = "normal"
        end
        if next == mode then
            return
        end
        mode = next
        setCameraGoggleEffect(mode, true)
        click()
        free()
        if mode == "normal" then
            return
        end
        local sw, sh = guiGetScreenSize()
        screenSource = dxCreateScreenSource(sw, sh)
        shader = screenSource and dxCreateShader(SHADERS[mode]) or nil
        if not shader then
            return free() -- GTA's own vision still shows, without the goggles' picture
        end
        dxSetShaderValue(shader, "ScreenTexture", screenSource)
        if mode == "nightvision" then
            dxSetShaderValue(shader, "Aspect", sw / sh, 1)
        else
            dxSetShaderValue(shader, "Sensor", SENSOR_ROWS * sw / sh, SENSOR_ROWS)
        end
        switchedAt = getTickCount()
    end

    local function batteryLeft()
        return tonumber(getElementData(localPlayer, "items.eyesBattery")) or 0
    end

    local function draw()
        if mode == "normal" or not shader then
            return
        end
        local now = getTickCount()
        local left = batteryLeft()
        -- a battery running low makes the picture dip for a few frames now and then
        if now >= dipUntil then
            local low = left <= goggles.LOW and (1 - left / goggles.LOW) or 0
            if math.random() < 0.02 + 0.1 * low and low > 0 then
                dip, dipUntil = 0.35 + 0.4 * math.random(), now + 40 + math.random(120)
            else
                dip, dipUntil = 1, now + 60
            end
        end
        local warm = math.min(1, (now - switchedAt) / WARM_MS)
        local sw, sh = guiGetScreenSize()
        -- sampled now, so what was drawn before this (hunger's blur, the toxic cast) is seen through the goggles too
        dxUpdateScreenSource(screenSource, true)
        dxSetShaderValue(shader, "Power", dip * warm)
        if mode == "nightvision" then
            dxSetShaderValue(shader, "Time", (now % 100000) / 1000)
        end
        dxDrawImage(0, 0, sw, sh, shader)
        local s = sh / 480
        local colour = left <= goggles.LOW and tocolor(255, 90, 60, 220) or tocolor(200, 255, 200, 170)
        dxDrawText(
            lang.format("Battery %d%%", left),
            0,
            sh - 62 * s,
            sw,
            sh - 50 * s,
            colour,
            0.7 * s,
            "default-bold",
            "center",
            "center"
        )
    end

    addCommandHandler("goggles", function()
        if getElementData(localPlayer, "items.eyes") and not isPedDead(localPlayer) then
            triggerServerEvent("gogglesToggleRequested", localPlayer)
        end
    end)

    addEventHandler("onClientElementDataChange", localPlayer, function(key, _, value)
        if key == "items.vision" then
            vision = value or false
            apply()
        elseif key == "staff.duty" then
            onDuty = value == true
            apply()
        end
    end, false)

    -- the dead see nothing through them, and the server takes them off
    addEventHandler("onClientPlayerWasted", localPlayer, function()
        vision = false
        apply()
    end)

    addEventHandler("onClientResourceStart", resourceRoot, function()
        if not getKeyBoundToCommand("goggles") then
            bindKey(KEY, "down", "goggles")
        end
        -- under the HUD like hunger's screen effect, and after it
        addEventHandler("onClientHUDRender", root, draw, true, "low")
        vision = getElementData(localPlayer, "items.vision") or false
        onDuty = getElementData(localPlayer, "staff.duty") == true
        apply()
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        free()
        setCameraGoggleEffect("normal")
    end)
end
