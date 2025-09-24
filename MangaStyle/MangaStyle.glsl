// 左手系
#define PI 3.1415926



//========== Const ==========//
const int MAX_MARCH_STEP = 512;
const float EPSILON = 1e-5;

const float UV_SCALING_FACTOR = 8.0;        // 大于等于 4 时效果较好

const float SPOT_SCALE = 0.3;               // 0.1 ~ 0.9
const float LINE_WIDTH = 0.3;               // 0.0 ~ 1.0




//==========Structs ==========//
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

struct Sphere
{
    vec3 center;
    float radius;
};

struct DirLight
{
    vec3 dir;
    vec3 color;
    float intensity;
};




//========== Objects ==========//
Camera cam = Camera(vec3(0 , 0 , -5) ,
                    vec3(1 , 0 , 0) , vec3(0 , 1 , 0) , vec3(0 , 0 , 1) ,
                    60.0 , 0.03 , 200.0);

Sphere sphere1 = Sphere(vec3(0 , 0 , 7) , 2.0);


DirLight dirLight = DirLight(vec3(-2 , -3 , 4.8) , vec3(1 , 1 , 1) , 1.0);





//========== Ray March ==========//
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


vec3 GetSphereNormal(vec3 pos , Sphere sphere)
{
    return normalize(pos - sphere.center);
}


float SDSphere(vec3 pos ,Sphere sphere)
{
    return length(pos - sphere.center) - sphere.radius;
}

float SDScene(vec3 pos)
{
    return SDSphere(pos , sphere1);
}

float RayMarch(Ray ray , float start , float end)
{
    float d = start;

    for (int i = 0 ; i < MAX_MARCH_STEP ; ++i)
    {
        vec3 pos = ray.origin + ray.dir * d;

        float result = SDScene(pos);
        d += result;

        if (d < EPSILON || d > end * 1.1)
            break;
    }

    return d;
}





//========== Manga Style ==========//
vec2 GetScaledUV(vec2 uv , float aspect , out vec2 scaledUVIndex)
{
    vec2 wideRangeUV = uv * pow(2.0 , UV_SCALING_FACTOR) * vec2(aspect , 1.0);
    
    scaledUVIndex = floor(wideRangeUV);

    return wideRangeUV - scaledUVIndex;
}

float GetMangaSpot(vec2 scaledUV , float spotScale)
{
    return smoothstep(spotScale - 0.1 , spotScale + 0.1 , distance(scaledUV , vec2(0.5 , 0.5)));
}

float GetMangaLineArrangement(vec2 scaledUV , vec2 scaledUVIndex , float angle , float lineWidth)                   // 角度为水平和竖直时效果没那么好看
{
    vec2 lineDir = vec2(-sin(radians(angle)) , cos(radians(angle)));

    vec2 v = scaledUVIndex + scaledUV;

    return step(lineWidth , fract(dot(v , lineDir)));
}



void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;


    float width , height;
    Ray ray = GetRay(uv , width , height);
    float aspect = width / height;


    // 灯光变换
    dirLight.dir = vec3(dirLight.dir.x * sin(iTime) , dirLight.dir.y , dirLight.dir.z * cos(iTime));


    vec3 color = vec3(0.24);


    float d = RayMarch(ray , cam.near , cam.far);
    if (d < cam.far)
    {
        vec3 pos = ray.origin + ray.dir * d;
        vec3 normal = GetSphereNormal(pos , sphere1);

        vec3 lightDir = normalize(-dirLight.dir);

        // float NoL = dot(normal , lightDir) * 0.5 + 0.5;
        float NoL = max(0.0 , dot(normal , lightDir));


        // 绘制网点图
        vec2 scaledUVIndex;
        vec2 scaledUV = GetScaledUV(uv , aspect , scaledUVIndex);

        float spot = GetMangaSpot(scaledUV , 1.0 - NoL);
        float line = GetMangaLineArrangement(scaledUV , scaledUVIndex , 60.0 , 1.0 - NoL);

        color = vec3(line);
    }


    fragColor = vec4(color , 1);
}