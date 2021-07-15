Shader "coffeecat/BasicRender/SingleLights"
{
    Properties
    {
        _Tint ("Tint", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}
        // [NoScaleOffset] _HeightMap ("Heights", 2D) = "gray" {}
        [NoScaleOffset] _NormalMap ("Normals", 2D) = "bump"{}
        _BumpScale ("Bump Scale", Float) = 1
        [Gamma]_Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _DetailTex ("Detail Albedo", 2D) = "gray" {}
        [NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" {}
        _DetailBumpScale ("Detail Bump Scale", Float) = 1
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
            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram
            #define BINORMAL_PER_FRAGMENT
            #define FORWARD_BASE_PASS

            // #include "UnityCG.cginc"
            // #include "UnityStandardBRDF.cginc"
            // #include "UnityStandardUtils.cginc"
            #include "UnityPBSLighting.cginc"

            float4 _Tint;
            sampler2D _MainTex, _DetailTex;
            float4 _MainTex_ST, _DetailTex_ST;
            // sampler2D _HeightMap;
            // float4 _HeightMap_TexelSize;
            sampler2D _NormalMap, _DetailNormalMap;
            float _BumpScale, _DetailBumpScale;
            float _Metallic;
            float _Smoothness;

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
                // float2 uv : TEXCOORD0;
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
            };

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
                // ComputeVertexLightColor(i);
                return i;
            }

            // 调整法线
            // void InitializeFragmentNormal(inout Interpolators i)
            // {
            //     // float h = tex2D(_HeightMap, i.uv);
            //     // i.normal = float3(0, h, 0);
            //     // 从切线到法线
            //     float2 du = float2(_HeightMap_TexelSize.x * 0.5, 0);
            //     float u1 = tex2D(_HeightMap, i.uv - du);
            //     float u2 = tex2D(_HeightMap, i.uv + du);
            //     // float3 tu = float3(1, u2 - u1, 0);

            //     float2 dv = float2(0, _HeightMap_TexelSize.y * 0.5);
            //     float v1 = tex2D(_HeightMap, i.uv - dv);
            //     float v2 = tex2D(_HeightMap, i.uv + dv);
            //     // float3 tv = float3(0, v2 - v1, 1);

            //     // i.normal = cross(tv, tu);
            //     i.normal = float3(u1 - u2, 1, v1 - v2);
            //     i.normal = normalize(i.normal);
            // }
            // 使用法线贴图代替高度贴图
            void InitializeFragmentNormal(inout Interpolators i)
            {
                //通过计算2N-1之后将法线转换回其原始的-1~1的范围。
                // i.normal = tex2D(_NormalMap, i.uv).rgb * 2 - 1;
                // i.normal.xy = tex2D(_NormalMap, i.uv).ag * 2 - 1;
                // i.normal.xy *= _BumpScale;
                // i.normal.z = sqrt(1 - saturate(dot(i.normal.xy, i.normal.xy)));
                
                float3 mainNormal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
                float3 detailNormal = UnpackScaleNormal(tex2D(_DetailNormalMap, i.uv.zw), _DetailBumpScale);
                
                //使用偏导数
                // i.normal = float3(mainNormal.xy / mainNormal.z + detailNormal.xy / detailNormal.z, 1);
                //使用泛白混合（whiteout blending）
                // i.normal = float3(mainNormal.xy + detailNormal.xy, mainNormal.z * detailNormal.z);
                //使用封装的函数替代泛白混合
                float3 tangentSpaceNormal = BlendNormals(mainNormal, detailNormal);
                // tangentSpaceNormal = tangentSpaceNormal.xzy;
                // float3 binormal = cross(i.normal, i.tangent.xyz) * (i.tangent.w * unity_WorldTransformParams.w);
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
                // return float4(i.normal * 0.5 + 0.5, 1);
                // return dot(float3(0, 1, 0), i.normal);
                // return max(0, dot(float3(0, 1, 0), i.normal));
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
                albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

                UnityLight light;
                light.color = lightColor;
                light.dir = lightDir;
                light.ndotl = DotClamped(i.normal, lightDir);
                UnityIndirect indirectLight;
                indirectLight.diffuse = 0;
                indirectLight.specular = 0;
                float4 color = UNITY_BRDF_PBS(albedo, specularTint, oneMinusReflectivity, _Smoothness, i.normal, viewDir, light, indirectLight);
                return color;
            }

                        // float4 MyFragmentProgram(Interpolators i) : SV_TARGET
            // {
            //     i.normal = normalize(i.normal);
            //     // return float4(i.normal * 0.5 + 0.5, 1);
            //     // return dot(float3(0, 1, 0), i.normal);
            //     // return max(0, dot(float3(0, 1, 0), i.normal));
            //     float3 lightDir = _WorldSpaceLightPos0.xyz;
            //     float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
            //     // return DotClamped(lightDir, i.normal);
            //     float3 lightColor = _LightColor0.rgb;
            //     float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
            //     // 能量守恒
            //     // albedo *= 1 - _SpecularTint.rgb;
            //     // 单色能量守恒
            //     // albedo *= 1 - max(_SpecularTint.r, max(_SpecularTint.g, _SpecularTint.b));
            //     // 使用内置函数取代单色能量守恒
            //     // float oneMinusReflectivity;
            //     // albedo = EnergyConservationBetweenDiffuseAndSpecular(albedo, _SpecularTint.rgb, oneMinusReflectivity);
            //     // 使用金属度滑块切换金属和非金属
            //     // float3 specularTint = albedo * _Metallic;
            //     // float oneMinusReflectivity = 1 - _Metallic;
            //     // albedo *= oneMinusReflectivity;
            //     // 纯介电材质也有高光反射，使用内置函数
            //     float3 specularTint;
            //     float oneMinusReflectivity;
            //     albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);
            //     float3 diffuse = albedo * lightColor * DotClamped(lightDir, i.normal);
            //     // return float4(diffuse, 1);
            //     // 反射
            //     float3 reflectionDir = reflect(-lightDir, i.normal);
            //     // return float4(reflectionDir * 0.5 + 0.5, 1);
            //     // return DotClamped(viewDir, reflectionDir);
            //     // 光滑度
            //     // return pow(DotClamped(viewDir, reflectionDir), _Smoothness * 100);
            //     // Blinn-Phong 半角向量
            //     float3 halfVector = normalize(lightDir + viewDir);
            //     // return pow(DotClamped(halfVector, i.normal), _Smoothness * 100);
            //     // 高光颜色
            //     // float3 specular = _SpecularTint.rgb * lightColor * pow(DotClamped(halfVector, i.normal), _Smoothness * 100);
            //     float3 specular = specularTint * lightColor * pow(DotClamped(halfVector, i.normal), _Smoothness * 100);
            //     // return float4(specular, 1);
            //     return float4(diffuse + specular, 1);
            // }
            ENDCG
        }
    }

    // CustomEditor "MyLightingShaderGUI"
}
