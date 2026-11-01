-- Pure water test of upstream hack-detect.pwn `_hd_IsPlayerInWater`: is a position somewhere a swimming animation
-- is legitimate. Used against the client's claim of being in water (swim-fly check). No MTA calls at file scope.
local water = {}

local DAM_CENTRE = { -965.0, 2438.0, 42.0 }
local DAM_RADIUS = 700.0

-- minX, minY, maxX, maxY, top Z of each pool, lake and dam outside the sea
water.PLACES = {
    { -2048.0, -962.0, -2004.0, -758.0, 30.4 },
    { -2522.0, -310.0, -2382.0, -234.0, 35.382 },
    { -2778.0, -522.0, -2662.0, -414.0, 2.79256 },
    { -664.0, -1924.0, -464.0, -1864.0, 5.27 },
    { -848.0, -2082.0, -664.0, -1866.0, 5.27 },
    { 1084.0, -684.0, 1104.0, -660.0, 112.0 },
    { 1202.0, -2414.0, 1278.0, -2334.0, 8.86445 },
    { 1270.0, -812.0, 1290.0, -800.0, 86.673 },
    { 1744.0, 2780.0, 1792.0, 2868.0, 8.47297 },
    { 178.0, -1244.0, 206.0, -1216.0, 77.0534 },
    { 1836.0, 1468.0, 1888.0, 1568.0, 8.59839 },
    { 1888.0, 1468.0, 2036.0, 1700.0, 8.59839 },
    { 1928.0, -1222.0, 2012.0, -1178.0, 18.0 },
    { 2058.0, 1868.0, 2110.0, 1964.0, 9.62916 },
    { 2090.0, 1670.0, 2146.0, 1694.0, 9.61171 },
    { 2108.0, 1084.0, 2180.0, 1172.0, 7.56284 },
    { 2110.0, 1234.0, 2178.0, 1330.0, 7.83275 },
    { 214.0, -1208.0, 246.0, -1180.0, 74.0 },
    { 218.0, -1180.0, 238.0, -1172.0, 74.0 },
    { 2248.0, -1182.0, 2260.0, -1170.0, 23.3374 },
    { 2292.0, -1432.0, 2328.0, -1400.0, 22.165 },
    { 2506.0, 1546.0, 2554.0, 1586.0, 8.96708 },
    { 2564.0, 2370.0, 2604.0, 2398.0, 16.4 },
    { 502.0, -1114.0, 522.0, -1098.0, 78.4231 },
    { 890.0, -1106.0, 902.0, -1098.0, 22.41 },
}

-- Dry spots below sea level: train tunnels and the SF dry dock, as upstream's dynamic polygons (points, min Z, max Z)
water.DRY_POLYGONS = {
    {
        points = {
            { 1357.18958, -1905.22717 },
            { 1314.53406, -1947.33569 },
            { 665.2309, -1285.64282 },
            { 719.66364, -1223.15979 },
        },
        min_z = -6.0,
        max_z = 0.0,
    },
    {
        points = {
            { 2764.71533, 2126.56323 },
            { 2716.97314, 2081.59985 },
            { 2569.71045, 2213.24756 },
            { 2606.24243, 2252.94141 },
        },
        min_z = -6.0,
        max_z = 0.0,
    },
    {
        points = {
            { -1608.19177, 166.27438 },
            { -1578.24011, 135.71609 },
            { -1675.87097, 38.37003 },
            { -1707.14429, 66.96732 },
        },
        min_z = -14.0,
        max_z = 0.0,
    },
}

local function distance(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function water.inMapBounds(x, y, z)
    return x >= -3000.0 and x <= 3000.0 and y >= -3000.0 and y <= 3000.0 and z >= -100.0 and z <= 1000.0
end

-- insidePolygon is fields.insidePolygon (anticheat/shared/logic/fields.lua), passed in so this file stays standalone
function water.isWater(x, y, z, insidePolygon)
    if z < 44.0 and distance(x, y, z, DAM_CENTRE[1], DAM_CENTRE[2], DAM_CENTRE[3]) <= DAM_RADIUS then
        return true -- Sherman dam reservoir
    end
    if z < 1.9 then -- sea level plus the wave height
        if not water.inMapBounds(x, y, z) then
            return true
        end
        if distance(x, y, z, 618.4129, 863.3164, 1.0839) < 200.0 then
            return false -- Hunter quarry
        end
        if distance(x, y, z, -1597.1052, 703.2137, -5.9072) < 80.0 then
            return false -- SFPD
        end
        if x > 2215.38916 and x < 2320.28271 and y > 2422.94531 and y < 2504.66431 then
            return false -- LV PD
        end
        for _, poly in ipairs(water.DRY_POLYGONS) do
            if z >= poly.min_z and z <= poly.max_z and insidePolygon(x, y, poly.points) then
                return false
            end
        end
        return true
    end
    for _, p in ipairs(water.PLACES) do
        if z <= p[5] and x >= p[1] and x <= p[3] and y >= p[2] and y <= p[4] then
            return true
        end
    end
    return false
end

return water
