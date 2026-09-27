local geometry = {}

-- MTA rotation: rz in degrees, forward vector = (-sin(rz), cos(rz))
function geometry.dropPosition(x, y, rz, distance)
    local rad = math.rad(rz)
    return x - math.sin(rad) * distance, y + math.cos(rad) * distance
end

function geometry.box(x, y, r)
    return x - r, y - r, x + r, y + r
end

function geometry.polygonWKT(minx, miny, maxx, maxy)
    return string.format(
        "POLYGON((%g %g,%g %g,%g %g,%g %g,%g %g))",
        minx,
        miny,
        maxx,
        miny,
        maxx,
        maxy,
        minx,
        maxy,
        minx,
        miny
    )
end

return geometry
