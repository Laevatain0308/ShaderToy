// 注意：该世界坐标系为左手坐标系，向量叉乘运用左手定则!!!



// 常量
const float PI = 3.1415926535;

const int MAX_RAY_MARCH_STEPS = 512;                  // 光线步进最大步数
const float START_DISTANCE = 0.001;                   // 起始距离（相机近裁面）
const float MAX_DISTANCE = 200.0;                     // 最大终止距离（相机远裁面）
const float EPSILON = 0.0001;                         // 偏移量允许范围

const float AMBIENT_STRENGTH = 0.05;                  // 环境光常量
const float SHININESS = 64.0;                         // 高光指数（控制镜面反射的范围，值越大，高光越集中）



// 相机属性
vec3 cameraPos = vec3(0 , 0 , 0);
vec3 cameraForward = vec3(0 , 0 , 1);
vec3 cameraUp = vec3(0 , 1 , 0);
float fov = 60.0;                                     // 视场角（单位：度）


// 平行光
struct DirLight
{
    vec3 dir;
    vec3 color;
};

// 点光源
struct PointLight
{
    vec3 pos;
    vec3 color;

    // 光照衰减系数
    float intensity;    // 光强
    float linear;       // 线性
    float quadratic;    // 二次
};



struct Material
{
    vec3 color;              // 存储本身颜色
    float smoothness;        // 平滑度（0 ~ 1）
};


struct Transform
{
    vec3 position;
    vec3 rotation;           // 角度制
};


struct Object
{
    Transform transform;
    Material material;
};


struct SDFResult
{
    float d;        // 存储SDF的距离
    Material mat;   // 材质
};





//========== 屏幕坐标重映射 ==========//

// 利用屏幕宽高比重映射UV（以短边为1）
vec2 FixUVByAspect(vec2 fragCoord)
{
    return (fragCoord.xy * 2.0 - iResolution.xy) / min(iResolution.x , iResolution.y);
}






//========== 坐标系变换 ==========//

// 视空间转世界空间
vec3 TransformViewToWorld(vec3 posVS)
{
    cameraForward = normalize(cameraForward);
    cameraUp = normalize(cameraUp);

    vec3 cameraRight = normalize(cross(cameraUp , cameraForward));
    cameraUp = normalize(cross(cameraForward , cameraRight));

    return cameraPos + cameraRight * posVS.x + cameraUp * posVS.y + cameraForward * posVS.z; 
}






//========== 辅助函数 ==========//

// 获取点到直线的距离
float GetDistanceFromPointToRay(vec3 ro , vec3 rd , vec3 pointPos)
{
    return length(cross(pointPos - ro , rd)) / length(rd);
}






//========== 创建物体 ==========//
Material CreateMaterial(vec3 color , float smoothness)
{
    return Material(color , smoothness);
}

Transform CreateTransform(vec3 pos , vec3 rot)
{
    return Transform(pos , rot);
}

Object CreateObject(Transform transform , Material mat)
{
    return Object(transform , mat);
}



//========== 变换 ==========//
vec3 RotateByQuaternion(vec3 localPos , vec3 axis , float angle)
{
    vec4 q = vec4(axis * sin(angle * 0.5) , cos(angle * 0.5));
    return localPos + 2.0 * cross(q.xyz , cross(q.xyz , localPos) + q.w * localPos);
}

// 对世界坐标应用局部变换
vec3 ProceedPosition(vec3 pos , Transform transform)
{
    // 转换到局部坐标
    vec3 localPos = pos - transform.position;

    // 无需旋转则直接返回
    if (transform.rotation == vec3(0))
        return localPos;

    // 应用旋转
    localPos = transform.rotation.x != 0.0 ? RotateByQuaternion(localPos , vec3(1 , 0 , 0) , transform.rotation.x * PI / 180.0) : localPos;
    localPos = transform.rotation.y != 0.0 ? RotateByQuaternion(localPos , vec3(0 , 1 , 0) , transform.rotation.y * PI / 180.0) : localPos;
    localPos = transform.rotation.z != 0.0 ? RotateByQuaternion(localPos , vec3(0 , 0 , 1) , transform.rotation.z * PI / 180.0) : localPos;

    return localPos;
}



//========== 透视投影下的光追基础 ==========//

// 获取相机向每个屏幕像素发射的射线
vec3 GetRayToPixel(vec2 uv)
{
    float z = 1.0 / tan(fov * 0.5 * PI / 180.0);
    return normalize(TransformViewToWorld(vec3(uv , z)));
}



//========== SDF ==========//

// 合并SDF形状
SDFResult UnionSDFResult(SDFResult x , SDFResult y)
{
    if (x.d < y.d)
        return x;
    else
        return y;
}

SDFResult SmoothSDFResult(SDFResult x , SDFResult y , float k)
{
    float h = clamp(0.5 + 0.5 * (y.d - x.d) / k , 0.0 , 1.0);
    vec3 c = clamp(0.5 + 0.5 * (y.mat.color - x.mat.color) / k , 0.0 , 1.0);

    return SDFResult(mix(y.d , x.d , h) - k * h * (1.0 - h) ,
                     Material(mix(y.mat.color , x.mat.color , h) - k * h * (1.0 - h) ,
                              1.0));
}


// 球形SDF
SDFResult SDSphere(vec3 pos , Object object , float radius)
{
    return SDFResult(length(ProceedPosition(pos , object.transform)) - radius , object.material);
}

// 长方体SDF
SDFResult SDCube(vec3 pos , Object object , vec3 sizes)
{
    vec3 q = abs(ProceedPosition(pos , object.transform)) - sizes;
    return SDFResult(length(max(q , 0.0)) + min(max(q.x , max(q.y , q.z)) , 0.0) ,
                     object.material);
}

// 圆环SDF
SDFResult SDTorus(vec3 pos , Object object , vec2 t)
{
    pos = ProceedPosition(pos , object.transform);
    return SDFResult(length(vec2(length(pos.xz) - t.x , pos.y)) - t.y , object.material);
}

// 总SDF
SDFResult SDScene(vec3 pos)
{
    SDFResult result;


    Object sphere_1 = CreateObject(CreateTransform(vec3(0 , -0.4 , 5) , vec3(0)) , 
                                   CreateMaterial(vec3(1.0) , 0.09));
    result = SDSphere(pos , sphere_1 , 1.0);


    Object sphere_2 = CreateObject(CreateTransform(vec3(1.5 , 2.4 , 9) , vec3(0)) ,
                                   CreateMaterial(vec3(0.95, 0.96, 0.59) , 1.0));
    result = UnionSDFResult(result , SDSphere(pos , sphere_2 , 1.0));


    Object plane = CreateObject(CreateTransform(vec3(0 , -1.55 , 100) , vec3(0 , 0 , 0)) , 
                                CreateMaterial(vec3(1) , 0.0));
    result = UnionSDFResult(result , SDCube(pos , plane , vec3(100 , 0.1 , 100)));


    Object cube = CreateObject(CreateTransform(vec3(-3 , 0.7 , 9) , vec3(45 , 45 , 45)) ,
                               CreateMaterial(vec3(1.0) , 0.0));
    result = UnionSDFResult(result , SDCube(pos , cube , vec3(1)));


    Object torus = CreateObject(CreateTransform(vec3(-2 , 5 , 12) , vec3(-30 , 0 , -15)) ,
                                CreateMaterial(vec3(1.0) , 1.0));
    result = UnionSDFResult(result , SDTorus(pos , torus , vec2(2 , 0.6)));


    return result;
}



//========== Ray March ==========//
SDFResult RayMarch(vec3 ro , vec3 rd , float start , float end)
{
    SDFResult result;
    float d = start;

    for (int i=0 ; i<MAX_RAY_MARCH_STEPS ; i++)
    {
        vec3 pos = ro + rd * d;

        result = SDScene(pos);
        d += result.d;

        if (d < EPSILON || d > end * 1.1)
            break;
    }

    result.d = d;
    return result;
}



//========== 法线计算 ==========//
// 利用 中心差分法 ，对某点以数值近似的方式，获取该点在SDScene的距离场梯度，即法线
vec3 CalculateNormal(vec3 pos)
{
    vec2 e = vec2(1.0 , -1.0) * 0.0005;     // 微笑偏移量

    return normalize(
        e.xyy * SDScene(pos + e.xyy).d +      // x方向上的差分：pos + (e.x , e.y , e.y)
        e.yyx * SDScene(pos + e.yyx).d +        // y方向上的差分：pos + (e.y , e.y , e.x)
        e.yxy * SDScene(pos + e.yxy).d +        // z方向上的差分：pos + (e.y , e.x , e.y)
        e.xxx * SDScene(pos + e.xxx).d          // 对称差分，增强稳定性
    );
}




//========== 光照处理 ==========//
vec3 CalculateDirLight(SDFResult result , vec3 fragNormal , vec3 rd , DirLight light)
{
    vec3 lightDir = normalize(-light.dir);

    // 漫反射部分
    float NoL = max(0.0 , dot(fragNormal , lightDir));

    // 高光部分
    vec3 reflectVector = normalize(reflect(-lightDir , fragNormal));
    float Rov = pow(max(0.0 , dot(reflectVector , normalize(-rd))) , SHININESS);


    vec3 diffuse = NoL * light.color * result.mat.color;
    vec3 specular = Rov * clamp(result.mat.smoothness , 0.0 , 1.0) * light.color;


    return diffuse + specular;
}

vec3 CalculatePointLight(SDFResult result , vec3 fragPos , vec3 fragNormal , vec3 rd , PointLight light)
{
    vec3 lightDir = normalize(light.pos - fragPos);

    // 光照衰减
    float distanceToLightPoint = distance(fragPos , light.pos);
    float attenuaion = light.intensity / (1.0 + light.linear * distanceToLightPoint + light.quadratic * distanceToLightPoint * distanceToLightPoint);
    
    // 漫反射部分
    float NoL = max(0.0 , dot(fragNormal , lightDir));

    // 高光部分
    vec3 reflectVector = normalize(reflect(-lightDir , fragNormal));
    float RoV = pow(max(0.0 , dot(reflectVector , normalize(-rd))) , SHININESS);


    vec3 diffuse = NoL * attenuaion * light.color;
    vec3 specular = RoV * clamp(result.mat.smoothness , 0.0 , 1.0) * attenuaion * light.color;


    return diffuse + specular;
}



//========== 阴影计算 ==========//
float CalculateHardShadow(vec3 ro , vec3 rd , float min , float max)
{
    float t = min + 0.1;

    for (int i=0 ; i<MAX_RAY_MARCH_STEPS ; i++)
    {
        float d = SDScene(ro + rd * t).d;

        if (d < EPSILON)
            return 0.0;

        t += d;

        if (t >= max)
            break;
    }

    return 1.0;
}





DirLight dirLight = DirLight(vec3(2 , -3 , 1) , vec3(0.11, 0.51, 1.0));

PointLight pointLights[] = PointLight[]
(
    PointLight(vec3(-4 , 2 , 0) , vec3(1) , 1.0 , 0.022 , 0.0019)
    // PointLight(vec3(-1 , 1 , -3) , vec3(0.42, 1.0, 0.72) , 1.0 , 0.022 , 0.0019) , 
    // PointLight(vec3(3 , -3 , 3.2) , vec3(0.98, 0.11, 0.11) , 0.5 , 0.022 , 0.0019)
);




//========== 主渲染 ==========//
void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // [Debug] 鼠标操控相机方向
    // cameraForward = vec3(FixUVByAspect(iMouse.xy) , 1);

    // [Debug] 鼠标操控平行光旋转
    // dirLight.dir = vec3(-3.0 * FixUVByAspect(iMouse.xy) , 1);

    // [Debug] 点光源位置随时间变换
    pointLights[0].pos = vec3(6.0 * cos(iTime) , 5 , 6.0 * sin(iTime));
    // pointLights[1].pos = vec3(3 , -6.0 * sin(iTime) , 1.6);



    // 获取像素大小
    float pixelSize = 1.0 / min(iResolution.x , iResolution.y);


    // 归一化屏幕空间坐标
    vec2 uv = FixUVByAspect(fragCoord);


    // 获取射线
    vec3 rayOrigination = cameraPos;
    vec3 rayDir = GetRayToPixel(uv);


    // 初始化输出颜色
    vec3 color = vec3(0);
    // vec3 bgColor = mix(vec3(0.02), vec3(0.1, 0.2, 0.4), -rayDir.y);


    // 光线步进
    SDFResult result = RayMarch(rayOrigination , rayDir , START_DISTANCE , MAX_DISTANCE);
    if (result.d < MAX_DISTANCE)
    {
        vec3 pos = rayOrigination + rayDir * result.d;
        vec3 normal = CalculateNormal(pos);

        // 环境光
        vec3 ambient = AMBIENT_STRENGTH * result.mat.color;
        color += ambient;

        // 平行光处理
        // color += CalculateDirLight(result , normal , rayDir , dirLight);
        
        // 点光源处理
        for (int i=0 ; i<pointLights.length() ; i++)
        {
            color += CalculatePointLight(result , pos , normal , rayDir , pointLights[i]);
        
            float shadow = CalculateHardShadow(pos + EPSILON * normal , normalize(pointLights[i].pos - pos) , START_DISTANCE , MAX_DISTANCE);
            color *= shadow;
        }

    }



    // 最终片元着色器输出
    fragColor = vec4(color , 1);
}