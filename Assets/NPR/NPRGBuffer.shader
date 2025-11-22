Shader "NPRGBuffer"
{
    Properties
    {
    	[Toggle] _SceneSwitch ("场景开关", Int) = 0
        [FoldoutBegin(_FoldoutTexEnd)]_FoldoutTex("基础色", Float) = 0
        _MainTex ("基础贴图",2D) = "white"{}
        [HDR]_BaseColor("基础颜色",Color)=(1,1,1)
        [FoldoutEnd]_FoldoutTexEnd("_FoldoutEnd", Float) = 0
        
        [FoldoutBegin(_FoldoutEnd2, _USENORMALMAP_ON)]_FoldoutWithKey("法线开关", float) = 0
        [HideInInspector]_USENORMALMAP_ON("_USENORMALMAP_ON", float) = 0
        _NormalMap("法线贴图",2D)="white"{}
        [FoldoutEnd]_FoldoutEnd2("FoldoutEnd2", float) = 0
        
        _Metalness("金属度",Range(0,1))=0
    	_Roughness("粗糙度",Range(0,1))=0
        _RMOMap("RMO贴图",2D)="white"{}
        
    	_LUT("LUT",2D)="white"{}
        
        [FoldoutBegin(_FoldoutEnd3, _USESTROKE_ON)]_FoldoutWithKey2("描边开关", float) = 0
        [HideInInspector]_USESTROKE_ON("_USESTROKE_ON", float) = 0
        [Toggle(_USESMOOTHNORMAL_ON)]_SmoothNormal("使用平滑法线", Float)= 0
        [HDR]_StrokeColor("描边颜色",Color)=(0,0,0)
        [HDR]_ShadowStrokeColor("描边暗部颜色",Color)=(0,0,0)
        _OutlineWidth("描边宽度",Range(0,10))=2
        _OutlineClampScale("描边偏移",Range(0,4))=0
        [FoldoutEnd]_FoldoutEnd3("FoldoutEnd3", float) = 0
        
        // Ramp
        [FoldoutBegin(_FoldoutShadowRampEnd, _SHADOW_RAMP)]_FoldoutShadowRamp("ShadowRamp", Float) = 0
        [HideInInspector]_SHADOW_RAMP("_SHADOW_RAMP", Float) = 0
        [Ramp]_ShadowRampTex("ShadowRampTex", 2D)= "white" { }
    	_ShadowOffset("阴影偏移", Range(-1, 1)) = 0.5
	    _ShadowSmoothNdotL("阴影软硬", Range(0, 0.1)) = 0.25
        [FoldoutEnd]_FoldoutShadowRampEnd("_FoldoutEnd", Float) = 0
    }
    SubShader
    {
        Tags 
        {
            "RenderType"="Opaque"
        }
        Cull Off
        //渲染的pass
        Pass
        {
            Name "NPRBase"
            Tags 
            {
                "LightMode"="UniversalGBuffer"
            }
            Stencil//untiy 正常该有的模板测试
		    {
		        Ref 32
		        ReadMask 0
		        WriteMask 96
		        Comp Always
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
            
            #pragma vertex Basevert
            #pragma fragment Basefrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"
            //#include "Assets/NPR/NPR.hlsl"
            #pragma multi_compile _ _USENORMALMAP_ON
            #pragma multi_compile _ _SHADOW_RAMP

            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
			float _NormalMapToggle;
			float _Roughness;
			float _Metalness;
			float _OutlineClampScale;
            float _ShadowOffset;
            float _ShadowSmoothNdotL;
            int _SceneSwitch;
			float3 _BaseColor;
			float3 _StrokeColor;
			float3 _ShadowStrokeColor;

			CBUFFER_END
			TEXTURE2D(_MainTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MainTex);
			TEXTURE2D(_NormalMap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_NormalMap);
			TEXTURE2D(_RMOMap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_RMOMap);
			TEXTURE2D(_LUT);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_LUT);
			TEXTURE2D(_ShadowRampTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_ShadowRampTex);

            

            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
	            float4 uv1 : TEXCOORD1;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };
            struct v2f
            {
                float4 posCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 scrPos : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 nDirWS : TEXCOORD3;
                float3 tDirWS : TEXCOORD4;
                float3 bDirWS :TEXCOORD5;
	            float2 uv1 : TEXCOORD6;
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
            };
            //将Gubffer打包成结构体输出
            struct DeferredOutPut{
                float4 gBuffer0 : SV_TARGET0;
                float4 gBuffer1 : SV_TARGET1;
                float4 gBuffer2 : SV_TARGET2;
                float4 gBuffer3 : SV_TARGET3;
            };

            v2f Basevert(a2v v)
            {
                v2f o;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.posCS = vertexInput.positionCS;
                o.posWS = vertexInput.positionWS;
                o.nDirWS = TransformObjectToWorldNormal(v.normal.xyz) ;
                o.tDirWS = real3(TransformObjectToWorldDir(v.tangent.xyz));
                o.bDirWS = cross(o.nDirWS,o.tDirWS)*v.tangent.w*GetOddNegativeScale();
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	            o.uv1 = v.uv1;
                o.scrPos = ComputeScreenPos(vertexInput.positionCS);
                return o;
            }

            DeferredOutPut Basefrag(v2f i) : SV_Target
			{
			    DeferredOutPut g;
			    //贴图采样
			    float4 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
				float4 ver_RMOMap = SAMPLE_TEXTURE2D(_RMOMap, sampler_RMOMap, i.uv);
			    //拿数据
				float Roughness = _Roughness*ver_RMOMap.r;
				float Metalness = _Metalness*ver_RMOMap.g;
				float AO = ver_RMOMap.b;
				float3 vDirWS = normalize(GetCameraPositionWS() - i.posWS);
			    float3 lDirWS =  normalize(_MainLightPosition.xyz);
				float3 hDirWS = normalize(vDirWS+lDirWS);
			    float3 nDirWS = normalize(i.nDirWS);
				float3 tDirWS = normalize(i.tDirWS);
				float3 bDirWS = normalize(i.bDirWS);
				//如果法线贴图开关开启就TBN矩阵
				#if _USENORMALMAP_ON
					float4 ver_NormalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv);
					nDirWS = TBNNormal(ver_NormalMap.rg,tDirWS,bDirWS,nDirWS);
			    #endif

				//一些中间量
				float NdotL = max(0.0,dot(nDirWS,lDirWS));
				float NdotV = max(0.0,dot(nDirWS,vDirWS));
				float NdotH = max(dot(nDirWS,hDirWS),0.0);
				float VdotH = max(dot(vDirWS,hDirWS),0.0);
				float halfLambert = dot(nDirWS,lDirWS)*0.5+0.5;

				

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
				float3 F0 =lerp(float3(0.04, 0.04, 0.04), _BaseColor*ver_MainTex.rgb, Metalness);//F0也是高光度工作流的SpecColor
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
			    float3 Albedo = _BaseColor*ver_MainTex;
				float3 diffColor = kd * Albedo * _MainLightColor * NdotL;
				#if _SHADOW_RAMP
				halfLambert = sigmoidTrue(halfLambert,_ShadowOffset,_ShadowSmoothNdotL);
				float3 RampTex = SAMPLE_TEXTURE2D(_ShadowRampTex, sampler_ShadowRampTex, float2(halfLambert,0.125));
				diffColor = RampTex*Albedo*_MainLightColor;
				#else
				diffColor = Albedo  * NdotL;
			    #endif
				//混合直接光照
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
				//混合环境光
				float3 ibl = iblDiffuseResult+iblSpecularResult;
				

				//输出准备
				nDirWS = EyPackNormal(nDirWS);
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(diffColor*AO,1.0);//RGB：漫反射 
			    g.gBuffer1 = float4(F0,Roughness);//RGB ：F0项，A：粗糙度
			    g.gBuffer2 = float4(nDirWS,_SceneSwitch);//RGB:法线 A：场景与角色遮罩
				g.gBuffer3 = float4(ibl*AO,1);
				return g;
			}
            ENDHLSL
        }
		Pass
        {
            Name "NPRStroke"
            Tags 
            {
                "LightMode"="EyNPRStrokeGBuffer"
            }
            Cull Front
            Stencil//untiy 正常该有的模板测试
		    {
		        Ref 32
		        ReadMask 0
		        WriteMask 96
		        Comp Always
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
                #pragma vertex Strokevert
                #pragma fragment Strokefrag
                #include "Assets/NPR/NPR.hlsl"
                #pragma multi_compile _ _USESTROKE_ON
                #pragma multi_compile _ _USESMOOTHNORMAL_ON
            ENDHLSL
        }
    }
    CustomEditor "UnityEditor.DanbaidongGUI.DanbaidongGUI"
}
