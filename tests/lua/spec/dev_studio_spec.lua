local studio = dofile("resources/[scavengesurvive]/dev/shared/logic/studio.lua")

local function near(a, b)
    return math.abs(a - b) < 1e-9
end

describe("dev studio", function()
    it("builds a closed box of 36 vertices, every one on a corner of the box", function()
        local v = studio.boxTriangles(-1, -2, -3, 1, 2, 3)
        assert.equals(36, #v)
        for _, p in ipairs(v) do
            assert.is_true(math.abs(p[1]) == 1 and math.abs(p[2]) == 2 and math.abs(p[3]) == 3)
        end
    end)

    it("covers every face: each axis plane holds 12 vertices", function()
        local v = studio.boxTriangles(0, 0, 0, 1, 1, 1)
        local faces = { 0, 0, 0, 0, 0, 0 }
        for i = 1, #v, 6 do
            -- the six vertices of a face share one coordinate
            for axis = 1, 3 do
                local same = true
                for j = i + 1, i + 5 do
                    same = same and v[j][axis] == v[i][axis]
                end
                if same then
                    faces[(axis - 1) * 2 + v[i][axis] + 1] = faces[(axis - 1) * 2 + v[i][axis] + 1] + 1
                end
            end
        end
        assert.same({ 1, 1, 1, 1, 1, 1 }, faces)
    end)

    it("stands the floor FEET under the ped origin", function()
        local lowest, highest = math.huge, -math.huge
        for _, p in ipairs(studio.box(0, 0, 100)) do
            lowest, highest = math.min(lowest, p[3]), math.max(highest, p[3])
        end
        assert.equals(100 - studio.FEET, lowest)
        assert.equals(100 - studio.FEET + studio.HEIGHT, highest)
    end)

    it("puts yaw 0 north of the ped and yaw 180 south, looking at it", function()
        local cx, cy, cz, tx, ty, tz = studio.cameraMatrix(10, 20, 5, 0, 3, 1, 0.5)
        assert.is_true(near(cx, 10) and near(cy, 23) and near(cz, 6))
        assert.same({ 10, 20, 5.5 }, { tx, ty, tz })
        cx, cy = studio.cameraMatrix(10, 20, 5, 180, 3, 0)
        assert.is_true(near(cx, 10) and near(cy, 17))
        cx, cy = studio.cameraMatrix(10, 20, 5, 90, 3, 0)
        assert.is_true(near(cx, 13) and near(cy, 20))
    end)

    it("resolves presets and defaults to threequarter", function()
        local cam = studio.parseCam({ "back" })
        assert.same({ yaw = 180, dist = 3.5, height = 0.3, lookZ = 0 }, cam)
        assert.equals(35, studio.parseCam({}).yaw)
    end)

    it("parses numbers, wraps yaw and keeps the camera inside the box", function()
        local cam = studio.parseCam({ "-90", "50", "99", "-9" })
        assert.equals(270, cam.yaw)
        assert.equals(studio.HALF - studio.MARGIN, cam.dist)
        assert.equals(studio.HEIGHT - studio.FEET - studio.MARGIN, cam.height)
        assert.equals(-studio.FEET + studio.MARGIN, cam.lookZ)
    end)

    it("rejects junk with the usage line", function()
        local cam, err = studio.parseCam({ "sideways" })
        assert.is_nil(cam)
        assert.truthy(err:find("presets: back, face, front", 1, true))
    end)

    it("hands out the lowest free dimension", function()
        assert.equals(60000, studio.freeDimension({}))
        assert.equals(60002, studio.freeDimension({ [60000] = true, [60001] = true, [60003] = true }))
    end)
end)
