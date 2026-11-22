local discordchat = {}

function discordchat.strip(s)
    local cleaned = tostring(s or ""):gsub("#%x%x%x%x%x%x", "")
    return cleaned ~= "" and cleaned or tostring(s or "")
end

function discordchat.joinPayload(name, channel, langName)
    local player = discordchat.strip(name)
    if player == "" then
        return nil
    end
    local payload = { player = player }
    if channel then
        payload.channel = channel
    end
    if langName and langName ~= "" then
        payload.lang = langName
    end
    return payload
end

function discordchat.quitPayload(name, quitType, reason, respName, channel)
    local player = discordchat.strip(name)
    if player == "" then
        return nil, nil
    end

    local reasonStr = type(reason) == "string" and reason ~= "" and discordchat.strip(reason) or false

    if quitType == "Kicked" then
        local payload = {
            player = player,
            responsible = respName and discordchat.strip(respName) or "Console",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.kick", payload
    elseif quitType == "Banned" then
        local payload = {
            player = player,
            responsible = respName and discordchat.strip(respName) or "Console",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.ban", payload
    else
        local payload = {
            player = player,
            type = quitType or "Quit",
            reason = reasonStr,
        }
        if channel then
            payload.channel = channel
        end
        return "player.quit", payload
    end
end

function discordchat.nickChangePayload(previous, nick, channel)
    local prevClean = discordchat.strip(previous)
    local newClean = discordchat.strip(nick)
    if prevClean == "" or newClean == "" or prevClean == newClean then
        return nil
    end
    local payload = {
        player = newClean,
        previous = prevClean,
    }
    if channel then
        payload.channel = channel
    end
    return payload
end

function discordchat.itemSpawnPayload(playerName, itemUname, itemId, zone, channel)
    local player = discordchat.strip(playerName)
    local item = discordchat.strip(itemUname)
    if player == "" or item == "" then
        return nil, nil
    end
    local idStr = itemId and (" (ID: " .. tostring(itemId) .. ")") or ""
    local zoneClean = zone and discordchat.strip(zone) or nil
    local zoneStr = (zoneClean and zoneClean ~= "" and zoneClean ~= "none") and (" in " .. zoneClean) or ""
    local payload = {
        player = player,
        item = item,
        id = itemId and tostring(itemId) or nil,
        zone = (zoneClean and zoneClean ~= "" and zoneClean ~= "none") and zoneClean or nil,
        text = string.format(":package: **%s** spawned item **%s**%s%s", player, item, idStr, zoneStr),
    }
    if channel then
        payload.channel = channel
    end
    return "staff.log", payload
end

-- #spawns embeds -----------------------------------------------------------------------------------------------

local WIKI = "https://wiki.scavengesurvive-reborn.com/"
local FOOTER = "Scavenge & Survive"
local CATEGORY = {
    weapon = { colour = 0xC0392B },
    ammo = { label = "Ammunition", colour = 0xD4AC0D },
    food = { label = "Food", colour = 0x27AE60 },
    liquid = { label = "Liquid", colour = 0x2E86C1 },
    bag = { label = "Bag", colour = 0x8E44AD },
    safebox = { label = "Storage", colour = 0x7F8C8D },
    generic = { label = "Item", colour = 0x16A085 },
}

local function titleCase(s)
    return (tostring(s or ""):gsub("^%l", string.upper))
end

-- The item's type line: "Melee weapon", "Firearm · 7.62", "Ammunition · 9mm", "Food", ...
function discordchat.itemTypeLabel(def, calibreName)
    local cat = def and def.category or "generic"
    local data = def and def.categoryData or {}
    local cal = data.calibre and (calibreName and calibreName(data.calibre) or data.calibre)
    if cat == "weapon" then
        if data.melee then
            return "Melee weapon"
        end
        return cal and ("Firearm · " .. cal) or "Weapon"
    end
    local label = (CATEGORY[cat] or CATEGORY.generic).label
    return cal and (label .. " · " .. cal) or label
end

-- calibreName: calibre id -> display name. images: the spawn_images.lua table (version, items = uname -> png,
-- wiki = uname -> page). base: the renders' URL.
function discordchat.itemSpawnEmbed(def, uname, region, images, base, calibreName)
    local name = discordchat.strip(def and def.name or uname)
    if name == "" then
        return nil
    end
    local file = images and images.items and images.items[uname]
    local page = images and images.wiki and images.wiki[uname]
    local fields = {
        { name = "📍 Region", value = region ~= "" and region or "Unknown" },
        { name = "🏷️ Type", value = discordchat.itemTypeLabel(def, calibreName) },
    }
    if def and tonumber(def.size) then
        fields[#fields + 1] = { name = "🎒 Size", value = tostring(def.size) }
    end
    return {
        author = "📦 Loot spawned",
        title = name,
        url = page and (WIKI .. page) or nil,
        fields = fields,
        thumbnail = file and (base .. "items/" .. file .. "?v=" .. tostring(images.version or "1")) or nil,
        colour = (CATEGORY[def and def.category] or CATEGORY.generic).colour,
        footer = FOOTER,
    }
end

function discordchat.vehicleSpawnEmbed(vt, region)
    local name = discordchat.strip(vt and vt.name or "")
    if name == "" then
        return nil
    end
    local class = titleCase(vt.category)
    if vt.group and vt.group ~= "" then
        class = class ~= "" and (class .. " · " .. vt.group) or vt.group
    end
    local fields = { { name = "📍 Region", value = region ~= "" and region or "Unknown" } }
    if class ~= "" then
        fields[#fields + 1] = { name = "🚙 Class", value = class }
    end
    if tonumber(vt.trunkSize) and vt.trunkSize > 0 then
        fields[#fields + 1] = { name = "🧰 Trunk", value = tostring(vt.trunkSize) .. " slots" }
    end
    if not vt.noEngine and tonumber(vt.maxFuel) and vt.maxFuel > 0 then
        fields[#fields + 1] = { name = "⛽ Fuel tank", value = string.format("%d L", vt.maxFuel) }
    end
    return {
        author = "🚗 Vehicle spawned",
        title = name,
        url = WIKI .. "Vehicles",
        fields = fields,
        colour = 0xE67E22,
        footer = FOOTER,
    }
end

function discordchat.staffLogPayload(text, channel)
    local cleaned = discordchat.strip(text)
    if cleaned == "" then
        return nil, nil
    end
    local payload = {
        text = cleaned,
    }
    if channel then
        payload.channel = channel
    end
    return "staff.log", payload
end

return discordchat
