local mock = require("tests.lua.helpers.mta_mock")
local load = require("tests.lua.helpers.load_module")
describe("lib.net", function()
    local net
    before_each(function() mock.install(); net = load("net"); mock.addElement("p1"); mock.addElement("p2") end)
    it("registers a remote event and only runs when client == source", function()
        local seen = 0
        net.handler("onItemsRequestPickup", function(player) seen = seen + 1 end, { rate = 100 })
        assert.same({ "addEvent", "onItemsRequestPickup", true }, mock.calls[1])
        _G.client, _G.source = "p1", "p1"; mock.fire("onItemsRequestPickup")
        _G.client, _G.source = "p1", "p2"; mock.fire("onItemsRequestPickup")
        assert.equals(1, seen)
    end)
    it("rate limits per player per event", function()
        local seen = 0
        net.handler("onItemsRequestDrop", function() seen = seen + 1 end, { rate = 2 })
        _G.client, _G.source = "p1", "p1"
        for _ = 1, 5 do mock.fire("onItemsRequestDrop") end
        assert.equals(2, seen)
        mock.tick = 1001
        mock.fire("onItemsRequestDrop")
        assert.equals(3, seen)
    end)
    it("issues one-shot tokens that expire", function()
        local tok = net.issueToken("p1", "inv", 30)
        assert.is_false(net.consumeToken("p2", "inv", tok))
        assert.is_true(net.consumeToken("p1", "inv", tok))
        assert.is_false(net.consumeToken("p1", "inv", tok))
        local tok2 = net.issueToken("p1", "inv", 1)
        mock.tick = 5000
        assert.is_false(net.consumeToken("p1", "inv", tok2))
    end)
end)
