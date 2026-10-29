local discordchat = dofile("resources/[scavengesurvive]/discordchat/shared/logic/discordchat.lua")

describe("discordchat logic", function()
    it("strips MTA hex color tags", function()
        assert.equals("PlayerName", discordchat.strip("#FF0000PlayerName"))
        assert.equals("Alice and Bob", discordchat.strip("Alice #00FF00and #0000FFBob"))
        assert.equals("#12345", discordchat.strip("#12345")) -- invalid hex length remains
    end)

    it("builds player.join payload with optional channel", function()
        assert.same({ player = "Alice" }, discordchat.joinPayload("Alice"))
        assert.same(
            { player = "Bob", channel = "1564285345426833608" },
            discordchat.joinPayload("#00FF00Bob", "1564285345426833608")
        )
        assert.is_nil(discordchat.joinPayload(""))
        assert.is_nil(discordchat.joinPayload(nil))
    end)

    it("builds player.quit payload for standard disconnects", function()
        local packet, payload = discordchat.quitPayload("Alice", "Quit", nil, nil, "1564285345426833608")
        assert.equals("player.quit", packet)
        assert.same({
            player = "Alice",
            type = "Quit",
            reason = false,
            channel = "1564285345426833608",
        }, payload)

        local p2, pl2 = discordchat.quitPayload("Bob", "Timed out", "Timeout", nil, nil)
        assert.equals("player.quit", p2)
        assert.same({
            player = "Bob",
            type = "Timed out",
            reason = "Timeout",
        }, pl2)
    end)

    it("builds player.kick payload", function()
        local packet, payload = discordchat.quitPayload("Troll", "Kicked", "Spamming", "Admin", "1564285345426833608")
        assert.equals("player.kick", packet)
        assert.same({
            player = "Troll",
            responsible = "Admin",
            reason = "Spamming",
            channel = "1564285345426833608",
        }, payload)

        -- Kicked with no admin defaults to Console
        local p2, pl2 = discordchat.quitPayload("AFK", "Kicked", nil, nil, "1564285345426833608")
        assert.equals("player.kick", p2)
        assert.same({
            player = "AFK",
            responsible = "Console",
            reason = false,
            channel = "1564285345426833608",
        }, pl2)
    end)

    it("builds player.ban payload", function()
        local packet, payload = discordchat.quitPayload("Cheater", "Banned", "Aimbot", "Admin", "1564285345426833608")
        assert.equals("player.ban", packet)
        assert.same({
            player = "Cheater",
            responsible = "Admin",
            reason = "Aimbot",
            channel = "1564285345426833608",
        }, payload)
    end)

    it("builds player.nickchange payload", function()
        local payload = discordchat.nickChangePayload("#FF0000OldNick", "NewNick", "1564285345426833608")
        assert.same({
            player = "NewNick",
            previous = "OldNick",
            channel = "1564285345426833608",
        }, payload)

        -- Same nick after stripping color codes returns nil
        assert.is_nil(discordchat.nickChangePayload("#FF0000Nick", "#00FF00Nick", "1564285345426833608"))
        assert.is_nil(discordchat.nickChangePayload("", "NewNick"))
    end)

    it("builds staff.log payload for item spawning", function()
        local packet, payload =
            discordchat.itemSpawnPayload("KingSergio", "M9Pistol", 42, "Fort Carson", "1563498523507425421")
        assert.equals("staff.log", packet)
        assert.same({
            player = "KingSergio",
            item = "M9Pistol",
            id = "42",
            zone = "Fort Carson",
            channel = "1563498523507425421",
            text = ":package: **KingSergio** spawned item **M9Pistol** (ID: 42) in Fort Carson",
        }, payload)

        -- Strips color codes and handles missing optional fields
        local p2, pl2 = discordchat.itemSpawnPayload("#FF0000KingSergio", "Wrench", nil, nil, nil)
        assert.equals("staff.log", p2)
        assert.same({
            player = "KingSergio",
            item = "Wrench",
            text = ":package: **KingSergio** spawned item **Wrench**",
        }, pl2)

        -- Empty player or item returns nil
        assert.is_nil(discordchat.itemSpawnPayload("", "M9Pistol"))
        assert.is_nil(discordchat.itemSpawnPayload("KingSergio", ""))
        assert.is_nil(discordchat.itemSpawnPayload(nil, "M9Pistol"))
    end)

    it("builds generic staff.log payload", function()
        local packet, payload = discordchat.staffLogPayload("Important staff note", "1563498523507425421")
        assert.equals("staff.log", packet)
        assert.same({
            text = "Important staff note",
            channel = "1563498523507425421",
        }, payload)

        assert.is_nil(discordchat.staffLogPayload(""))
        assert.is_nil(discordchat.staffLogPayload(nil))
    end)
end)
