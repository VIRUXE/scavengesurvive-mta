local load = require("tests.lua.helpers.load_module")
local function near(a, b)
    return math.abs(a - b) < 1e-9
end
local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
describe("lib.surface", function()
    local surface = load("surface")
    it("lies flat on level ground facing its yaw", function()
        local m = surface.matrix(1, 2, 3, 0, 0, 1, 90, 0.02)
        assert.is_true(near(m[2][1], -1) and near(m[2][2], 0) and near(m[2][3], 0))
        assert.is_true(near(m[3][3], 1))
        assert.is_true(near(m[4][1], 1) and near(m[4][2], 2) and near(m[4][3], 3.02))
    end)
    it("follows a slope with an orthonormal right-handed basis", function()
        local n = 1 / math.sqrt(2)
        local m = surface.matrix(0, 0, 0, n, 0, n, 30, 0.1)
        assert.is_true(near(m[3][1], n) and near(m[3][3], n))
        for i = 1, 3 do
            assert.is_true(near(dot(m[i], m[i]), 1))
        end
        assert.is_true(near(dot(m[1], m[2]), 0) and near(dot(m[2], m[3]), 0) and near(dot(m[1], m[3]), 0))
        -- right x forward = up
        local r, f = m[1], m[2]
        assert.is_true(near(r[2] * f[3] - r[3] * f[2], m[3][1]) and near(r[1] * f[2] - r[2] * f[1], m[3][3]))
        assert.is_true(near(m[4][1], 0.1 * n) and near(m[4][3], 0.1 * n))
    end)
    it("survives a wall facing its yaw and a zero normal", function()
        local m = surface.matrix(0, 0, 0, 0, -1, 0, 0)
        assert.is_true(near(dot(m[2], m[2]), 1) and near(dot(m[2], m[3]), 0))
        m = surface.matrix(0, 0, 0, 0, 0, 0, 0)
        assert.is_true(near(m[3][3], 1))
    end)
end)
