// A stage-zero texture replacement: GTA retains its lighting, reflections and render states.
texture WheelTexture;
technique replace
{
    pass P0
    {
        Texture[0] = WheelTexture;
    }
}
