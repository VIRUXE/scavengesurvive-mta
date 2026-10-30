// Draws an object with a render target (the ranch PC's screen text, upstream SetDynamicObjectMaterialText).
texture Tex;
technique screen
{
    pass P0
    {
        Texture[0] = Tex;
        AlphaBlendEnable = true;
    }
}
