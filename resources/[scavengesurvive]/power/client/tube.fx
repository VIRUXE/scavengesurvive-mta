// The light fittings' tubes (ws_fluorescent2) glow inside a lit mains site's room (client/main.lua sets up to two
// rooms) and keep the world's own shading everywhere else. The world position comes the way world/client/
// blackout.fx gets it: texture stage 1's generated camera-space position turned back by the inverse view matrix.
// Drawn above blackout.fx (priority 1 against its -10), so a glowing tube is not capped dark.
texture gTexture0 < string textureState = "0,Texture"; >;
float4x4 gViewInverse : VIEWINVERSE;
float4 Room0Min = float4(0, 0, -10000, 0);
float4 Room0Max = float4(0, 0, -10000, 0);
float4 Room1Min = float4(0, 0, -10000, 0);
float4 Room1Max = float4(0, 0, -10000, 0);

static const float3 GLOW = float3(1.15, 1.2, 1.3);

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

float inside(float4 mn, float4 mx, float3 wp)
{
    float3 a = step(mn.xyz, wp) * step(wp, mx.xyz);
    return a.x * a.y * a.z * mn.w;
}

float4 ps(float4 diffuse : COLOR0, float2 uv : TEXCOORD0, float3 wp : TEXCOORD1) : COLOR0
{
    float lit = saturate(inside(Room0Min, Room0Max, wp) + inside(Room1Min, Room1Max, wp));
    float4 t = tex2D(Sampler0, uv);
    float3 shade = lerp(diffuse.rgb, GLOW, lit);
    return float4(t.rgb * shade, t.a * diffuse.a);
}

technique glow
{
    pass P0
    {
        TexCoordIndex[1] = 131073;
        TextureTransformFlags[1] = 3;
        TextureTransform[1] = (gViewInverse);
        PixelShader = compile ps_2_a ps();
    }
}

technique fallback
{
    pass P0
    {
    }
}
