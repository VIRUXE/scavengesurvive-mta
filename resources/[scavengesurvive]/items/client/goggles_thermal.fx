// The picture Thermal Vision goggles show (client/goggles.lua), drawn over GTA's own vision effect from the screen
// source. GTA has lit the living red and everything else blue. Red against blue is read as heat and painted with an
// ironbow palette (cold black and violet, warm orange, hot yellow to white) on a coarse sensor (Sensor: its columns
// and rows) inside a square eyepiece.
// Power (0..1) is the picture's strength: it rises as the goggles warm up and dips when the battery is low.
texture ScreenTexture;
float Power = 1;
float2 Sensor = float2(427, 240);

sampler ScreenSampler = sampler_state
{
    Texture = (ScreenTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
};

float4 psThermal(float2 uv : TEXCOORD0) : COLOR0
{
    float2 q = (floor(uv * Sensor) + 0.5) / Sensor;
    float3 c = tex2D(ScreenSampler, q).rgb;
    float hot = saturate((c.r - c.b) * 1.6 + c.r * 0.25);
    float cold = saturate(dot(c, float3(0.1, 0.3, 0.6)));
    float t = lerp(0.42 * cold, 0.55 + 0.45 * hot, step(0.06, hot)) * Power;
    float3 o;
    o.r = saturate(1.9 * t - 0.2);
    o.g = saturate(2.4 * t - 1.2);
    o.b = saturate(1 - abs(t - 0.3) * 3.2) * 0.55 + saturate(4 * t - 3.1);
    // a square eyepiece
    float2 d = abs(uv - 0.5);
    o *= 1 - smoothstep(0.455, 0.49, max(d.x, d.y));
    return float4(o, 1);
}

technique thermal
{
    pass P0
    {
        PixelShader = compile ps_2_0 psThermal();
    }
}

technique fallback
{
    pass P0
    {
    }
}
