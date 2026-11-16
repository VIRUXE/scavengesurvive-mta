// Hunger and thirst on the screen (client/hunger.lua, shared/logic/hunger.lua): the screen source drained of colour
// (Desat), darkened towards the edges (Vignette) and blurred towards the edges (Blur), each 0..1.
texture ScreenTexture;
float Desat = 0;
float Vignette = 0;
float Blur = 0;
float2 Aspect = float2(1, 1);

sampler ScreenSampler = sampler_state
{
    Texture = (ScreenTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
};

float4 ps(float2 uv : TEXCOORD0) : COLOR0
{
    float2 d = (uv - 0.5) * Aspect;
    float r = length(d) * 1.6; // ~0 at the centre, ~1 in the corners
    float edge = saturate(r * r);
    float spread = Blur * edge * 0.006;
    float3 c = tex2D(ScreenSampler, uv).rgb * 0.36;
    c += tex2D(ScreenSampler, uv + float2(spread, 0)).rgb * 0.16;
    c += tex2D(ScreenSampler, uv - float2(spread, 0)).rgb * 0.16;
    c += tex2D(ScreenSampler, uv + float2(0, spread)).rgb * 0.16;
    c += tex2D(ScreenSampler, uv - float2(0, spread)).rgb * 0.16;
    float grey = dot(c, float3(0.299, 0.587, 0.114));
    c = lerp(c, float3(grey, grey, grey), Desat);
    c *= 1 - Vignette * saturate(r * r * 1.1);
    return float4(c, 1);
}

technique hunger
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
