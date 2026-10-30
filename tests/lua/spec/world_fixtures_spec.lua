-- Tests for the fixed world items (upstream zone files' CreateItem): which are missing and get made again.
local fixtures = dofile("resources/[scavengesurvive]/world/shared/logic/fixtures.lua")
local data = dofile("resources/[scavengesurvive]/world/data/features.lua")

describe("world fixtures", function()
    local bench = { "Workbench", 100.0, 200.0, 5.0, 90.0, "sf" }
    local bench2 = { "Workbench", 300.0, 200.0, 5.0, 0.0, "sf" }

    it("makes a fixture again when nothing of its type lies at its spot", function()
        assert.same({ bench }, fixtures.missing({ bench }, {}))
        assert.same({ bench }, fixtures.missing({ bench }, { { type_uname = "Workbench", x = 110.0, y = 200.0 } }))
        assert.same({ bench }, fixtures.missing({ bench }, { { type_uname = "Barbecue", x = 100.0, y = 200.0 } }))
    end)

    it("leaves one that is still there, nudged a little", function()
        assert.same({}, fixtures.missing({ bench }, { { type_uname = "Workbench", x = "101.2", y = "200.5" } }))
    end)

    it("counts each world item for one fixture only", function()
        local close = { "Workbench", 101.0, 200.0, 5.0, 0.0, "sf" }
        local rows = { { type_uname = "Workbench", x = 100.5, y = 200.0 } }
        assert.same({ close }, fixtures.missing({ bench, close }, rows))
        assert.same({ bench2 }, fixtures.missing({ bench, bench2 }, rows))
    end)

    it("counts a tagged puzzle item as there only when a row nearby carries its tag", function()
        local battery = { "Battery", -2316.15, -1646.64, 483.43, 32.04, "mtchill", "mtchill.ch_battery" }
        local plain = { type_uname = "Battery", x = -2316.0, y = -1646.5 }
        local tagged = { type_uname = "Battery", x = -2316.0, y = -1646.5, tag = "mtchill.ch_battery" }
        local other = { type_uname = "Battery", x = -2316.0, y = -1646.5, tag = "mtchill.ch_fusebox" }
        assert.same({ battery }, fixtures.missing({ battery }, { plain }))
        assert.same({ battery }, fixtures.missing({ battery }, { other }))
        assert.same({}, fixtures.missing({ battery }, { tagged }))
        assert.same({}, fixtures.missing({ battery }, { plain, tagged }))
    end)

    it("lists the fixture types once, sorted", function()
        assert.same({ "Barbecue", "Workbench" }, fixtures.types({ bench, { "Barbecue", 0, 0, 0, 0, "sf" }, bench2 }))
    end)

    it("has upstream's 15: 11 workbenches, the two scrapyard machines, a barbecue and the LV joke item", function()
        local count = {}
        for _, f in ipairs(data.fixtures) do
            count[f[1]] = (count[f[1]] or 0) + 1
        end
        assert.same({ Workbench = 11, ScrapMachine = 1, RefineMachine = 1, Barbecue = 1, Dildo2 = 1 }, count)
    end)
end)
