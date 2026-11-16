// Blackout for buildings: GTA bakes lit windows and lamp pools into each building's night vertex colours (the
// day/night prelight blend). Capping the brightness of that colour at night leaves every window as dark as the wall
// around it. Cap is 1 by day (no change) and falls to NightCap as the game's own day/night balance rises
// (client/blackout.lua). The hue is kept, only the brightness is limited.
texture gTexture0 < string textureState = "0,Texture"; >;
float Cap = 1;

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

float4 ps(float4 diffuse : COLOR0, float2 uv : TEXCOORD0) : COLOR0
{
    float peak = max(max(diffuse.r, diffuse.g), max(diffuse.b, 0.0001));
    float3 light = diffuse.rgb * min(1, Cap / peak);
    return tex2D(Sampler0, uv) * float4(light, diffuse.a);
}

technique blackout
{
    pass P0
    {
        PixelShader = compile ps_2_0 ps();
    }
}

technique fallback
{
    pass P0
    {
    }
}
