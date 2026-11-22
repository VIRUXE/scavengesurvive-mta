// A puff of the toxic cloud (client/main.lua): the puff texture times the colour the line is drawn with, and no
// distance fog. The game's fog is still switched on when the 3D lines are drawn, and a puff far away, drawn close
// to the far clip plane, came out in the fog's colour instead of the gas's.
texture Puff;

technique cloud
{
    pass P0
    {
        Texture[0] = Puff;
        FogEnable = false;
        AddressU[0] = Clamp;
        AddressV[0] = Clamp;
        ColorOp[0] = Modulate;
        ColorArg1[0] = Texture;
        ColorArg2[0] = Diffuse;
        AlphaOp[0] = Modulate;
        AlphaArg1[0] = Texture;
        AlphaArg2[0] = Diffuse;
    }
}
