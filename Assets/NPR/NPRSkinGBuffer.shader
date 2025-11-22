Shader "NPRSkinGBuffer"
{
    Properties
    {
        [FoldoutBegin(_FoldoutTexEnd)]_FoldoutTex("基础色", Float) = 0
        _MainTex ("基础贴图",2D) = "white"{}
        [HDR]_MainColor("基础颜色",Color)=(1,1,1)
        _SSSLUT ("SSSLUT",2D) = "white"{}
        _BrushTex("笔刷纹理",2D) = "white"{}
        [HDR]_HighlightsColor("亮部颜色",Color)=(1,1,1)
        _ShadowColor("暗部颜色1",Color)=(1,1,1)
        _MidColor("暗部颜色2",Color)=(1,1,1)
        _LowColor("暗部颜色3",Color)=(1,1,1)
        _Range1("阈值1",Range(0,1))=1
        _Range2("阈值2",Range(0,1))=1
        _Range3("阈值3",Range(0,1))=1
        _RangeB("阈值B",Range(0,3))=1
        _BrushHard1("笔刷强度1",Range(0,1))=1
        _BrushHard2("笔刷强度2",Range(0,1))=1
        _BrushHard3("笔刷强度3",Range(0,1))=1
        _AmbientStrength("环境光强度",Range(0,0.1))=0.01
        [FoldoutEnd]_FoldoutTexEnd("_FoldoutEnd", Float) = 0
        
        
        _Metalness("金属度",Range(0,1))=0
        _MetalnessMap("金属度贴图",2D)="white"{}
        _Roughness("粗糙度",Range(0,1))=0
        _RoughnessMap("粗糙度贴图",2D)="white"{}
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
        [FoldoutEnd]_FoldoutShadowRampEnd("_FoldoutEnd", Float) = 0
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
            Name "NPRSkin"
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
            #pragma fragment Skinfrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"

            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
			float4 _BrushTex_ST;
			float _Roughness;
			float _Metalness;
			float _OutlineClampScale;
			//皮肤
			float _Range1;
			float _Range2;
			float _Range3;
			float _RangeB;
			float _BrushHard1;
			float _BrushHard2;
			float _BrushHard3;
			float _AmbientStrength;
			float3 _MainColor;
			float3 _StrokeColor;
			float3 _ShadowStrokeColor;
			float3 _ShadowColor;
			float3 _MidColor;
			float3 _LowColor;
			float3 _HighlightsColor;


			CBUFFER_END
			TEXTURE2D(_MainTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MainTex);
			TEXTURE2D(_RoughnessMap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_RoughnessMap);
			TEXTURE2D(_MetalnessMap);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MetalnessMap);
			TEXTURE2D(_LUT);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_LUT);
			TEXTURE2D(_ShadowRampTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_ShadowRampTex);
			TEXTURE2D(_SSSLUT);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_SSSLUT);
			TEXTURE2D(_BrushTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_BrushTex);


            

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
                return o;
            }
            //皮肤渲染所用着色器
			DeferredOutPut Skinfrag(v2f i) : SV_Target
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
				float3 tDirWS = normalize(i.tDirWS);
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
				float halfLambert = NdotL*0.5+0.5;

				//卡渲用Ramp
				float3 ver_ShadowRampTex = SAMPLE_TEXTURE2D(_ShadowRampTex, sampler_ShadowRampTex, float2(NdotL,0.5));
				//尝试采样预积分的LUT
				float3 LUT = SAMPLE_TEXTURE2D(_SSSLUT, sampler_SSSLUT, float2(halfLambert,NdotV));
				//LUT = 1-LUT;
				float2 uv2 = i.uv*_BrushTex_ST.xy+_BrushTex_ST.zw;
				float3 Brush = SAMPLE_TEXTURE2D(_BrushTex,sampler_BrushTex,uv2);
				//NdotL = ver_ShadowRampTex;//尝试NdotL都用ramp

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
				specColor = max(0,specColor);
				//漫反射项
				float3 kd = (1 - F)*(1 - Metalness);
			    float3 Albedo = _MainColor*ver_MainTex;
				float3 diffColor = Albedo * _MainLightColor * LUT.g;
				//卡通渲染漫反射项（先尝试简单的，二分阴影）
				half HLightSig = sigmoid(halfLambert, clamp(_Range1*(1+(1-Brush.r)*_BrushHard1),0.01,0.99), _RangeB);
				half MidSig = sigmoid(halfLambert, clamp(_Range2*(1+(1-Brush.g)*_BrushHard2),0.01,0.99), _RangeB);
				half DarkSig = sigmoid(halfLambert, clamp(_Range3*(1+(1-Brush.b)*_BrushHard3),0.01,0.99), _RangeB);
				//尝试新的混合方式
				float3 combinedColor = Albedo*_HighlightsColor;
				combinedColor = lerp(_ShadowColor,combinedColor,HLightSig);
				combinedColor = lerp(_MidColor,combinedColor,MidSig);
				combinedColor = lerp(_LowColor,combinedColor,DarkSig);

				/*half HLightWin = HLightSig;
				half MidLWin = MidSig - HLightSig;
				half MidDWin = DarkSig - MidSig;
				half DarkWin = 1 - DarkSig;
				float Intensity = HLightWin * 1.0 + MidLWin * 0.8 + MidDWin * 0.5 + DarkWin * 0.3;*/
				//float3 Ey_Color = Albedo*Intensity;
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
				float3 ibl = (iblDiffuseResult+iblSpecularResult)*_AmbientStrength;
				//输出准备
				float3 rgb = combinedColor+specColor;
				nDirWS = EyPackNormal(nDirWS);
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(rgb,1.0);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(nDirWS,0);//RGB:法线 A暂无
				g.gBuffer3 = float4(0,0,0,1);
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
