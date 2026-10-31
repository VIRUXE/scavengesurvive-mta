-- The two-handed carry pose (upstream SPECIAL_ACTION_CARRY, which the SA-MP client plays as the partial CARRY
-- crry_prtial on the upper body). setPedAnimation would run it as a full ped task and freeze WASD, so every client
-- sets these bone rotations itself each frame (client/attach.lua) while a useCarryAnim item is held.
-- bones[gtaBoneId] = { x, y, z } exactly as getElementBoneRotation returned them for a ped playing CARRY
-- crry_prtial (sampled on prod 2026-10-31). Only the arms: the spine and neck move by a few degrees, which would
-- fight the walking sway.
return {
    bones = {
        [21] = { -66.4, 107.8, 68.5 }, -- right clavicle
        [22] = { 53.4, -44.1, -63.2 }, -- right upper arm
        [23] = { 0.0, -69.6, 0.0 }, -- right forearm
        [24] = { -149.1, 3.6, -2.7 }, -- right hand
        [25] = { 0.0, 19.5, 0.0 }, -- right fingers
        [26] = { 0.0, 13.3, 0.0 }, -- right thumb
        [31] = { 61.4, 112.8, -70.3 }, -- left clavicle
        [32] = { -42.7, -41.0, 60.4 }, -- left upper arm
        [33] = { 0.0, -76.8, 0.0 }, -- left forearm
        [34] = { 164.0, 8.0, 4.2 }, -- left hand
        [35] = { 0.0, 19.5, 0.0 }, -- left fingers
        [36] = { 0.0, 13.3, 0.0 }, -- left thumb
    },
}
