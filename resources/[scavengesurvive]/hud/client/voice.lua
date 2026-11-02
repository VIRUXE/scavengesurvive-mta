-- Voice chat HUD: tracks active speakers, renders the centre-left nickname list,
-- displays the local transmitting voice indicator, and draws 3D overhead icons.
return function(ctx)
    local canvas = ctx.canvas
    local c = ctx.c
    local getState = ctx.getState
    local voiceLogic = ctx.voiceLogic

    local talkingPlayers = {} -- playerElement -> startTick
    local localPlayerTalking = false

    local BLACK = tocolor(0, 0, 0, 255)
    local BG_INDICATOR = tocolor(0, 0, 0, 175)
    local BG_ROW = tocolor(0, 0, 0, 145)
    local GREEN_ACCENT = tocolor(51, 255, 102, 255)
    local GREEN_TEXT = tocolor(51, 255, 102, 255)
    local BLUE_ACCENT = tocolor(51, 204, 255, 210)
    local BLUE_ICON = tocolor(51, 204, 255, 240)
    local YELLOW_TEXT = tocolor(232, 232, 144, 255)

    -- Event handlers to keep talkingPlayers state fresh and accurate
    addEventHandler("onClientPlayerVoiceStart", root, function()
        if not isElement(source) or getElementType(source) ~= "player" then
            return
        end
        talkingPlayers[source] = getTickCount()
        if source == localPlayer then
            localPlayerTalking = true
        end
    end)

    addEventHandler("onClientPlayerVoiceStop", root, function()
        talkingPlayers[source] = nil
        if source == localPlayer then
            localPlayerTalking = false
        end
    end)

    addEventHandler("onClientPlayerVoicePause", root, function()
        talkingPlayers[source] = nil
        if source == localPlayer then
            localPlayerTalking = false
        end
    end)

    addEventHandler("onClientPlayerVoiceResumed", root, function()
        if not isElement(source) or getElementType(source) ~= "player" then
            return
        end
        talkingPlayers[source] = getTickCount()
        if source == localPlayer then
            localPlayerTalking = true
        end
    end)

    addEventHandler("onClientPlayerQuit", root, function()
        talkingPlayers[source] = nil
        if source == localPlayer then
            localPlayerTalking = false
        end
    end)

    addEventHandler("onClientElementDestroy", root, function()
        if getElementType(source) == "player" then
            talkingPlayers[source] = nil
            if source == localPlayer then
                localPlayerTalking = false
            end
        end
    end)

    addEventHandler("onClientPlayerWasted", root, function()
        talkingPlayers[source] = nil
        if source == localPlayer then
            localPlayerTalking = false
        end
    end)

    -- Server cancelled voice (e.g. muted or unauthenticated)
    addEventHandler("chatVoiceBlocked", root, function()
        if source == localPlayer then
            talkingPlayers[localPlayer] = nil
            localPlayerTalking = false
        end
    end)

    -- Helper to draw outlined text for maximum legibility against any GTA background
    local function drawOutlinedText(text, x, y, scaleX, scaleY, font, colour)
        dxDrawText(text, x - 1, y, x - 1, y, BLACK, scaleX, scaleY, font)
        dxDrawText(text, x + 1, y, x + 1, y, BLACK, scaleX, scaleY, font)
        dxDrawText(text, x, y - 1, x, y - 1, BLACK, scaleX, scaleY, font)
        dxDrawText(text, x, y + 1, x, y + 1, BLACK, scaleX, scaleY, font)
        dxDrawText(text, x, y, x, y, colour, scaleX, scaleY, font)
    end

    local function draw3DOverhead(player, isLocal)
        local isStreamed = (player == localPlayer) or isElementStreamedIn(player)
        if not isStreamed or not isElementOnScreen(player) then
            return
        end
        local hx, hy, hz = getPedBonePosition(player, voiceLogic.HEAD_BONE)
        if not hx or not hy or not hz then
            return
        end
        hz = hz + voiceLogic.WORLD_OFFSET
        local sx, sy = getScreenFromWorldPosition(hx, hy, hz)
        if not sx or not sy then
            return
        end
        local cx, cy, cz = getCameraMatrix()
        local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
        if dist > voiceLogic.MAX_DISTANCE or dist < 0.5 then
            return
        end
        -- Line of sight check: don't draw overhead icons through walls
        if not isLineOfSightClear(cx, cy, cz, hx, hy, hz, true, false, false, true, false, true, false, player) then
            return
        end
        local iconSize = voiceLogic.overheadScale(dist, c.sh)
        local iconColor
        if isLocal then
            iconColor = GREEN_ACCENT
        else
            local nr, ng, nb = getPlayerNametagColor(player)
            iconColor = tocolor(nr or 51, ng or 204, nb or 255, 230)
        end
        dxDrawImage(
            sx - iconSize / 2,
            sy - iconSize / 2,
            iconSize,
            iconSize,
            voiceLogic.ICON_PATH,
            0,
            0,
            0,
            iconColor,
            false
        )
    end

    local function render()
        if isVoiceEnabled and not isVoiceEnabled() then
            return
        end

        -- Build and validate speaker list
        local speakers = {}
        for player, startTick in pairs(talkingPlayers) do
            if isElement(player) and not isPedDead(player) then
                local isLocal = (player == localPlayer)
                speakers[#speakers + 1] = {
                    player = player,
                    name = getPlayerName(player),
                    isLocal = isLocal,
                    startTick = startTick or 0,
                }
            else
                talkingPlayers[player] = nil
            end
        end

        localPlayerTalking = (talkingPlayers[localPlayer] ~= nil)
        if #speakers == 0 then
            return
        end

        voiceLogic.sortSpeakers(speakers)

        -- 1. Draw 3D overhead icons above talking players
        for _, s in ipairs(speakers) do
            draw3DOverhead(s.player, s.isLocal)
        end

        -- 2. Draw centre-left nickname list and transmitting indicator
        local font = canvas.font(1)
        local scaleY = canvas.textScale(c, 1.35, 1)
        local scaleX = scaleY * canvas.xScale(1, 0.30, 1.35)
        local fontH = dxGetFontHeight(scaleY, font)
        local iconPx = canvas.len(c, voiceLogic.LAYOUT.iconSize)
        local padPx = canvas.len(c, voiceLogic.LAYOUT.padding)
        local accentW = canvas.len(c, voiceLogic.LAYOUT.accentWidth)

        local hudState = getState()
        local hasIndicator = localPlayerTalking
        local indicatorTitle = voiceLogic.indicatorTitle(hudState.chatMode or 0, hudState.frequency)

        -- Determine the maximum width to keep all rows in the block cleanly aligned
        local maxRowW = canvas.len(c, voiceLogic.LAYOUT.minWidth)
        if hasIndicator then
            local indTextW = dxGetTextWidth(indicatorTitle, scaleX, font)
            maxRowW = math.max(maxRowW, padPx * 3 + iconPx + indTextW)
        end
        for _, s in ipairs(speakers) do
            local displayName = voiceLogic.formatName(s.name, s.isLocal)
            local textW = dxGetTextWidth(displayName, scaleX, font)
            maxRowW = math.max(maxRowW, padPx * 3 + iconPx + textW)
        end

        local startYUnits = voiceLogic.blockGeometry(#speakers, hasIndicator)
        local curYUnits = startYUnits
        local px = canvas.x(c, voiceLogic.LAYOUT.x, "left")

        -- Draw the local transmitting indicator if the player is speaking
        if hasIndicator then
            local indH = canvas.len(c, voiceLogic.LAYOUT.indicatorHeight)
            local indY = canvas.y(c, curYUnits)
            dxDrawRectangle(px, indY, maxRowW, indH, BG_INDICATOR)
            dxDrawRectangle(px, indY, accentW, indH, GREEN_ACCENT)

            local pulse = 200 + math.floor(math.sin(getTickCount() / 150) * 55)
            local iconCol = tocolor(51, 255, 102, pulse)
            dxDrawImage(px + padPx, indY + (indH - iconPx) / 2, iconPx, iconPx, voiceLogic.ICON_PATH, 0, 0, 0, iconCol)

            local textX = px + padPx * 2 + iconPx
            local textY = indY + (indH - fontH) / 2
            drawOutlinedText(indicatorTitle, textX, textY, scaleX, scaleY, font, GREEN_TEXT)

            curYUnits = curYUnits + voiceLogic.LAYOUT.indicatorHeight + voiceLogic.LAYOUT.indicatorSpacing
        end

        -- Draw speaker nickname rows
        for _, s in ipairs(speakers) do
            local rowH = canvas.len(c, voiceLogic.LAYOUT.rowHeight)
            local rowY = canvas.y(c, curYUnits)
            dxDrawRectangle(px, rowY, maxRowW, rowH, BG_ROW)

            local accentCol, iconCol, textCol
            if s.isLocal then
                accentCol = GREEN_ACCENT
                iconCol = GREEN_ACCENT
                textCol = YELLOW_TEXT
            else
                accentCol = BLUE_ACCENT
                iconCol = BLUE_ICON
                local nr, ng, nb = getPlayerNametagColor(s.player)
                textCol = tocolor(nr or 255, ng or 255, nb or 255, 255)
            end

            dxDrawRectangle(px, rowY, accentW, rowH, accentCol)
            dxDrawImage(
                px + padPx,
                rowY + (rowH - iconPx) / 2,
                iconPx,
                iconPx,
                voiceLogic.ICON_PATH,
                0,
                0,
                0,
                iconCol,
                false
            )

            local displayName = voiceLogic.formatName(s.name, s.isLocal)
            local textX = px + padPx * 2 + iconPx
            local textY = rowY + (rowH - fontH) / 2
            drawOutlinedText(displayName, textX, textY, scaleX, scaleY, font, textCol)

            curYUnits = curYUnits + voiceLogic.LAYOUT.rowHeight + voiceLogic.LAYOUT.rowSpacing
        end
    end

    return {
        render = render,
        isTalking = function()
            return localPlayerTalking
        end,
    }
end
