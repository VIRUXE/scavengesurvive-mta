local Tracer = dofile("resources/[scavengesurvive]/weapons/shared/logic/tracer.lua")

describe("weapons tracer logic", function()
    it("identifies tracer ammo types from upstream tracer.pwn", function()
        assert.is_true(Tracer.isTracerAmmo("Ammo556Tracer"))
        assert.is_true(Tracer.isTracerAmmo("Ammo357Tracer"))
        assert.is_false(Tracer.isTracerAmmo("Ammo556"))
        assert.is_false(Tracer.isTracerAmmo("Ammo9mm"))
        assert.is_false(Tracer.isTracerAmmo(nil))
    end)

    it("skips shots shorter than the 2m muzzle offset", function()
        assert.is_nil(Tracer.spawn(0, 0, 0, 1.5, 0, 0, 1000))
    end)

    it("computes start offset, 800m/s duration, and moving 3D segment", function()
        local tr = Tracer.spawn(0, 0, 0, 82, 0, 0, 1000)
        assert.is_not_nil(tr)
        assert.equals(2, tr.sx)
        assert.equals(80, tr.travel)
        assert.equals(100, tr.durationMs) -- 80m at 800m/s = 100ms

        local x1, y1, z1, x2, y2, z2 = Tracer.segment(tr, 1050)
        assert.equals(42 - Tracer.LENGTH, x1)
        assert.equals(0, y1)
        assert.equals(0, z1)
        assert.equals(42, x2)
        assert.equals(0, y2)
        assert.equals(0, z2)

        assert.is_nil(Tracer.segment(tr, 1100))
    end)
end)
