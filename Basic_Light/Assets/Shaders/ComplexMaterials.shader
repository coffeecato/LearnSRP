Shader "coffeecat/BasicRender/ComplexMaterials"
{
    Properties
    {
        _Tint ("Tint", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset] _NormalMap ("Normals", 2D) = "bump"{}
        _BumpScale ("Bump Scale", Float) = 1
        [NoScaleOffset] _MetallicMap ("Metallic", 2D) = "white" {}
        [Gamma]_Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _DetailTex ("Detail Albedo", 2D) = "gray" {}
        [NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" {}
        _DetailBumpScale ("Detail Bump Scale", Float) = 1
        [NoScaleOffset] _EmissionMap ("Emission", 2D) = "black"{}
        _Emission ("Emission", Color) = (0, 0, 0)
    }
    SubShader
    {
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            CGPROGRAM
            #pragma target 3.0
            #pragma shader_feature _ _METALLIC_MAP
            #pragma shader_feature _ _SMOOTHNESS_ALBEDO _SMOOTHNESS_METALLIC
            #pragma shader_feature _EMISSION_MAP
            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram
            #define BINORMAL_PER_FRAGMENT
            #define FORWARD_BASE_PASS

            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"
            //需要把光照加进来，自己实现间接光照，不要修改MyLighting.cginc
            // #include "MyLighting.cginc"

            float4 _Tint;
            sampler2D _MainTex, _DetailTex, _MetallicMap, _EmissionMap;
            float4 _MainTex_ST, _DetailTex_ST;
            sampler2D _NormalMap, _DetailNormalMap;
            float _BumpScale, _DetailBumpScale;
            float _Metallic;
            float _Smoothness;
            float3 _Emission;

            struct VertexData
            {
                float4 position : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Interpolators
            {
                float4 position : SV_POSITION;
                float4 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                
                #if defined(BINORMAL_PER_FRAGMENT)
                    float4 tangent : TEXCOORD2;
                #else
                    float3 tangent : TEXCOORD2;
                    float3 binormal : TEXCOORD3;
                #endif

                float3 worldPos : TEXCOORD4;

                #if defined(VERTEXLIGHT_ON)
                    float3 vertexLightColor : TEXCOORD5;
                #endif 
                SHADOW_COORDS(6)
            };
            
            float GetMetallic(Interpolators i)
            {
                return tex2D(_MetallicMap, i.uv.xy).r * _Metallic;
            }

            float GetSmoothness(Interpolators i)
            {
                float smoothness = 1;
                #if defined(_SMOOTHNESS_ALBEDO)
                    smoothness = tex2D(_MainTex, i.uv.xy).a;
                #elif defined(_SMOOTHNESS_METALLIC) && defined(_METALLIC_MAP)
                    return tex2D(_MetallicMap, i.uv.xy).a;
                #endif
                return smoothness * _Smoothness;
            }

            float3 GetEmission(Interpolators i)
            {
                #if defined(FORWARD_BASE_PASS)
                    #if defined(_EMISSION_MAP)
                        return tex2D(_EmissionMap, i.uv.xy) * _Emission;
                    #else
                        return _Emission;
                    #endif
                    return 0;
                #endif
                return 0;
            }

            float3 CreateBinormal(float3 normal, float3 tangent, float binormalSign)
            {
                return cross(normal, tangent.xyz) * (binormalSign * unity_WorldTransformParams.w);
            }

            Interpolators MyVertexProgram(VertexData v)
            {
                Interpolators i;
                i.position = UnityObjectToClipPos(v.position);
                i.normal = UnityObjectToWorldNormal(v.normal);
                i.worldPos = mul(unity_ObjectToWorld, v.position);
                #if defined(BINORMAL_PER_FRAGMENT)
                    i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
                #else
                    i.tanget = UnityObjectToWorldDir(v.tanget.xyz);
                    i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
                #endif

                i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
                i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
                TRANSFER_SHADOW(i);
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
                // 内置宏已经包含阴影衰减处理，第二个参数需要传入插值器
                UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos);
                light.color = _LightColor0.rgb * attenuation;
                light.ndotl = DotClamped(i.normal, light.dir);
                return light;
            }

            float3 BoxProjection(float3 direction, float3 position, float4 cubemapPosition, float3 boxMin, float3 boxMax)
            {
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
                    float3 reflectionDir = reflect(-viewDir, i.normal);
                    Unity_GlossyEnvironmentData envData;
                    envData.roughness = 1 - _Smoothness;
                    // envData.reflUVW = reflectionDir;
                    envData.reflUVW = BoxProjection(reflectionDir, i.worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
                    // indirectLight.specular = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
                    // 增加第二个反射探针
                    float3 probe0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
                    envData.reflUVW = BoxProjection(reflectionDir, i.worldPos, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);
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

            // 使用法线贴图代替高度贴图
            void InitializeFragmentNormal(inout Interpolators i)
            {
                float3 mainNormal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
                float3 detailNormal = UnpackScaleNormal(tex2D(_DetailNormalMap, i.uv.zw), _DetailBumpScale);
                float3 tangentSpaceNormal = BlendNormals(mainNormal, detailNormal);
                #if defined(BINORMAL_PER_FRAGMENT)
                    float3 binormal = CreateBinormal(i.normal, i.tangent.xyz, i.tangent.w);
                #else
                    float3 binormal = i.binormal;
                #endif
                i.normal = normalize(tangentSpaceNormal.x * i.tangent + tangentSpaceNormal.y * binormal + tangentSpaceNormal.z * i.normal);
            }
            // 使用Untiy PBS函数计算
            float4 MyFragmentProgram(Interpolators i) : SV_TARGET
            {
                InitializeFragmentNormal(i);
                float3 lightDir = _WorldSpaceLightPos0.xyz;
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                // return DotClamped(lightDir, i.normal);
                float3 lightColor = _LightColor0.rgb;
                float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;
                albedo *= tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;
                // albedo *= tex2D(_HeightMap, i.uv);
                // 纯介电材质也有高光反射，使用内置函数
                float3 specularTint;
                float oneMinusReflectivity;
                albedo = DiffuseAndSpecularFromMetallic(albedo, GetMetallic(i), specularTint, oneMinusReflectivity);

                // UnityLight light;
                // light.color = lightColor;
                // light.dir = lightDir;
                // light.ndotl = DotClamped(i.normal, lightDir);
                // UnityIndirect indirectLight;
                // indirectLight.diffuse = 0;
                // indirectLight.specular = 0;
                float4 color = UNITY_BRDF_PBS(albedo, specularTint, oneMinusReflectivity, GetSmoothness(i), i.normal, viewDir, CreateLight(i), CreateIndirectLight(i, viewDir));
                color.rgb += GetEmission(i);
                return color;
            }
            ENDCG
        }
    }

    CustomEditor "MyLightingShaderGUI"
}
