// Replace only stage zero so GTA still applies paint, lighting and reflections.
texture DirtTexture;

technique replace
{
    pass P0
    {
        Texture[0] = DirtTexture;
    }
}
