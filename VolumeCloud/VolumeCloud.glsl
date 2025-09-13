#iChannel0 "file://VolumeCloud.png"

// 左手系
#define PI 3.1415926



const int maxMarchCount = 64;
const float marchStep = 0.15;

const float beerAttenuation = 0.8;

const float scatterProbability = 0.1;
const float scatterIntensity = 12.0;

const bool usePointLight = false;
// const bool usePointLight = true;


vec4 texture3D(sampler2D sampler , vec3 texcoord , int col , int row)
{
    vec3 size = vec3(1.0) / vec3(col , row , col * row - 1);

    float z = texcoord.z / size.z;
    int index1 = int(floor(z));
    int index2 = int(ceil(z));

    vec2 uvStart1 = vec2(index1 % col , row - 1 - index1 / row);
    vec2 uvStart2 = vec2(index2 % col , row - 1 - index2 / row);

    vec2 uv1 = (uvStart1 + texcoord.xy) * size.xy;
    vec2 uv2 = (uvStart2 + texcoord.xy) * size.xy;

    vec4 sample1 = texture2D(sampler , uv1);
    vec4 sample2 = texture2D(sampler , uv2);

    vec4 result = sample1 * (float(index2) - z) + sample2 * (z - float(index1));

    return result;
}



struct Camera
{
    vec3 position;

    vec3 right;
    vec3 up;
    vec3 forward;

    float fov;
    float near;
    float far;
};

struct Ray
{
    vec3 origin;
    vec3 dir;
};

struct Bounds
{
    vec3 min;
    vec3 max;
};

struct PointLight
{
    vec3 position;
    vec3 color;
    float intensity;
};

struct DirLight
{
    vec3 dir;
    vec3 color;
    float intensity;
};



Camera cam = Camera(vec3(0 , 0 , -5) ,
                    vec3(1 , 0 , 0) , vec3(0 , 1 , 0) , vec3(0 , 0 , 1) ,
                    60.0 , 0.03 , 1000.0);

Bounds bounds = Bounds(vec3(-1 , -1 , -1) , vec3(1 , 1 , 1));

PointLight pointLight = PointLight(vec3(1 , 1 , -2) , vec3(1 , 1 , 1) , 1.0);

DirLight dirLight = DirLight(vec3(-1 , -1 , 1) , vec3(1 , 1 , 1) , 1.0);



mat4 GetViewToWorldMatrix()
{
    return mat4(vec4(cam.right , 0.0) ,
                vec4(cam.up , 0.0) ,
                vec4(cam.forward , 0.0) ,
                vec4(cam.position , 0.0));
}



Ray GetRay(vec2 uv , out float width , out float height)
{
    Ray ray;

    ray.origin = cam.position;

    float aspect = iResolution.x / iResolution.y;
    height = tan(radians(cam.fov) * 0.5) * cam.near * 2.0;
    width = height * aspect;
    vec3 viewPointVS = vec3(uv - 0.5 , 1.0) * vec3(width , height , cam.near);

    vec3 viewPointWS = (GetViewToWorldMatrix() * vec4(viewPointVS , 1.0)).xyz;

    ray.dir = normalize(viewPointWS - ray.origin);

    return ray;
}

bool RayBounds(vec3 ro , vec3 invRd , Bounds bounds , out float tEnter , out float tExit)
{
    vec3 t1 = (bounds.min - ro) * invRd;
    vec3 t2 = (bounds.max - ro) * invRd;

    vec3 tMin = min(t1 , t2);
    vec3 tMax = max(t1 , t2);

    tEnter = max(tMin.x , max(tMin.y , tMin.z));
    tExit = min(tMax.x , min(tMax.y , tMax.z));

    return tEnter < tExit && tExit > 0.0;
}



float Beer(float density)
{
    return exp(-density * beerAttenuation);
}

float BeerPower(float density)
{
    return 2.0 * exp(-density) * (1.0 - exp(-2.0 * density));
}

float HenyeyGreenstein(vec3 lightDir , vec3 viewDir , float g)
{
    float LoV = dot(lightDir , viewDir);
    return 1.0 / (4.0 * PI) * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * LoV , 1.5);
}



float GetCloudLuminance(vec3 pos , vec3 lightDir , Bounds bounds)
{
    float tEnter , tExit;
    bool isRayBounds = RayBounds(pos , vec3(1) / lightDir ,
                                 bounds , tEnter , tExit);
    
    if (!isRayBounds)
        return 0.0;

    float marchLength = 0.0;
    float totalDensity = 0.0;

    for(int march = 0; march < maxMarchCount; )
    {
        marchLength += marchStep;

        if (marchLength >= tExit)
            break;

        if (marchLength <= tEnter)
            continue;

        vec3 pos = pos + lightDir * marchLength;
        vec3 texcoord = (pos - bounds.min) / (bounds.max - bounds.min);

        float density = texture3D(iChannel0 , texcoord , 8 , 8).r;
        totalDensity += density * marchStep;

        ++march;
    }

    return BeerPower(totalDensity);
}



void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;


    float width , height;
    Ray ray = GetRay(uv , width , height);


    vec2 mouseUV = iMouse.xy / iResolution.xy;
    vec3 mousePos = vec3(mouseUV - 0.5 , 1.0) * vec3(width , height , cam.near);
    if (usePointLight)
    {
        pointLight.position = mousePos * 500.0;
    }
    else
    {
        vec3 point = vec3(0 , 5 , -2);
        mousePos.z *= -1.0;
        dirLight.dir = normalize(mousePos * 500.0 - point);
    }


    float tEnter , tExit;
    bool isRayBounds = RayBounds(ray.origin , vec3(1) / ray.dir ,
                                 bounds , tEnter , tExit);
    
    if (!isRayBounds)
    {
        fragColor = vec4(0 , 0 , 0 , 1);
        return;
    }


    float marchLength = 0.0;
    float totalDensity = 0.0;
    float totalLum = 0.0;

    for(int march = 0; march < maxMarchCount; )
    {
        marchLength += marchStep;

        if (marchLength >= tExit)
            break;

        if (marchLength <= tEnter)
            continue;

        vec3 pos = ray.origin + ray.dir * marchLength;
        vec3 texcoord = (pos - bounds.min) / (bounds.max - bounds.min);

        float density = texture3D(iChannel0 , texcoord , 8 , 8).r;
        
        if (density > 0.0)
        {
            vec3 lightDir;
            if (usePointLight)
                lightDir = normalize(pointLight.position - pos);
            else
                lightDir = normalize(-dirLight.dir);

            float phase = HenyeyGreenstein(-lightDir , -ray.dir , scatterProbability) * scatterIntensity;

            float lum = GetCloudLuminance(pos , lightDir , bounds);
            lum *= density * marchStep;
            totalLum += Beer(totalDensity) * lum * phase;

            totalDensity += density * marchStep;
        }

        ++march;
    }

    vec3 color = (usePointLight ? pointLight.color * pointLight.intensity : dirLight.color * dirLight.intensity) * totalLum;


    fragColor = vec4(color , 1);
}