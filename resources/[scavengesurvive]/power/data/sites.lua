-- Buildings wired for a generator: a mains box (prop_models 20307, its lever 20308) fixed where the building's own
-- supply would come in, and the lights a powered box switches on. The building's models stay as they are: the box
-- and lever are objects of their own and the light is the world resource's blackout shader lifting its cap inside
-- `room` (world:setRoomLight), plus a point light under each fitting for peds and vehicles.
--   box      x, y, z, rz of the box's origin (the centre of its back, on the wall), its front (+Y) into the room
--   floor    the floor's height under the box (a plugged cord lies there)
--   room    x1, y1, z1, x2, y2, z2: the volume the lights reach
--   fittings the light fittings' centres (a point light hangs just under each)
--   cordPath x, y on the floor a plugged cord runs through from the Generator's side to the inlet's foot, so it goes
--            round walls instead of through them (in order, the Generator end first)
--   watts    what the lights draw from the generator
return {
    {
        -- the car park under the three East LS project blocks (lae2_ground08): 30 x 61 m, two rows of four pillars,
        -- four twin-tube fittings down the middle (ws_fluorescent2). The box is on the east wall beside the ramp
        -- mouth, so the generator stands outside up the ramp and the cord runs down the ramp wall into the inlet.
        id = "eastls_projects",
        name = "East LS project car park",
        box = { 2352.02, -1267.6, 22.95, 90 },
        floor = 21.5,
        interior = 0,
        dimension = 0,
        -- the walls' inner faces (x 2322.38 .. 2352.03, y -1275.48 .. -1214.52) and a margin, so every wall is lit
        room = { 2322.1, -1275.8, 21.2, 2352.3, -1214.2, 24.9 },
        fittings = {
            { 2337.24, -1264.81, 24.4 },
            { 2337.24, -1251.09, 24.4 },
            { 2337.24, -1237.98, 24.4 },
            { 2337.24, -1225.9, 24.4 },
        },
        watts = 464, -- four twin 58 W fluorescent fittings
        -- from the ramp in at the north corner of its mouth, then along the east wall to the box
        cordPath = { { 2351.4, -1269.6 } },
    },
}
