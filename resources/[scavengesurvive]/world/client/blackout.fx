// Blackout for buildings: GTA bakes lit windows and lamp pools into each building's night vertex colours (the
// day/night prelight blend). Capping the brightness of that colour at night leaves every window as dark as the wall
// around it. Cap is 1 by day (no change) and falls to NightCap as the game's own day/night balance rises
// (client/blackout.lua). The hue is kept, only the brightness is limited.
//
// Lights a player brings (a Flood Light, items/client/floodlight.lua) add on top of that: up to four spot lights,
// each LightNPos (xyz, w = radius), LightNDir (xyz, the aim) and LightNCol (rgb), fading with distance and across
// the cone (Cone: the cosines where it is full and where it is gone), with a glow round the lamp itself that lights
// the room behind it too. GTA's vertex processing is left as it is: the world position comes from texture stage 1's
// generated camera-space position turned back by the inverse view matrix, so the pixel shader gets it as TEXCOORD1.
// There are no shadows: the light passes through walls, which the short radius keeps to the next room. A card that
// cannot run ps_2_a gets the plain blackout and no lights.
//
// A building lit by its own mains (the power resource, a Generator wired to its box) is up to two rooms,
// RoomNMin / RoomNMax (xyz; Min.w = the light added over the night colours, Max.w = 1 while lit) and RoomNCol:
// inside one the cap is lifted, so the building's baked night colours (its lamps' pools) show as GTA lit them, and
// the room's light is added on top. Past the room's box the light dies off over ROOM_FADE metres, so it spills out of
// a doorway or a ramp and fades instead of stopping at a hard edge.
texture gTexture0 < string textureState = "0,Texture"; >;
float4x4 gViewInverse : VIEWINVERSE;
float Cap = 1;
float Gain = 1;
float2 Cone = float2(0.6, 0.2);
float4 Light0Pos = float4(0, 0, 0, 0);
float4 Light0Dir = float4(0, 0, -1, 0);
float4 Light0Col = float4(0, 0, 0, 0);
float4 Light1Pos = float4(0, 0, 0, 0);
float4 Light1Dir = float4(0, 0, -1, 0);
float4 Light1Col = float4(0, 0, 0, 0);
float4 Light2Pos = float4(0, 0, 0, 0);
float4 Light2Dir = float4(0, 0, -1, 0);
float4 Light2Col = float4(0, 0, 0, 0);
float4 Light3Pos = float4(0, 0, 0, 0);
float4 Light3Dir = float4(0, 0, -1, 0);
float4 Light3Col = float4(0, 0, 0, 0);
float4 Room0Min = float4(0, 0, -10000, 0);
float4 Room0Max = float4(0, 0, -10000, 0);
float4 Room0Col = float4(0, 0, 0, 0);
float4 Room1Min = float4(0, 0, -10000, 0);
float4 Room1Max = float4(0, 0, -10000, 0);
float4 Room1Col = float4(0, 0, 0, 0);

static const float GLOW = 4.0; // metres round the lamp lit whichever way they lie
static const float GLOW_SHARE = 0.35;
static const float MAX_LIGHT = 1.6;
static const float ROOM_FADE = 4.0;

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

float3 cappedAt(float4 diffuse, float cap)
{
    float peak = max(max(diffuse.r, diffuse.g), max(diffuse.b, 0.0001));
    return diffuse.rgb * min(1, cap / peak);
}

float3 capped(float4 diffuse)
{
    return cappedAt(diffuse, Cap);
}

// 1 inside the room while it is lit, falling to 0 at ROOM_FADE metres outside its box, else 0
float inside(float4 mn, float4 mx, float3 wp)
{
    float3 past = max(max(mn.xyz - wp, wp - mx.xyz), 0);
    return saturate(1 - length(past) / ROOM_FADE) * mx.w;
}

float3 spot(float4 pos, float4 dir, float4 col, float3 wp)
{
    float3 d = pos.xyz - wp;
    float dist = max(length(d), 0.001);
    float fall = saturate(1 - dist / max(pos.w, 0.001));
    float cone = saturate((dot(-d / dist, dir.xyz) - Cone.y) / (Cone.x - Cone.y));
    float glow = saturate(1 - dist / GLOW);
    return col.rgb * (fall * fall * cone + GLOW_SHARE * glow * glow);
}

float4 psLit(float4 diffuse : COLOR0, float2 uv : TEXCOORD0, float3 wp : TEXCOORD1) : COLOR0
{
    float3 added = spot(Light0Pos, Light0Dir, Light0Col, wp) + spot(Light1Pos, Light1Dir, Light1Col, wp)
        + spot(Light2Pos, Light2Dir, Light2Col, wp) + spot(Light3Pos, Light3Dir, Light3Col, wp);
    float in0 = inside(Room0Min, Room0Max, wp);
    float in1 = inside(Room1Min, Room1Max, wp);
    float room = saturate(in0 + in1);
    added += Room0Col.rgb * Room0Min.w * in0 + Room1Col.rgb * Room1Min.w * in1;
    float3 light = min(cappedAt(diffuse, lerp(Cap, 1, room)) + added * Gain, MAX_LIGHT);
    return tex2D(Sampler0, uv) * float4(light, diffuse.a);
}

float4 ps(float4 diffuse : COLOR0, float2 uv : TEXCOORD0) : COLOR0
{
    return tex2D(Sampler0, uv) * float4(capped(diffuse), diffuse.a);
}

technique lit
{
    pass P0
    {
        // D3DTSS_TCI_CAMERASPACEPOSITION (0x20000) on stage 1, three coordinates (D3DTTFF_COUNT3), times the
        // inverse view: the world position
        TexCoordIndex[1] = 131073;
        TextureTransformFlags[1] = 3;
        TextureTransform[1] = (gViewInverse);
        PixelShader = compile ps_2_a psLit();
    }
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
