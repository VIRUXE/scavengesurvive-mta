// Procedural blue gas jet; UV.y=0 at the tip. Drawn as a world-space billboard.
float time = 0;
float4 flame(float2 uv : TEXCOORD0, float4 color : COLOR0) : COLOR0
{
    float h = 1 - uv.y;
    float sway = sin(time * 9 + h * 8) * 0.07 * h;
    float x = abs((uv.x - 0.5 - sway) * 2);
    float width = 0.82 * (1 - h * h);
    float body = saturate((width - x) * 12) * saturate(h * 18) * saturate((1-h)*14);
    float core = saturate((width * 0.44 - x) * 15) * (1 - h);
    float3 rgb = lerp(float3(0.02, 0.18, 1), float3(0.2, 0.85, 1), core);
    return float4(rgb, body * color.a * 0.85);
}
technique GasFlame
{
    pass P0
    {
        PixelShader = compile ps_2_0 flame();
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = ONE;
        ZEnable = true;
        ZWriteEnable = false;
        CullMode = NONE;
    }
}
