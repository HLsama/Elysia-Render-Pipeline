Shader "BlueRed"
{
    Properties
    {
        _MainTex ("基础贴图",2D) = "white"{}
        _NormalMap("法线贴图",2D)="white"{}
        _Metalness("金属度",Range(0,1))=0
        _MetalnessMap("金属度贴图",2D)="white"{}
        _Roughness("粗糙度",Range(0,1))=0
        _RoughnessMap("粗糙度贴图",2D)="white"{}
    	[HDR]_MainColor("基础颜色",Color)=(1,1,1)
    	_LUT("LUT",2D)="white"{}
    }
    SubShader
    {
        Tags 
        {
            "RenderType"="Opaque"
        }
        //渲染的pass
        Pass
        {
            Tags
            {
                "LightMode"="UniversalGBuffer"
            }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"

            #pragma multi_compile _ _USENORMALMAP_ON  
            
            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };
            struct v2f
            {
                float4 posCS : SV_POSITION;
                float2 uv : TEXCOORD;
                float4 scrPos : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 nDirWS : TEXCOORD3;
                float3 tDirWS : TEXCOORD4;
            	float3 bDirWS :TEXCOORD5;
            	DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
            };
            //将Gubffer打包成结构体输出
            struct DeferredOutPut{
                float4 gBuffer0 : SV_TARGET0;
                float4 gBuffer1 : SV_TARGET1;
                float4 gBuffer2 : SV_TARGET2;
                float4 gBuffer3 : SV_TARGET3;
            };

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float _NormalMapToggle;
            float _Roughness;
            float _Metalness;
            float3 _MainColor;


			CBUFFER_END
            TEXTURE2D(_MainTex);//在CG中会写成sampler2D _MainTex;
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);//在CG中会写成sampler2D _MainTex;
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RoughnessMap);//在CG中会写成sampler2D _MainTex;
            SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_MetalnessMap);//在CG中会写成sampler2D _MainTex;
            SAMPLER(sampler_MetalnessMap);
            TEXTURE2D(_LUT);//在CG中会写成sampler2D _MainTex;
            SAMPLER(sampler_LUT);

            v2f vert(a2v v)
            {
                v2f o;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.posCS = vertexInput.positionCS;
                o.posWS = vertexInput.positionWS;
                o.nDirWS = TransformObjectToWorldNormal(v.normal.xyz) ;
                o.tDirWS = real3(TransformObjectToWorldDir(v.tangent.xyz));
            	o.bDirWS = cross(o.nDirWS,o.tDirWS)*v.tangent.w*GetOddNegativeScale();
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.scrPos = ComputeScreenPos(vertexInput.positionCS);
                return o;
            }
            DeferredOutPut frag(v2f i) : SV_Target
			{
			    DeferredOutPut g;
                //贴图采样
			    float4 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
				float ver_RoughnessMap = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, i.uv).r;
				float ver_MetalnessMap = SAMPLE_TEXTURE2D(_MetalnessMap, sampler_MetalnessMap, i.uv).r;
			    //拿数据
				float Roughness = _Roughness*ver_RoughnessMap;
				float Metalness = _Metalness*ver_MetalnessMap;
				float3 vDirWS = normalize(GetCameraPositionWS() - i.posWS);
			    float3 lDirWS =  normalize(_MainLightPosition.xyz);
				float3 hDirWS = normalize(vDirWS+lDirWS);
			    float3 nDirWS = normalize(i.nDirWS);
				float3 tDirWS = normalize(i.nDirWS);
				float3 bDirWS = normalize(i.bDirWS);
				//如果法线贴图开关开启就TBN矩阵
				#if _USENORMALMAP_ON
					float4 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
					ver_NormalMap = normalize(ver_NormalMap*2-1);
                    float3x3 TBN = float3x3(tDirWS,bDirWS,nDirWS);
					nDirWS = normalize(mul(ver_NormalMap,TBN));
                #endif

				//一些中间量
				float NdotL = max(0.0,dot(nDirWS,lDirWS));
				float NdotV = max(0.0,dot(nDirWS,vDirWS));
				float NdotH = max(dot(nDirWS,hDirWS),0.0);
				float VdotH = max(dot(vDirWS,hDirWS),0.0);

				//直接光照
				//镜面反射项
				//1.D法线分布函数（GGX）
				Roughness = lerp(0.002,1,Roughness);
				float a2 = Roughness*Roughness;
				float NdotH2 = NdotH*NdotH;
				float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
				denom = PI * denom * denom;
				denom = max(0.00001,denom);
				float D = a2/denom;
				//2.F菲涅尔方程
				float3 F0 =lerp(float3(0.04, 0.04, 0.04), _MainColor*ver_MainTex.rgb, Metalness);//F0也是高光度工作流的SpecColor
				float3 F = F0 + (1 - F0) * exp2((-5.55473 * VdotH - 6.98316) * VdotH);
				//3.G.几何遮蔽项
				float k = pow(Roughness+1,2)/8;
				float GLeft = NdotL/lerp(NdotL,1,k);
				float GRight = NdotV/lerp(NdotV,1,k);
				float G = GLeft*GRight;
				//混合高光项
				float3 SpecularResult = (D * G * F * 0.25) / (NdotV * NdotL);
				float3 specColor = SpecularResult * _MainLightColor * NdotL * PI;
				//漫反射项
				float3 kd = (1 - F)*(1 - Metalness);
                float3 Albedo = _MainColor*ver_MainTex;
				float3 diffColor = kd * Albedo * _MainLightColor * NdotL;
				//混合漫反射项
				float3 DirectLightResult = diffColor + specColor;
				//环境光项
				//镜面反射项
				float3 reflectDirWS = reflect(-vDirWS,nDirWS);
				half mip = PerceptualRoughnessToMipmapLevel(Roughness);
				half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDirWS, mip));
				float3 indirectSpecular = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
				float2 envBDRF = SAMPLE_TEXTURE2D(_LUT, sampler_LUT,float2(lerp(0, 0.99, max(NdotV,0.00001)), lerp(0, 0.99, Roughness*Roughness))).rg; // LUT采样
                float3 Flast = fresnelSchlickRoughness(max(NdotV, 0.0), F0, Roughness*Roughness);
                float3 iblSpecularResult = indirectSpecular * (Flast * envBDRF.r + envBDRF.g);
				//漫反射项
				float kdLast = (1 - Flast) * (1 - Metalness);
				half3 ambient_contrib = SAMPLE_GI(input.staticLightmapUV, i.vertexSH, nDirWS);
				float3 ambient = 0.03 * Albedo;
				float3 iblDiffuse = max(half3(0, 0, 0), ambient.rgb + ambient_contrib);
				float3 iblDiffuseResult = iblDiffuse * kdLast * Albedo;
				

				
				//输出前准备
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(DirectLightResult,1);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(0,0,0,1);//RGB:法线 A暂无
				g.gBuffer3 = float4(iblDiffuseResult+iblSpecularResult,1);
				return g;
			}
            ENDHLSL
        }
    }
    CustomEditor "EyShaderGUI"
}
