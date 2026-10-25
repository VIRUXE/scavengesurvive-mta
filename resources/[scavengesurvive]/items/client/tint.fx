// Tints an item object's textures by its DefineItemType colour (0xAARRGGBB, upstream SetDynamicObjectMaterial /
// SetPlayerAttachedObject materialcolor1 & materialcolor2, #96). gTexture0 is bound by MTA to whichever texture
// each material of the object is currently drawing; Unlit skips vertex lighting for the full-bright gear previews.
texture gTexture0 < string textureState = "0,Texture"; >;
float4 Colour = float4(1, 1, 1, 1);
bool Unlit = false;

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

float4 ps(float4 diffuse : COLOR0, float2 uv : TEXCOORD0) : COLOR0
{
    float4 light = Unlit ? float4(1, 1, 1, 1) : diffuse;
    return tex2D(Sampler0, uv) * light * Colour;
}

technique tint
{
    pass P0
    {
        AlphaBlendEnable = true;
        PixelShader = compile ps_2_0 ps();
    }
}
