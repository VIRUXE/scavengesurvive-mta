local placement = dofile("resources/[scavengesurvive]/maps/shared/logic/placement.lua")

-- one shell (SA-MP 19489) with a single window facing +x: centre (6, 0, 1), 1 m either side, 0.7 m up and down
local glazed = { [19489] = { { 6, 0, 1, 1, 0, 1, 0.7 } } }

describe("maps placement glazed shells", function()
    it("drops a pane in an opening the shell glazes, rotated with the shell", function()
        local shell = { 19489, 100, 200, 10, 0, 0, 90 }
        -- turned 90 degrees, the +x window faces +y: local (6, 0.5, 1) lands at world (99.5, 206, 11)
        local pane = { 19466, 99.5, 206, 11, 0, 0, 90 }
        local rows, dropped = placement.dropGlazedPanes({ shell, pane }, glazed)
        assert.equals(1, dropped)
        assert.same({ shell }, rows)
    end)

    it("keeps panes beside the opening, other models in it and panes of unglazed shells", function()
        local shell = { 19489, 0, 0, 0, 0, 0, 0 }
        local beside = { 19466, 6, 2.5, 1, 0, 0, 0 } -- 1.5 m past the opening's end
        local door = { 1491, 6, 0, 1, 0, 0, 0 }
        local other = { 19491, 50, 0, 0, 0, 0, 0 }
        local otherPane = { 19325, 56, 0, 1, 0, 0, 0 }
        local rows, dropped = placement.dropGlazedPanes({ shell, beside, door, other, otherPane }, glazed)
        assert.equals(0, dropped)
        assert.equals(5, #rows)
    end)

    it("drops the upstream panes of every placed shell in the real maps", function()
        local data = dofile("resources/[scavengesurvive]/maps/shared/glazed_windows.lua")
        local rows = {}
        for zone in pairs(dofile("resources/[scavengesurvive]/maps/data/index.lua")) do
            for _, o in ipairs(dofile("resources/[scavengesurvive]/maps/data/" .. zone .. ".lua").objects or {}) do
                rows[#rows + 1] = o
            end
        end
        local _, dropped = placement.dropGlazedPanes(rows, data)
        assert.is_true(dropped > 1500, "dropped " .. dropped)
    end)
end)
