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
end)
