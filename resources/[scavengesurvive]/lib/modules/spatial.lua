-- SQL broad phase for world_items_pos queries (alias p). Retain the exact ST_Distance predicate too.
local spatial = {}

function spatial.bounds(x, y, radius)
    -- Expand slightly so strict MBR boundary semantics and decimal conversion cannot drop circle-edge points.
    local r = radius + 0.000001
    return string.format(
        "MBRContains(ST_GeomFromText('POLYGON((%.17g %.17g,%.17g %.17g,%.17g %.17g,%.17g %.17g,%.17g %.17g))'), p.pos)",
        x - r,
        y - r,
        x + r,
        y - r,
        x + r,
        y + r,
        x - r,
        y + r,
        x - r,
        y - r
    )
end

return spatial
