#if !defined(MY_LIGHTING_INCLUDED)
#define MY_LIGHTING_INCLUDED
#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;
float _Metallic;
float _Smoothness;

struct VertexData
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Interpolators
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 worldPos : TEXCOORD2;
    
    // #if defined(SHADOWS_SCREEN)
    //     float4 shadowCoordinates : TEXCOORD3;
    // #endif
    SHADOW_COORDS(3)
    #if defined(VERTEXLIGHT_ON)
        float3 vertexLightColor : TEXCOORD4;
    #endif
};

void ComputeVertexLightColor (inout Interpolators i)
{
    #if defined(VERTEXLIGHT_ON)
        // 1个顶点光
        // float3 lightPos = float3(unity_4LightPosX0.x, unity_4LightPosY0.x, unity_4LightPosZ0.x);
        // float3 lightVec = lightPos - i.worldPos;
        // float3 lightDir = normalize(lightVec);
        // float ndotl = DotClamped(i.normal, lightDir);
        // float attenuation = 1 / (1 + dot(lightVec, lightVec) * unity_4LightAtten0);
        // i.vertexLightColor = unity_LightColor[0].rgb * ndotl * attenuation;
        // 4个顶点光，使用内置函数
        i.vertexLightColor = Shade4PointLights(
            unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
            unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
            unity_4LightAtten0, i.worldPos, i.normal
        );
    #endif
}

Interpolators MyVertexProgram(VertexData v)
{
    Interpolators i;
    i.uv = TRANSFORM_TEX(v.uv, _MainTex);
    i.pos = UnityObjectToClipPos(v.vertex);
    // i.normal = mul((float3x3)unity_ObjectToWorld, v.normal);
    //转置世界到对象矩阵
    // i.normal = mul(transpose((float3x3)unity_ObjectToWorld), v.normal);
    i.normal = UnityObjectToWorldNormal(v.normal);
    i.worldPos = mul(unity_ObjectToWorld, v.vertex);
    
    i.normal = normalize(i.normal);

    // #if defined(SHADOWS_SCREEN)
    //     // i.shadowCoordinates.xy = (float2(i.position.x, -i.position.y) + i.position.w) * 0.5;
    //     // i.shadowCoordinates.zw = i.position.zw;
    //     // 使用unity的内置接口
    //     i.shadowCoordinates = ComputeScreenPos(i.position);
    // #endif
    //使用内置宏替换上面操作
    TRANSFER_SHADOW(i);
    ComputeVertexLightColor(i);
    return i;
}

UnityLight CreateLight(Interpolators i)
{
    UnityLight light;
    #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
        light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
    #else
        light.dir = _WorldSpaceLightPos0.xyz;
    #endif
    
    // 计算衰减
    // float3 lightVec = _WorldSpaceLightPos0.xyz - i.worldPos;
    // float attenuation = 1 / (1 + dot(lightVec, lightVec));
    // #if defined(SHADOWS_SCREEN)
    //     // float attenuation = tex2D(_ShadowMapTexture, i.shadowCoordinates.xy / i.shadowCoordinates.w);
    //     //使用内置宏
    //     float attenuation = SHADOW_ATTENUATION(i);
    // #else
    //     // 使用Unity内置函数计算衰减
    //     UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos);
    // #endif
    // 内置宏已经包含阴影衰减处理，第二个参数需要传入插值器
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos);
    light.color = _LightColor0.rgb * attenuation;
    light.ndotl = DotClamped(i.normal, light.dir);
    return light;
}

float3 BoxProjection(float3 direction, float3 position, float4 cubemapPosition, float3 boxMin, float3 boxMax)
{
    // boxMin -= position;
    // boxMin -= position;
    // float x = (direction.x > 0 ? boxMin.x : boxMin.x) / direction.x;
    // float y = (direction.y > 0 ? boxMin.y : boxMin.y) / direction.y;
    // float z = (direction.z > 0 ? boxMax.z : boxMin.z) / direction.z;

    // float scalar = min(min(x, y), z);
    #if UNITY_SPECCUBE_BOX_PROJECTION
    if (cubemapPosition.w > 0)
    {
        float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
        float scalar = min(min(factors.x, factors.y), factors.z);
        direction = direction * scalar + (position - cubemapPosition);
    }
    #endif
    return direction;
}

UnityIndirect CreateIndirectLight(Interpolators i, float3 viewDir)
{
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    #if defined(VERTEXLIGHT_ON)
        indirectLight.diffuse = i.vertexLightColor;
    #endif 
    #if defined(FORWARD_BASE_PASS)
        indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
        // 对天空盒立方体贴图进行采样
        // float3 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, i.normal);
        // indirectLight.specular = envSample;
        // 处理HDR & 使用反射向量采样
        // float3 reflectionDir = reflect(-viewDir, i.normal);
        // float4 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectionDir);
        // indirectLight.specular = DecodeHDR(envSample, unity_SpecCube0_HDR);
        // 使用mipmap级别对立方体贴图进行采样
        // float3 reflectionDir = reflect(-viewDir, i.normal);
        // float roughness = 1 - _Smoothness;
        // roughness *= 1.7 - 0.7 * roughness;
        // float4 envSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectionDir, roughness * UNITY_SPECCUBE_LOD_STEPS);
        // indirectLight.specular = DecodeHDR(envSample, unity_SpecCube0_HDR);
        // 使用内置接口
        float3 reflectionDir = reflect(-viewDir, i.normal);
        Unity_GlossyEnvironmentData envData;
        envData.roughness = 1 - _Smoothness;
        // envData.reflUVW = reflectionDir;
        envData.reflUVW = BoxProjection(reflectionDir, i.worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
        // indirectLight.specular = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
        // 增加第二个反射探针
        float3 probe0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
        envData.reflUVW = BoxProjection(reflectionDir, i.worldPos, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);
        // float3 probe1 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0), unity_SpecCube0_HDR, envData);
        // indirectLight.specular = lerp(probe1, probe0, unity_SpecCube0_BoxMin.w);
        // 优化-需要混合时才进行插值
        #if UNITY_SPECCUBE_BLENDING
            float interpolator = unity_SpecCube0_BoxMin.w;
            UNITY_BRANCH
            if (interpolator < 0.99999)
            {
                // float3 probe0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
                float3 probe1 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0), unity_SpecCube0_HDR, envData);
                indirectLight.specular = lerp(probe1, probe0, interpolator);
            }
            else
            {
                indirectLight.specular = probe0;
            }      
        #else
            indirectLight.specular = probe0;
        #endif
    #endif
    return indirectLight;
}
//试验球谐函数的9项输出
// float4 MyFragmentProgram(Interpolators i) : SV_TARGET
// {
//     i.normal = normalize(i.normal);
//     float t = i.normal.z * i.normal.z;
//     return t > 0 ? t : float4(1, 0, 0, 1) * -t;
// }
// 使用Untiy PBS函数计算
float4 MyFragmentProgram(Interpolators i) : SV_TARGET
{
    i.normal = normalize(i.normal);
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
    float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
    // 纯介电材质也有高光反射，使用内置函数
    float3 specularTint;
    float oneMinusReflectivity;
    albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);
    
    // float3 shColor = ShadeSH9(float4(i.normal, 1));
    // return float4(shColor, 1);

    return UNITY_BRDF_PBS(albedo, specularTint, oneMinusReflectivity, _Smoothness, i.normal, viewDir, CreateLight(i), CreateIndirectLight(i, viewDir));
}

#endif