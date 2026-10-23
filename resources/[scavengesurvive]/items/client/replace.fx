// Draws an object with another texture (the pitched tent's camo net, camo fabric and lamppost paint,
// upstream SetDynamicObjectMaterial). Tex comes from engineGetModelTextures on the stock model that owns it.
texture Tex;
technique replace
{
    pass P0
    {
        Texture[0] = Tex;
        CullMode = None; // both faces: the roof sheets are one-sided meshes seen from outside and inside
    }
}
