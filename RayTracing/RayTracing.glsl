//========== Struct ==========//
struct Transform
{
    vec3 position;
};

struct Camera
{
    float nearClippingPlane;
    float fov;

    Transform transform;

    vec3 cameraForward;
    vec3 cameraUp;
    vec3 cameraRight;
};

struct Ray
{
    vec3 origin;
    vec3 dir;
};

struct RayTracingMaterial
{
    vec3 color;

    vec3 emissionColor;
    float emissionStrength;

    float smoothness;
    float metallic;
    vec3 specularColor;
};

struct Sphere
{
    float radius;
    Transform transform;
    RayTracingMaterial material;
};

struct HitInfo
{
    bool didHit;
    float distance;
    vec3 pos;
    vec3 normal;
    RayTracingMaterial material;
};

struct Sun
{
    vec3 dir;
    float focus;
    float intensity;
};



//========== Const ==========//
const float PI = 3.14159;
const float INFINITY = 1.0 / 0.0;

const int MAX_BOUNCE_COUNT = 128;
const int RAY_COUNT_PER_PIXEL = 10;

const Transform DEFAULT_TRANSFORM = Transform(vec3(0));

const RayTracingMaterial DEFAULT_MATERIAL = RayTracingMaterial(vec3(1) , vec3(0) , 0.0 , 0.0 , 0.0 , vec3(1));

const Sphere DEFAULT_SPHERE = Sphere(1.0 , DEFAULT_TRANSFORM , DEFAULT_MATERIAL);

const HitInfo DEFAULT_HITINFO = HitInfo(false , 0.0 , vec3(0) , vec3(0) , DEFAULT_MATERIAL);




//========== Functions ==========//

//----- Camera -----//
void InitCamera(inout Camera cam , float nearClippingPlane , float fov)
{
    cam.nearClippingPlane = nearClippingPlane;
    cam.fov = fov;

    cam.transform.position = vec3(0);

    cam.cameraForward = vec3(0 , 0 , 1);
    cam.cameraUp = vec3(0 , 1 , 0);
    cam.cameraRight = vec3(1 , 0 , 0);
}

vec2 GetUV(vec2 fragCoord)
{
    return fragCoord.xy / iResolution.xy;
}

vec2 GetScreenSize(Camera cam)
{
    float aspect = iResolution.x / iResolution.y;

    float height = cam.nearClippingPlane * tan(0.5 * cam.fov * PI / 180.0) * 2.0;
    float width = height * aspect;

    return vec2(width , height);
}

Ray GetRay(Camera cam , vec2 fragCoord)
{
    Ray ray;

    ray.origin = cam.transform.position;

    vec2 uvCenter = GetUV(fragCoord) * 2.0 - 1.0;
    vec2 screenSize = GetScreenSize(cam);

    vec3 targetPoint = vec3(screenSize / 2.0 * uvCenter , cam.nearClippingPlane);
    targetPoint = cam.cameraRight * targetPoint.x + cam.cameraUp * targetPoint.y + cam.cameraForward * targetPoint.z;

    ray.dir = normalize(targetPoint - ray.origin);

    return ray;
}


//----- Transform -----//       // TODO：旋转，并修改 "GetRay" 中的目标点坐标系变换方式
void UpdatePosition(inout Transform transform , vec3 newPos)
{
    transform.position = newPos;
}


//----- Sphere -----//
void InitSphere(inout Sphere sphere , float r , vec3 color , vec3 emissionColor , float emissionStrength , float smoothness , float metallic , vec3 specularColor)
{
    sphere.radius = r;
    sphere.transform.position = vec3(0);
    sphere.material = RayTracingMaterial(color , emissionColor , emissionStrength , smoothness , metallic , specularColor);
}


//----- Random -----//
// 获取生成随机数的种子
uint CreateRandomSeed(vec2 uv)
{
    uvec2 pixelCoord = uvec2(uv * iResolution.xy);
    uint seed = pixelCoord.x * 1973u + pixelCoord.y * 9277u + uint(iTime * 1000.0);
    seed = seed * 747796405u + 2891336453u;
    return seed;
}

float RandomValue01(inout uint seed)
{
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return float(seed) / 4294967295.0; // 转换为0-1范围
}

// 生成标准正态分布下的随机数
float RandomValueNormalDistribution(inout uint seed)
{
    // Thanks to https://stackoverflow.com/a/6178290
    
    float theta = 2.0 * PI * RandomValue01(seed);
    float rho = sqrt(-2.0 * log(RandomValue01(seed)));
    return rho * cos(theta);
}

vec3 RandomDirection(inout uint seed)
{
    float x = RandomValueNormalDistribution(seed);
    float y = RandomValueNormalDistribution(seed);
    float z = RandomValueNormalDistribution(seed);

    return normalize(vec3(x , y , z));
}

vec3 RandomHemisphereDirection(vec3 normal , inout uint seed)
{
    vec3 dir = RandomDirection(seed);
    return dir * sign(dot(normal , dir));
}


//----- Sun -----//
void InitSun(inout Sun sun , vec3 dir , float focus , float intensity)
{
    sun.dir = normalize(dir);
    sun.focus = focus;
    sun.intensity = intensity;
}




//========== Statement ==========//
Camera mainCamera;
Sun sun;

Sphere[] spheres = Sphere[]
(
    DEFAULT_SPHERE , DEFAULT_SPHERE , DEFAULT_SPHERE , DEFAULT_SPHERE , DEFAULT_SPHERE
);




//========== Environment ==========//
vec3 GetEnvironmentLight()
{
    return vec3(0);

    vec3 color = vec3(0.57, 0.67, 0.75);
    return color;
}




//========== Ray Collision ==========//
HitInfo RaySphere(Ray ray , Sphere sphere)
{
    HitInfo info = DEFAULT_HITINFO;

    // 转换至局部坐标系（以球心为原点）
    vec3 offsetOrigin = ray.origin - sphere.transform.position;

    // 当 pow(ro + rd * d , 2.0) = r * r 时，射线与球面相交
    float a = dot(ray.dir , ray.dir);
    float b = 2.0 * dot(offsetOrigin , ray.dir);
    float c = dot(offsetOrigin , offsetOrigin) - sphere.radius * sphere.radius;

    float delta = b * b - 4.0 * a * c;
    if (delta >= 0.0)
    {
        // 取近点
        float d = (-b - sqrt(delta)) * 0.5;

        info.didHit = d >= 0.0;
        info.distance = d;
        info.pos = ray.origin + ray.dir * d;
        info.normal = normalize(info.pos - sphere.transform.position);
    }

    return info;
}

HitInfo CalculateCollision(Ray ray)
{
    HitInfo closestInfo = DEFAULT_HITINFO;
    closestInfo.distance = INFINITY;

    for (int i=0 ; i<spheres.length() ; i++)
    {
        HitInfo info = RaySphere(ray , spheres[i]);

        if (info.didHit && info.distance < closestInfo.distance)
        {
            closestInfo = info;
            closestInfo.material = spheres[i].material;
        }
    }

    return closestInfo;
}

vec3 Trace(Ray ray , inout uint seed)
{
    vec3 rayColor = vec3(1);
    vec3 incomingLight = vec3(0);

    for (int i=0 ; i<=MAX_BOUNCE_COUNT ; i++)
    {
        HitInfo info = CalculateCollision(ray);

        if (info.didHit)
        {
            RayTracingMaterial mat = info.material;

            ray.origin = info.pos;

            vec3 diffuseDir = normalize(info.normal + RandomDirection(seed));
            vec3 specularDir = normalize(reflect(ray.dir , info.normal));

            bool isSpecularBounce = mat.metallic >= RandomValue01(seed);

            ray.dir = mix(diffuseDir , specularDir , mat.smoothness * (isSpecularBounce ? 1.0 : 0.0));

            vec3 emittedLight = mat.emissionColor * mat.emissionStrength;
            incomingLight += emittedLight * rayColor;

            rayColor *= mix(mat.color , mat.specularColor , isSpecularBounce ? 1.0 : 0.0);
        }
        else
        {
            incomingLight += GetEnvironmentLight() * rayColor;
            break;
        }
    }

    return incomingLight;
}




//========== Rendering ==========//
void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // 初始化物体
    InitCamera(mainCamera , 0.3 , 60.0);
    InitSun(sun , vec3(3 , -1 , -2) , 1.0 , 1.0);

    InitSphere(spheres[0] , 1.0 , vec3(1.0) , vec3(0.0) , 0.0 , 0.0 , 0.0 , vec3(1));
    InitSphere(spheres[1] , 0.7 , vec3(0.96, 0.18, 0.18) , vec3(0) , 0.0 , 0.0 , 0.0 , vec3(1));
    InitSphere(spheres[2] , 1.2 , vec3(0.17, 0.44, 0.91) , vec3(0.0) , 0.0 , 0.0 , 0.0 , vec3(1));
    InitSphere(spheres[3] , 20.0 , vec3(0.72, 0.38, 0.88) , vec3(0) , 0.0 , 0.0 , 0.0 , vec3(1));
    InitSphere(spheres[4] , 10.0 , vec3(0) , vec3(1) , 1.6 , 0.0 , 0.0 , vec3(1));

    UpdatePosition(spheres[0].transform , vec3(cos(iTime) , sin(iTime / 3.0) + 1.0 , 5.0 + sin(iTime)));
    UpdatePosition(spheres[1].transform , vec3(2.0 + cos(iTime / 1.1 + 0.3) , -0.3 , 5.0 + sin(iTime)));
    UpdatePosition(spheres[2].transform , vec3(-2.5 + cos(iTime) , 0 , 5.0 + sin(iTime + 1.6)));
    UpdatePosition(spheres[3].transform , vec3(0 , -21 , 6));
    UpdatePosition(spheres[4].transform , vec3(3 , 11 , 10));


    // 随机数种
    uint seed = CreateRandomSeed(GetUV(fragCoord));


    // 获取射线
    Ray ray = GetRay(mainCamera , fragCoord);


    // 光线追踪
    vec3 totalIncomingLight = vec3(0);
    for (int i=0 ; i<RAY_COUNT_PER_PIXEL ; i++)
    {
        totalIncomingLight += Trace(ray , seed);
    }
    totalIncomingLight /= float(RAY_COUNT_PER_PIXEL);


    // 输出片元颜色
    vec3 color = totalIncomingLight;

    fragColor = vec4(color , 1);
}