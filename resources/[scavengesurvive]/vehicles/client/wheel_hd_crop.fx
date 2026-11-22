// Only the wheel's region of a large atlas is downloaded. Outside it, sample the
// original texture so dashboard/body UVs sharing this material remain untouched.
// Keep GTA's fixed-function vertex processing (including vehicle lighting).
texture OriginalTexture < string textureState = "0,Texture"; >;
texture WheelTexture;
float4 Region; // minimum UV xy, maximum UV zw
float4 Transform; // UV scale xy, offset zw; padding is extended edge texels

sampler OriginalSampler = sampler_state { Texture = (OriginalTexture); };
sampler WheelSampler = sampler_state
{
    Texture = (WheelTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

float4 replaceRegion(float2 uv : TEXCOORD0, float4 diffuse : COLOR0, float4 specular : COLOR1) : COLOR0
{
    float2 wrapped = frac(uv);
    float inside = step(Region.x, wrapped.x) * step(Region.y, wrapped.y)
                 * step(wrapped.x, Region.z) * step(wrapped.y, Region.w);
    float4 original = tex2D(OriginalSampler, uv);
    float4 wheel = tex2D(WheelSampler, wrapped * Transform.xy + Transform.zw);
    float4 pixel = lerp(original, wheel, inside) * diffuse;
    pixel.rgb += specular.rgb;
    return pixel;
}

technique cropped
{
    pass P0
    {
        PixelShader = compile ps_2_0 replaceRegion();
    }
}

// Hardware without ps_2_0 keeps vanilla rather than displaying the cropped atlas incorrectly.
technique vanilla
{
    pass P0 { }
}
