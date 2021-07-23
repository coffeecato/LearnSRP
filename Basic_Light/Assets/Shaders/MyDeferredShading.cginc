#if !defined(MY_DEFERRED_SHADING)
#define MY_DEFERRED_SHADING

#include "UnityCG.cginc"


            // #include "UnityCG.cginc"
            #include "UnityPBSLighting.cginc"

            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;
            float4 _LightColor, _LightDir;
            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

            struct VertexData
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct Interpolators
            {
                float4 pos : SV_POSITION;
                float4 uv : TEXCOORD0;
                float3 ray : TEXCOORD1;
            };

            Interpolators VertexProgram(VertexData v)
            {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.uv = ComputeScreenPos(i.pos);
                i.ray = v.normal;
                return i;
            }

            UnityLight CreateLight()
            {
                UnityLight light;
                light.color = _LightColor.rgb;
                light.dir = -_LightDir;
                return light;
            }

            float4 FragmentProgram(Interpolators i) : SV_Target
            {
                float2 uv = i.uv.xy / i.uv.w;

                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
                depth = Linear01Depth(depth);
                float3 rayToFarPlane = i.ray * _ProjectionParams.z / i.ray.z;
                float3 viewPos = rayToFarPlane * depth;
                float3 worldPos = mul(unity_CameraToWorld, float4(viewPos, 1)).xyz;
                // 计算BRDF 1.需要视角方向
                float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);
                
                float3 albedo = tex2D(_CameraGBufferTexture0, uv).rgb;
                float3 specularTint = tex2D(_CameraGBufferTexture1, uv).rgb;
                float3 smoothness = tex2D(_CameraGBufferTexture1, uv).a;
                float3 normal = tex2D(_CameraGBufferTexture2, uv).rgb * 2 - 1;
                // 计算BRDF 2.需要表面反射系数
                float oneMinuesReflectivity = 1 - SpecularStrength(specularTint);
                // 计算BRDF 3.需要灯光数据
                UnityLight light = CreateLight();
                UnityIndirect indirectLight;
                indirectLight.diffuse = 0;
                indirectLight.specular = 0;

                float4 color = UNITY_BRDF_PBS(albedo, specularTint, oneMinuesReflectivity, smoothness, normal, viewDir, light, indirectLight);
                return color;
            }

#endif
