-- Voice chat HUD logic: layout calculations, nickname formatting, and 3D overhead icon scaling.
local voice = {}

voice.MAX_DISTANCE = 40.0 -- chat.LOCAL_RANGE (40 m)
voice.HEAD_BONE = 8 -- GTA ped head bone
voice.WORLD_OFFSET = 0.4 -- 0.4 m above head bone
voice.ICON_PATH = "images/voice.png"

-- Layout dimensions in 640x480 canvas units
voice.LAYOUT = {
    x = 20, -- left anchor
    centerY = 240, -- vertical centre of 480 canvas
    rowHeight = 18,
    rowSpacing = 3,
    iconSize = 14,
    accentWidth = 3,
    padding = 5,
    minWidth = 100,
    indicatorHeight = 20,
    indicatorSpacing = 4,
}

-- Mode names (chat.MODE: 0 local, 1 global, 2 radio, 3 admin)
voice.MODE_NAMES = {
    [0] = "LOCAL",
    [1] = "GLOBAL",
    [2] = "RADIO",
    [3] = "ADMIN",
}

-- Formats the indicator header text when the local player is talking
function voice.indicatorTitle(mode, freq)
    local modeName = voice.MODE_NAMES[mode] or "LOCAL"
    if mode == 2 and freq then
        return string.format("TALKING [%.2f]", tonumber(freq) or 98.12)
    end
    return string.format("TALKING [%s]", modeName)
end

-- Formats nickname for display in the centre-left list
function voice.formatName(name, isLocal)
    if isLocal then
        return string.format("%s (You)", name or "Player")
    end
    return name or "Player"
end

-- Sorts speakers: local player first, then sorted by start tick ascending, then name
function voice.sortSpeakers(speakers)
    table.sort(speakers, function(a, b)
        if a.isLocal ~= b.isLocal then
            return a.isLocal == true
        end
        if (a.startTick or 0) ~= (b.startTick or 0) then
            return (a.startTick or 0) < (b.startTick or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    return speakers
end

-- Computes the vertical start Y to centre the entire block around centerY (240 units)
function voice.blockGeometry(speakerCount, hasIndicator)
    local L = voice.LAYOUT
    local count = math.max(0, speakerCount or 0)
    local indH = hasIndicator and (L.indicatorHeight + L.indicatorSpacing) or 0
    local listH = count > 0 and (count * L.rowHeight + (count - 1) * L.rowSpacing) or 0
    local totalH = indH + listH
    local startY = math.max(100, math.min(340, L.centerY - totalH / 2))
    return startY, totalH
end

-- Computes 3D overhead voice icon size in pixels based on camera distance
-- Non-linear scaling: 81 px at 1-2 m, 68 px at 5 m, 45 px at 10 m, 30 px at 20 m (scaled for 1080p)
function voice.overheadScale(distance, screenH)
    distance = math.max(1.0, distance or 1.0)
    local s = (screenH or 480) / 480
    local base = 80.0 * s
    local size = base / (distance ^ 0.6)
    return math.max(12.0 * s, math.min(36.0 * s, size))
end

return voice
