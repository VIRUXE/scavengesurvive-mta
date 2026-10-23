local tent = dofile("resources/[scavengesurvive]/items/shared/logic/tent.lua")

describe("pitched tent geometry", function()
    local function near(a, b)
        return math.abs(a - b) < 0.001
    end
    it("builds four leaning camo panels and two poles around the pack, upstream order", function()
        local p = tent.parts(100, 200, 3, 0)
        assert.equals(6, #p)
        for i = 1, 4 do
            assert.equals(tent.PANEL, p[i].model)
            assert.is_true(near(p[i].z, 3.4))
            assert.equals(90, p[i].rz) -- the pack's heading plus 90
        end
        local materials = {}
        for i = 1, 6 do
            materials[i] = p[i].material
        end
        assert.same({ "net", "camo", "net", "camo", "pole", "pole" }, materials)
        assert.equals(45, p[1].ry)
        assert.equals(-45, p[3].ry)
        -- heading 0 + 90: the panels sit 0.49 / 0.48 along y either side of the pack (right side first, as upstream)
        assert.is_true(near(p[1].x, 100) and near(p[1].y, 199.51))
        assert.is_true(near(p[2].x, 100) and near(p[2].y, 199.52))
        assert.is_true(near(p[3].x, 100) and near(p[3].y, 200.49))
        assert.is_true(near(p[4].x, 100) and near(p[4].y, 200.48))
        -- the poles stand 1.3 m along x, 0.48 above the panels
        assert.equals(tent.POLE, p[5].model)
        assert.is_true(near(p[5].x, 98.7) and near(p[5].y, 200) and near(p[5].z, 3.88))
        assert.is_true(near(p[6].x, 101.3) and near(p[6].y, 200) and near(p[6].z, 3.88))
    end)
    it("turns with the pack's heading", function()
        local p = tent.parts(0, 0, 0, 90)
        assert.equals(180, p[1].rz)
        assert.is_true(near(p[5].x, 0) and near(p[5].y, -1.3))
        assert.is_true(near(p[6].x, 0) and near(p[6].y, 1.3))
        assert.is_true(near(p[1].x, 0.49) and near(p[1].y, 0))
    end)
    it("names the stock textures upstream reused", function()
        assert.same({ model = 2068, texture = "CJ_cammonet" }, tent.MATERIALS.net)
        assert.same({ model = 3095, texture = "sam_camo" }, tent.MATERIALS.camo)
        assert.same({ model = 1270, texture = "lamppost" }, tent.MATERIALS.pole)
    end)
end)
