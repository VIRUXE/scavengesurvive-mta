// The picture Night Vision goggles show (client/goggles.lua), drawn over GTA's own vision effect from the screen
// source. GTA has lit the scene green and multiplied the frame by green, so what is left is one channel of
// brightness. It is amplified (dark detail lifted, anything already bright burnt out towards white, the way a tube
// blooms), tinted phosphor green, crossed by faint scan lines and seen through two round tubes.
// Power (0..1) is the picture's strength: it rises as the goggles warm up and dips when the battery is low.
texture ScreenTexture;
float Power = 1;
float Time = 0;
float2 Aspect = float2(1.778, 1);

sampler ScreenSampler = sampler_state
{
    Texture = (ScreenTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
};

float4 psNight(float2 uv : TEXCOORD0) : COLOR0
{
    float3 c = tex2D(ScreenSampler, uv).rgb;
    float lum = dot(c, float3(0.2, 0.7, 0.1));
    float v = pow(lum, 0.7) * 1.9 * Power;
    float3 o = float3(0.2, 1.0, 0.3) * v + saturate(v - 0.9) * 0.8;
    o *= 0.93 + 0.07 * sin(uv.y * 900 + Time * 6);
    // two tubes side by side, their edges soft
    float2 d = (uv - 0.5) * Aspect;
    float dist = min(length(d + float2(0.3, 0)), length(d - float2(0.3, 0)));
    o *= 1 - smoothstep(0.5, 0.56, dist);
    return float4(o, 1);
}

technique night
{
    pass P0
    {
        PixelShader = compile ps_2_0 psNight();
    }
}

technique fallback
{
    pass P0
    {
    }
}
