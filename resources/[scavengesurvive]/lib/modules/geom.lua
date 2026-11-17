-- Server-side world collision through ml_sageom (docs/runbooks/server-collision.md): the vanilla map plus the port's
-- overlay that the world resource loads. Every query answers nil while the module is missing, its world is still
-- loading, the overlay has not been applied or is stale (map files changed since the server started), so callers
-- keep a fallback for those cases. Main world only (interior 0, dimension 0): callers check that themselves.
local geom = {}

-- true once the module, its world and the current overlay are all loaded
function geom.ready()
    return type(sageomGround) == "function"
        and sageomIsReady()
        and getElementData(root, "geom.overlay") ~= false
        and getElementData(root, "geom.overlay") ~= nil
        and getElementData(root, "geom.stale") ~= true
end

-- The first surface straight below (x, y, z), searched from `above` metres over it to `depth` metres under it:
-- hz, nx, ny, nz, model or nil when nothing is there.
function geom.below(x, y, z, above, depth)
    if not geom.ready() then
        return nil
    end
    above = above or 0.5
    local hz, nx, ny, nz, _, model = sageomGround(x, y, z + above, 0, above + (depth or 3))
    if not hz then
        return nil
    end
    return hz, nx, ny, nz, model
end

-- The first surface on the segment from (x1, y1, z1) to (x2, y2, z2): hx, hy, hz, nx, ny, nz, model or nil.
function geom.ray(x1, y1, z1, x2, y2, z2)
    if not geom.ready() then
        return nil
    end
    local hit, hx, hy, hz, nx, ny, nz, _, model = sageomRaycast(x1, y1, z1, x2, y2, z2, 0)
    if not hit then
        return nil
    end
    return hx, hy, hz, nx, ny, nz, model
end

-- true when nothing solid is on the segment, false when something is, nil when the world cannot tell
function geom.clear(x1, y1, z1, x2, y2, z2)
    if not geom.ready() then
        return nil
    end
    return not sageomRaycast(x1, y1, z1, x2, y2, z2, 0)
end

-- The water surface's z at (x, y), or nil where there is no water (or the world cannot tell: see geom.ready)
function geom.water(x, y)
    if not geom.ready() then
        return nil
    end
    return sageomWaterLevel(x, y) or nil
end

return geom
