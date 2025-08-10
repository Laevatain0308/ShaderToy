#iChannel0 "file://ZUTOMAYO.JPG"
#iChannel1 "file://Caustics_tex_color.png"

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;

    float radius = 60.0;
    vec2 mousePos = iMouse.xy;
    float distToMouse = distance(mousePos , fragCoord);

    float factor = 0.06;
    float focus = 8.0;

    vec2 pixelUVSize = vec2(1.0 / iResolution.x , 1.0 / iResolution.y);
    float[] blurOffset = float[] ( 1.0 , 0.0 , -1.0 );

    vec4 outColor;
    if (distToMouse < radius)
    {
        vec2 dir = normalize(fragCoord - mousePos);
        float percent = distToMouse / radius;
        vec2 offset = -dir * factor * pow(percent , focus);

        for (int x = 0 ; x < 3 ; ++x)
        {
            for (int y = 0 ; y < 3 ; ++y)
            {
                vec2 blur = pixelUVSize * vec2(blurOffset[x] , blurOffset[y]);
                outColor += texture2D(iChannel0 , uv + offset + blur);
            }
        }

        outColor /= 9.0;
    }
    else
    {
        outColor = texture2D(iChannel0 , uv);
    }

    fragColor = outColor;
}