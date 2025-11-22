Shader "NPRFaceGbuffer"
{
    Properties
    {
        [FoldoutBegin(_FoldoutTexEnd)]_FoldoutTex("基础色", Float) = 0
        _MainTex ("基础贴图",2D) = "white"{}
        [HDR]_MainColor("基础颜色",Color)=(1,1,1)
    	[Toggle(_USEUV2_ON)]_SDFUV2("使用uv2采样SDF", Float)= 0
        _SDFTex("SDF贴图",2D)="white"{}
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
    	_ShadowSmoothNdotL                      ("ShadowSmoothNdotL", Range(0, 1))      = 0.25
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
            Name "NPRBase"
            Tags 
            {
                "LightMode"="UniversalGBuffer"
            }
            Stencil//untiy 正常该有的模板测试
		    {
		        Ref 32
		        ReadMask 0
		        //WriteMask 96
		        Comp Always
		        Pass Replace
		        Fail Keep
		        ZFail Keep
		    }
            HLSLPROGRAM
            #pragma vertex Basevert
            #pragma fragment Facefrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Library/FxLibrary.hlsl"
            #pragma multi_compile _ _USEUV2_ON
            #pragma multi_compile _ _SHADOW_RAMP
            
            CBUFFER_START(UnityPerMaterial)
			float4 _MainTex_ST;
			float4 _BrushTex_ST;

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
            float3 _FaceFrontDirWS;
            float3 _FaceRightDirWS;
			float3 _MainColor;
			float3 _StrokeColor;
			float3 _ShadowStrokeColor;
			float3 _ShadowColor;
			float3 _MidColor;
			float3 _LowColor;
			float3 _HighlightsColor;
            float _ShadowSmoothNdotL;

			CBUFFER_END
			TEXTURE2D(_MainTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_MainTex);
			TEXTURE2D(_ShadowRampTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_ShadowRampTex);
			TEXTURE2D(_BrushTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_BrushTex);
			TEXTURE2D(_SDFTex);//在CG中会写成sampler2D _MainTex;
			SAMPLER(sampler_SDFTex);

            struct a2v
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
	            float4 uv1 : TEXCOORD1;
                float3 normal : NORMAL;
            };
            struct v2f
            {
                float4 posCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            	float2 uv1 : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                float3 nDirWS : TEXCOORD3;
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
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
	            o.uv1 = v.uv1;
                return o;
            }
            DeferredOutPut Facefrag(v2f i) : SV_Target
			{
				DeferredOutPut g;

				//取数据
				float3 lDirWS =  normalize(_MainLightPosition.xyz);
				float3 nDirWS = normalize(i.nDirWS);
				float2 SDFUV = i.uv;
				#if _USEUV2_ON
				SDFUV = i.uv1;
				#endif
				//float3 frontDir = TransformObjectToWorldDir(float3(0.0,0.0,1.0));
				//float3 rightDir = TransformObjectToWorldDir(float3(1.0,0.0,0.0));
				float3 frontDir = _FaceFrontDirWS;   //使用外部脚本传递的前向
				float3 rightDir = _FaceRightDirWS;
				float2 faceLightDot;
				faceLightDot.x = dot(rightDir.xz,lDirWS.xz);
				faceLightDot.y = saturate(dot(-lDirWS.xz, frontDir.xz) * 0.5 + 0.5);//这里的0是阴影的偏移值，之后要改成可任意调节的Ramge值
				SDFUV.x = faceLightDot.x < 0 ? SDFUV.x: 1-SDFUV.x;
				
				//拿数据

				float3 vDirWS = normalize(GetCameraPositionWS() - i.posWS);
				float3 hDirWS = normalize(vDirWS+lDirWS);

				//一些中间量
				float NdotL = max(0.0,dot(nDirWS,lDirWS));
				float NdotV = max(0.0,dot(nDirWS,vDirWS));
				float NdotH = max(dot(nDirWS,hDirWS),0.0);
				float VdotH = max(dot(vDirWS,hDirWS),0.0);
				float halfLambert = NdotL*0.5+0.5;
				
			    //贴图采样
			    float4 ver_MainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
				float4 ver_SDFTex = SAMPLE_TEXTURE2D(_SDFTex, sampler_SDFTex, SDFUV);
				//分别提取SDF的数据
				float diffuseSDF = ver_SDFTex.r;
				//diffuseSDF = diffuseSDF*1.2-0.6;
				float SpecularSDF = ver_SDFTex.g;
				float SSSSDF = ver_SDFTex.b;
				float MaskSDF = ver_SDFTex.a;
				float3 diffuse;

				#ifdef _SHADOW_RAMP
				//漫反射（其二有ramp）
				float faceMapShadow = sigmoid(diffuseSDF, faceLightDot.y, _ShadowSmoothNdotL * 5) * MaskSDF;
                float shadowArea = faceMapShadow; // Face Modify shadow
				float3 RampTex = SAMPLE_TEXTURE2D(_ShadowRampTex, sampler_ShadowRampTex, float2(shadowArea,0.125));
				diffuse = RampTex*ver_MainTex*_MainColor;
				#else
				
				//漫反射项其一（无ramp时）
				//计算面部阴影
				float3 Albedo = _MainColor*ver_MainTex;
				float2 uv2 = i.uv*_BrushTex_ST.xy+_BrushTex_ST.zw;
				float3 Brush = SAMPLE_TEXTURE2D(_BrushTex,sampler_BrushTex,uv2);
				float faceMapShadow = sigmoid(diffuseSDF, faceLightDot.y, 0.1 * 5)*MaskSDF;
				half HLightSig = sigmoid(faceMapShadow, clamp(_Range1*(1+(1-Brush.r)*_BrushHard1),0.01,0.99), _RangeB);
				half MidSig = sigmoid(faceMapShadow, clamp(_Range2*(1+(1-Brush.g)*_BrushHard2),0.01,0.99), _RangeB);
				half DarkSig = sigmoid(faceMapShadow, clamp(_Range3*(1+(1-Brush.b)*_BrushHard3),0.01,0.99), _RangeB);
				//用皮肤同款算法应对面部阴影
				float3 combinedColor = ver_MainTex*_HighlightsColor;
				combinedColor = lerp(_ShadowColor,combinedColor,HLightSig);
				combinedColor = lerp(_MidColor,combinedColor,MidSig);
				combinedColor = lerp(_LowColor,combinedColor,DarkSig);
				diffuse = combinedColor;
				#endif
				
				
				//镜面反射
				// Nose Spec
				float faceSpecStep = clamp(faceLightDot.y, 0.001, 0.999);
				SDFUV.x = 1 - SDFUV.x;
				float noseSpecArea1 = step(faceSpecStep, ver_SDFTex.g);
				float noseSpecArea2 = step(1 - faceSpecStep, ver_SDFTex.b);
				float noseSpecArea = noseSpecArea1 * noseSpecArea2;
				noseSpecArea *= smoothstep(0, 0.5, 1 - faceLightDot.y);
				float specular = noseSpecArea;
				//输出准备
				float3 rgb = specular+diffuse;
				nDirWS = EyPackNormal(nDirWS);
			    //输出倒Gbuffer
			    g.gBuffer0 = float4(rgb,0.0);//RGB：基础色 A:粗糙度
			    g.gBuffer1 = float4(0,0,0,1);//RGB ：F0项，A：映射ID
			    g.gBuffer2 = float4(nDirWS,0);//RGB:法线 A：场景or角色
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
            Cull Front
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
